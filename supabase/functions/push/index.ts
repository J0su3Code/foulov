// Notification « Nouveau message » (docs/SECURITY.md §9) : texte fixe, sans contenu, sans nom.
//
// Appelée par le déclencheur `envelopes_notify` avec le seul identifiant d'une enveloppe. N'importe qui peut
// l'appeler, mais elle ne fait rien d'autre que vérifier elle-même, avec la clé de service :
//   - que l'enveloppe existe, qu'elle est urgente et récente (2 min) ;
//   - qu'elle n'a pas déjà été notifiée (marquage atomique `pushed_at`).
// Elle n'a jamais accès au contenu : il est chiffré de bout en bout.
//
// Secret requis (jamais dans le dépôt) : FCM_SERVICE_ACCOUNT, le JSON du compte de service Firebase.

import { createClient } from "npm:@supabase/supabase-js@2.49.4";

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false },
});

type ServiceAccount = { project_id: string; client_email: string; private_key: string };
const account: ServiceAccount = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

// ------------------------------------------------------------------ jeton d'accès Google (OAuth 2, JWT RS256)

let cached: { token: string; until: number } | null = null;

const b64url = (b: ArrayBuffer | Uint8Array | string) => {
  const bytes = typeof b === "string" ? new TextEncoder().encode(b) : new Uint8Array(b);
  let s = "";
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

async function accessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.until > now + 60) return cached.token;
  const pem = account.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const head = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const sig = b64url(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(`${head}.${claims}`)));
  const r = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${head}.${claims}.${sig}` }),
  });
  if (!r.ok) throw new Error(`oauth ${r.status}`);
  const j = await r.json();
  cached = { token: j.access_token, until: now + (j.expires_in ?? 3600) };
  return cached.token;
}

// ------------------------------------------------------------------ envoi

// Texte fixe : le serveur ne sait rien du message, et l'écran verrouillé n'en montre rien.
const message = (fid: string) => ({
  message: {
    // Identifiant d'installation Firebase (FID), cible recommandée par FCM (le champ `token` est déprécié).
    fid,
    notification: { title: "FouLove", body: "Nouveau message 💌" },
    android: {
      priority: "HIGH",
      // Plusieurs messages d'affilée : une seule notification, remplacée.
      collapse_key: "messages",
      notification: { channel_id: "messages", tag: "messages", icon: "ic_notification", color: "#F29BB8" },
    },
    apns: {
      headers: { "apns-priority": "10", "apns-collapse-id": "messages" },
      payload: { aps: { sound: "default", "thread-id": "messages" } },
    },
  },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response(null, { status: 405 });
  let id: unknown;
  try {
    id = (await req.json())?.envelope_id;
  } catch {
    return new Response(null, { status: 400 });
  }
  if (typeof id !== "string" || !UUID.test(id)) return new Response(null, { status: 400 });

  // Marquage atomique : une seule notification par enveloppe, même si la fonction est appelée plusieurs fois.
  const { data: env, error } = await db
    .from("envelopes")
    .update({ pushed_at: new Date().toISOString() })
    .eq("id", id)
    .eq("urgent", true)
    .is("pushed_at", null)
    .gt("created_at", new Date(Date.now() - 120_000).toISOString())
    .select("recipient_id")
    .maybeSingle();
  // Déjà reçue (le destinataire avait l'app ouverte et l'a supprimée), déjà notifiée, ou inconnue : rien à faire.
  if (error || !env) return Response.json({ sent: 0 });

  const { data: tokens } = await db.from("push_tokens").select("token").eq("user_id", env.recipient_id);
  if (!tokens?.length || !account.private_key) return Response.json({ sent: 0 });

  const bearer = await accessToken();
  let sent = 0;
  for (const { token } of tokens) {
    const r = await fetch(`https://fcm.googleapis.com/v1/projects/${account.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
      body: JSON.stringify(message(token)),
    });
    if (r.ok) {
      sent++;
      continue;
    }
    const body = await r.text();
    // Application désinstallée ou jeton périmé : on l'oublie.
    // (Seulement dans ces cas sûrs : une erreur de format ne doit jamais effacer un jeton valide.)
    if (r.status === 404 || body.includes("UNREGISTERED")) {
      await db.from("push_tokens").delete().eq("token", token);
    } else {
      console.error("fcm", r.status);
    }
  }
  return Response.json({ sent });
});
