// URL pré-signées Cloudflare R2 (API S3), signature AWS SigV4 « en requête » écrite avec WebCrypto.
//
// Pourquoi pas une bibliothèque : les bibliothèques courantes refusent de signer `content-length`. Ici, la taille
// exacte du fichier chiffré fait partie de la signature : une URL d'envoi ne permet de déposer qu'un objet de
// cette taille-là, sous ce nom-là, pendant 5 minutes.
// Référence : https://docs.aws.amazon.com/AmazonS3/latest/API/sigv4-query-string-auth.html

export type R2 = { account: string; accessKeyId: string; secret: string; bucket: string };

const enc = new TextEncoder();

const hex = (b: ArrayBuffer) => [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");

async function hmac(key: ArrayBuffer | Uint8Array<ArrayBuffer>, data: string): Promise<ArrayBuffer> {
  const k = await crypto.subtle.importKey("raw", key, { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return crypto.subtle.sign("HMAC", k, enc.encode(data));
}

// Encodage URI de SigV4 : tout sauf A-Z a-z 0-9 - _ . ~ (et « / » conservé dans le chemin).
const uri = (s: string, keepSlash = false) =>
  [...enc.encode(s)]
    .map((b) => {
      const c = String.fromCharCode(b);
      if (/[A-Za-z0-9\-_.~]/.test(c) || (keepSlash && c === "/")) return c;
      return "%" + b.toString(16).toUpperCase().padStart(2, "0");
    })
    .join("");

export async function presign(
  r2: R2,
  method: "PUT" | "GET" | "DELETE",
  key: string,
  opts: { contentLength?: number; expires?: number; now?: Date } = {},
): Promise<string> {
  const host = `${r2.account}.r2.cloudflarestorage.com`;
  const now = opts.now ?? new Date();
  const amzDate = now.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, ""); // AAAAMMJJTHHMMSSZ
  const day = amzDate.slice(0, 8);
  const scope = `${day}/auto/s3/aws4_request`;
  const path = `/${r2.bucket}/${key}`;

  const headers: [string, string][] = [["host", host]];
  if (opts.contentLength !== undefined) headers.unshift(["content-length", String(opts.contentLength)]);
  const signedHeaders = headers.map(([k]) => k).join(";");

  const query: [string, string][] = [
    ["X-Amz-Algorithm", "AWS4-HMAC-SHA256"],
    ["X-Amz-Credential", `${r2.accessKeyId}/${scope}`],
    ["X-Amz-Date", amzDate],
    ["X-Amz-Expires", String(opts.expires ?? 300)],
    ["X-Amz-SignedHeaders", signedHeaders],
  ];
  const canonicalQuery = query
    .map(([k, v]) => [uri(k), uri(v)])
    .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0))
    .map(([k, v]) => `${k}=${v}`)
    .join("&");

  const canonicalRequest = [
    method,
    uri(path, true),
    canonicalQuery,
    headers.map(([k, v]) => `${k}:${v}\n`).join(""),
    signedHeaders,
    "UNSIGNED-PAYLOAD",
  ].join("\n");
  const stringToSign = [
    "AWS4-HMAC-SHA256",
    amzDate,
    scope,
    hex(await crypto.subtle.digest("SHA-256", enc.encode(canonicalRequest))),
  ].join("\n");

  let k = await hmac(enc.encode("AWS4" + r2.secret), day);
  for (const part of ["auto", "s3", "aws4_request"]) k = await hmac(k, part);
  const signature = hex(await hmac(k, stringToSign));
  return `https://${host}${uri(path, true)}?${canonicalQuery}&X-Amz-Signature=${signature}`;
}
