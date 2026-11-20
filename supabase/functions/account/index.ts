// Fermer sa bulle ou supprimer son compte (docs/SECURITY.md §8).
//
// Appelée avec la session de l'utilisateur (JWT vérifié par Supabase). Dans l'ordre :
// 1. les fichiers chiffrés du couple sur R2 (`c/<couple>/…`) sont supprimés, puis sa sauvegarde (`b/<lui>/latest`) ;
// 2. l'espace du couple est supprimé (RPC `leave_couple`, cascade : membres, invitations, enveloppes) ;
// 3. « delete » seulement : son compte est supprimé (cascade : profil, appareil, pré-clés, jetons de notification).
// En cas d'échec au milieu, l'appel peut être relancé : chaque étape supporte d'être refaite.
//
// Secrets : R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET ; SUPABASE_SERVICE_ROLE_KEY (fourni).

import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { presign, type R2 } from "../media/presign.ts";

const r2: R2 = {
  account: Deno.env.get("R2_ACCOUNT_ID")!,
  accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID")!,
  secret: Deno.env.get("R2_SECRET_ACCESS_KEY")!,
  bucket: Deno.env.get("R2_BUCKET")!,
};

// Appel possible depuis le site (page « Supprimer mon compte », sans l'app). L'accès se fait par jeton dans
// l'en-tête Authorization, jamais par cookie : ouvrir le CORS à toute origine ne donne rien de plus à un autre site.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Max-Age": "86400",
};

const json = (body: unknown, status = 200) => Response.json(body, { status, headers: cors });

/// Supprime tous les objets sous un préfixe (liste par pages de 1 000, suppressions par lots de 20 en parallèle).
async function purgePrefix(prefix: string): Promise<number> {
  let removed = 0;
  let token: string | undefined;
  do {
    const query: [string, string][] = [["list-type", "2"], ["prefix", prefix], ["max-keys", "1000"]];
    if (token) query.push(["continuation-token", token]);
    const res = await fetch(await presign(r2, "GET", "", { query }));
    if (!res.ok) throw new Error(`liste R2 ${res.status}`);
    const xml = await res.text();
    const keys = [...xml.matchAll(/<Key>([^<]+)<\/Key>/g)].map((m) => m[1]);
    for (let i = 0; i < keys.length; i += 20) {
      await Promise.all(
        keys.slice(i, i + 20).map(async (k) => {
          const d = await fetch(await presign(r2, "DELETE", k), { method: "DELETE" });
          if (!d.ok && d.status !== 404) throw new Error(`suppression R2 ${d.status}`);
          removed++;
        }),
      );
    }
    token = /<IsTruncated>true<\/IsTruncated>/.test(xml)
      ? xml.match(/<NextContinuationToken>([^<]+)<\/NextContinuationToken>/)?.[1]
      : undefined;
  } while (token);
  return removed;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (req.method !== "POST") return new Response(null, { status: 405, headers: cors });
  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "non authentifié" }, 401);
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: u } = await db.auth.getUser();
  if (!u?.user) return json({ error: "non authentifié" }, 401);
  let body: { action?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "requête invalide" }, 400);
  }
  if (body.action !== "close" && body.action !== "delete") return json({ error: "action inconnue" }, 400);

  try {
    const { data: couple } = await db.rpc("my_couple_id");
    let files = 0;
    // Un identifiant d'espace est un UUID : on n'efface jamais un préfixe vague.
    if (typeof couple === "string" && /^[0-9a-f-]{36}$/.test(couple)) files = await purgePrefix(`c/${couple}/`);
    files += await purgePrefix(`b/${u.user.id}/`);

    // Dans les deux cas, l'espace est fermé : l'autre ne reste jamais seul dans un espace plein de souvenirs.
    if (typeof couple === "string") {
      const { error } = await db.rpc("leave_couple");
      if (error) throw new Error(error.message);
    }
    if (body.action === "delete") {
      const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
        auth: { persistSession: false },
      });
      const { error } = await admin.auth.admin.deleteUser(u.user.id);
      if (error) throw new Error(error.message);
    }
    return json({ ok: true, files });
  } catch (e) {
    console.error("account", body.action, e instanceof Error ? e.message : e);
    return json({ error: "échec, réessaie" }, 502);
  }
});
