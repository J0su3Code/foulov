// Liens temporaires vers le stockage des photos et vidéos chiffrées (docs/SECURITY.md §6).
//
// - Appelée avec la session de l'utilisateur (JWT vérifié par Supabase).
// - Les fichiers sont chiffrés sur le téléphone avant l'envoi : R2 et ce serveur ne voient que des octets illisibles.
// - Un objet porte un nom aléatoire, rangé sous l'identifiant du couple : chacun n'obtient de lien que pour son couple.
// - Lien d'envoi : 5 minutes, un seul nom, et la taille exacte du fichier chiffré est signée.
//
// - Stickers FouLove (pack commun, non chiffré : ce ne sont pas des données personnelles) : liens de lecture vers
//   le seau des stickers, par lots, pour un utilisateur connecté.
//
// Secrets : R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET (et STICKERS_BUCKET, facultatif).

import { createClient } from "npm:@supabase/supabase-js@2.49.4";
import { presign, type R2 } from "./presign.ts";

const r2: R2 = {
  account: Deno.env.get("R2_ACCOUNT_ID")!,
  accessKeyId: Deno.env.get("R2_ACCESS_KEY_ID")!,
  secret: Deno.env.get("R2_SECRET_ACCESS_KEY")!,
  bucket: Deno.env.get("R2_BUCKET")!,
};

/// Plafond d'un fichier chiffré (photo ou vidéo, remplissage compris).
const MAX_BYTES = 220 * 1024 * 1024;
/// Plafond d'une sauvegarde chiffrée (textes, clés, miniatures : les fichiers restent sur R2).
const MAX_BACKUP_BYTES = 500 * 1024 * 1024;
const KEY = /^c\/([0-9a-f-]{36})\/[0-9a-f]{32}$/;

/// Pack de stickers : l'index, puis chaque sticker et sa miniature, nommés par leur empreinte SHA-256.
const stickers: R2 = { ...r2, bucket: Deno.env.get("STICKERS_BUCKET") ?? "foulove-stickers" };
const STICKER_KEY = /^v1\/(index\.json|(t\/)?[0-9a-f]{64}\.webp)$/;
/// Au plus 120 liens par appel (une page de la grille), valables 6 heures.
const MAX_STICKER_KEYS = 120;

const json = (body: unknown, status = 200) => Response.json(body, { status });

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response(null, { status: 405 });
  const auth = req.headers.get("Authorization");
  if (!auth) return json({ error: "non authentifié" }, 401);

  // Client « au nom de l'utilisateur » : les règles d'accès s'appliquent comme dans l'app.
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  let body: { action?: string; size?: number; key?: string; keys?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "requête invalide" }, 400);
  }

  if (body.action === "stickers") {
    const { data: u } = await db.auth.getUser();
    if (!u?.user) return json({ error: "non authentifié" }, 401);
    const keys = body.keys;
    if (!Array.isArray(keys) || keys.length < 1 || keys.length > MAX_STICKER_KEYS) {
      return json({ error: "liste invalide" }, 400);
    }
    if (!keys.every((k) => typeof k === "string" && STICKER_KEY.test(k))) return json({ error: "nom invalide" }, 400);
    const urls: Record<string, string> = {};
    for (const k of keys as string[]) urls[k] = await presign(stickers, "GET", k, { expires: 6 * 3600 });
    return json({ urls });
  }

  // Sauvegarde chiffrée de l'utilisateur (une seule, remplacée à chaque fois) : `b/<son identifiant>/latest`.
  // Elle est chiffrée avec une clé tirée de sa phrase de 24 mots, que le serveur n'a jamais.
  if (body.action?.startsWith("backup_")) {
    const { data: u } = await db.auth.getUser();
    if (!u?.user) return json({ error: "non authentifié" }, 401);
    const key = `b/${u.user.id}/latest`;
    if (body.action === "backup_upload") {
      const size = body.size;
      if (!Number.isInteger(size) || size! < 1 || size! > MAX_BACKUP_BYTES) return json({ error: "taille invalide" }, 400);
      return json({ url: await presign(r2, "PUT", key, { contentLength: size }) });
    }
    if (body.action === "backup_download") return json({ url: await presign(r2, "GET", key) });
    // Bulle fermée par l'autre : la sauvegarde de ce compte ne sert plus, elle est retirée.
    if (body.action === "backup_delete") {
      const r = await fetch(await presign(r2, "DELETE", key), { method: "DELETE" });
      if (!r.ok && r.status !== 404) return json({ error: "stockage indisponible" }, 502);
      return json({ ok: true });
    }
    if (body.action === "backup_status") {
      const r = await fetch(await presign(r2, "HEAD", key), { method: "HEAD" });
      if (r.status === 404) return json({ exists: false });
      if (!r.ok) return json({ error: "stockage indisponible" }, 502);
      return json({
        exists: true,
        size: Number(r.headers.get("content-length") ?? 0),
        at: r.headers.get("last-modified"),
      });
    }
    return json({ error: "action inconnue" }, 400);
  }

  const { data: couple, error } = await db.rpc("my_couple_id");
  if (error || typeof couple !== "string") return json({ error: "aucun couple" }, 403);

  if (body.action === "upload") {
    const size = body.size;
    if (!Number.isInteger(size) || size! < 1 || size! > MAX_BYTES) return json({ error: "taille invalide" }, 400);
    const name = [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join("");
    const key = `c/${couple}/${name}`;
    return json({ key, url: await presign(r2, "PUT", key, { contentLength: size }) });
  }

  if (body.action === "download" || body.action === "delete") {
    const m = typeof body.key === "string" ? KEY.exec(body.key) : null;
    if (!m || m[1] !== couple) return json({ error: "fichier introuvable" }, 404);
    const method = body.action === "download" ? "GET" : "DELETE";
    return json({ url: await presign(r2, method, body.key!) });
  }

  return json({ error: "action inconnue" }, 400);
});
