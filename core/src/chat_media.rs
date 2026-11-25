//! Photos et vidéos dans la conversation (`docs/SECURITY.md` §6).
//!
//! Envoi :
//! 1. `create_media` chiffre le fichier (clé aléatoire, STREAM AES-256-GCM, Padmé), garde le chiffré sur ce
//!    téléphone et ajoute le message à l'historique, « en attente ».
//! 2. L'app dépose le chiffré sur R2 avec un lien temporaire (taille signée), puis appelle `media_uploaded` :
//!    le message chiffré (clé du fichier, empreinte, miniature, dimensions) part alors vers le partenaire.
//!    Si l'app s'arrête entre les deux, `pending_uploads` permet de reprendre.
//!
//! Réception : la miniature s'affiche aussitôt ; l'app télécharge le chiffré, `media_downloaded` vérifie son
//! empreinte SHA-256, et `open_media` le déchiffre **en mémoire** pour l'affichage. Sur le téléphone, le fichier
//! reste chiffré ; sa clé ne quitte jamais la base SQLCipher.

use std::fs;
use std::path::{Path, PathBuf};

use rusqlite::{OptionalExtension, params};

use crate::chat::{ChatMessage, Outgoing, R, Received, SELECT, db, hex, id_from_wire, now_ms, pb, random16, row_to_message, unhex};
use crate::device::{Device, DeviceError};
use crate::media;

pub const KIND_PHOTO: u8 = 1;
pub const KIND_VIDEO: u8 = 2;
/// Message vocal (la « miniature » transporte alors la forme d'onde : jusqu'à 64 amplitudes de 0 à 255).
pub const KIND_VOICE: u8 = 3;
/// Sticker : image (WebP, PNG ou GIF, animée ou non) affichée sans bulle. La miniature voyage dans le message.
pub const KIND_STICKER: u8 = 4;
/// Archive chiffrée (transfert d'historique entre vos téléphones). Pas de miniature.
pub const KIND_ARCHIVE: u8 = 5;
/// Plafond du fichier chiffré (le serveur applique le même).
pub const MAX_MEDIA_BYTES: u64 = 220 * 1024 * 1024;
/// Plafond de la miniature, qui voyage dans le message chiffré.
pub const MAX_THUMB_BYTES: usize = 64 * 1024;

/// À quoi sert un fichier chiffré (colonne `media.purpose`).
pub(crate) const FOR_MESSAGE: i64 = 0;
pub(crate) const FOR_PICTURE: i64 = 1;
pub(crate) const FOR_MOMENT: i64 = 2;
pub(crate) const FOR_TRANSFER: i64 = 3;

/// Vérifie la description d'un fichier reçu (nom d'objet, clé, empreinte, taille, type, miniature).
pub(crate) fn valid_file(f: &pb::FileRef, kinds: &[u8]) -> bool {
    u8::try_from(f.kind).is_ok_and(|k| kinds.contains(&k) && check_meta(k, &f.mime, &f.thumb, "", f.width, f.height))
        && valid_object_key(&f.object_key)
        && f.file_key.len() == 32
        && f.sha256.len() == 32
        && f.size > 0
        && f.size <= MAX_MEDIA_BYTES
}

/// Enregistre un fichier reçu, à télécharger (état 2).
///
/// Enregistre un fichier annoncé par le partenaire. Ne remplace **jamais** une ligne existante : sinon le partenaire
/// pourrait réutiliser l'identifiant d'un de mes messages (un instant, par exemple) et changer la photo affichée
/// dans mon propre historique. Un identifiant déjà pris rejette le contenu reçu.
pub(crate) fn insert_remote(c: &rusqlite::Connection, id: &str, f: &pb::FileRef, purpose: i64) -> R<()> {
    let taken: bool =
        c.query_row("SELECT EXISTS (SELECT 1 FROM media WHERE message_id = ?1)", params![id], |r| r.get(0)).map_err(db)?;
    if taken {
        return Err(DeviceError::BadMessage);
    }
    c.execute(
        "INSERT INTO media (message_id, kind, object_key, file_key, sha256, size, mime, width, height, duration_ms,
           thumb, path, state, purpose) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, NULL, 2, ?12)",
        params![id, f.kind, f.object_key, f.file_key, f.sha256, f.size as i64, f.mime, f.width, f.height, f.duration_ms, f.thumb, purpose],
    )
    .map_err(db)?;
    Ok(())
}

/// Description d'un fichier déjà déposé sur R2, pour l'envoyer au partenaire.
pub(crate) fn file_ref(c: &rusqlite::Connection, id: &str) -> R<Option<pb::FileRef>> {
    c.query_row(
        "SELECT kind, object_key, file_key, sha256, size, mime, width, height, duration_ms, thumb FROM media
         WHERE message_id = ?1 AND object_key IS NOT NULL",
        params![id],
        |r| {
            Ok(pb::FileRef {
                kind: r.get::<_, i64>(0)? as u32,
                object_key: r.get(1)?,
                file_key: r.get(2)?,
                sha256: r.get(3)?,
                size: r.get::<_, i64>(4)? as u64,
                mime: r.get(5)?,
                width: r.get::<_, i64>(6)? as u32,
                height: r.get::<_, i64>(7)? as u32,
                duration_ms: r.get::<_, i64>(8)? as u32,
                thumb: r.get(9)?,
            })
        },
    )
    .optional()
    .map_err(db)
}

/// Retire un fichier : le chiffré local est effacé ; si `trash`, son objet R2 est mis à la corbeille.
pub(crate) fn drop_file(c: &rusqlite::Connection, id: &str, trash: bool) -> R<()> {
    let row: Option<(Option<String>, Option<String>)> = c
        .query_row("SELECT path, object_key FROM media WHERE message_id = ?1", params![id], |r| Ok((r.get(0)?, r.get(1)?)))
        .optional()
        .map_err(db)?;
    let Some((path, key)) = row else { return Ok(()) };
    if let Some(p) = path {
        let _ = fs::remove_file(p);
    }
    if let (true, Some(k)) = (trash, key) {
        c.execute("INSERT OR IGNORE INTO r2_trash (object_key) VALUES (?1)", params![k]).map_err(db)?;
    }
    c.execute("DELETE FROM media WHERE message_id = ?1", params![id]).map_err(db)?;
    Ok(())
}
const MIMES: &[&str] =
    &["image/jpeg", "image/png", "image/webp", "image/gif", "image/heic", "video/mp4", "video/quicktime", "audio/mp4", "audio/aac", "application/octet-stream"];

/// Fichier à déposer sur R2.
#[derive(Clone, Debug, PartialEq)]
pub struct PendingUpload {
    pub message_id: String,
    pub path: String,
    pub size: u64,
}

/// Fichier à télécharger depuis R2.
#[derive(Clone, Debug, PartialEq)]
pub struct PendingDownload {
    pub message_id: String,
    pub object_key: String,
    pub size: u64,
}

/// Description d'une photo ou vidéo à envoyer.
pub struct NewMedia<'a> {
    pub kind: u8,
    pub mime: &'a str,
    pub width: u32,
    pub height: u32,
    pub duration_ms: u32,
    pub thumb: &'a [u8],
    pub caption: &'a str,
    pub reply_to: Option<&'a str>,
}

fn invalid(what: &str) -> DeviceError {
    DeviceError::Protocol(format!("média invalide : {what}"))
}

/// Nom d'objet attribué par le serveur : « c/<couple>/<32 hex> ».
pub(crate) fn valid_object_key(k: &str) -> bool {
    let parts: Vec<&str> = k.split('/').collect();
    parts.len() == 3
        && parts[0] == "c"
        && parts[1].len() == 36
        && parts[1].chars().all(|c| c.is_ascii_hexdigit() || c == '-')
        && parts[2].len() == 32
        && parts[2].chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase())
}

pub(crate) fn check_meta(kind: u8, mime: &str, thumb: &[u8], caption: &str, w: u32, h: u32) -> bool {
    let family = match kind {
        KIND_PHOTO | KIND_STICKER => "image/",
        KIND_VIDEO => "video/",
        KIND_VOICE => "audio/",
        KIND_ARCHIVE => "application/",
        _ => return false,
    };
    if kind == KIND_ARCHIVE && !thumb.is_empty() {
        return false;
    }
    MIMES.contains(&mime)
        && mime.starts_with(family)
        && thumb.len() <= if kind == KIND_VOICE { 64 } else { MAX_THUMB_BYTES }
        && caption.len() <= crate::chat::MAX_TEXT_BYTES
        && w <= 20_000
        && h <= 20_000
}

/// Écriture sûre : fichier temporaire puis renommage (jamais de fichier à moitié écrit sous le nom final).
pub(crate) fn write_atomic(path: &Path, data: &[u8]) -> std::io::Result<()> {
    let tmp = path.with_extension("tmp");
    fs::write(&tmp, data)?;
    fs::rename(&tmp, path)
}

pub(crate) fn io(e: std::io::Error) -> DeviceError {
    DeviceError::Protocol(format!("fichier : {e}"))
}

/// Applique un message « photo ou vidéo » reçu (appelé dans la transaction de `receive`).
pub(crate) fn apply_media(c: &rusqlite::Connection, m: pb::Media) -> R<Received> {
    let id = id_from_wire(&m.id).ok_or(DeviceError::BadMessage)?;
    let kind = u8::try_from(m.kind).map_err(|_| DeviceError::BadMessage)?;
    let caption = m.caption.trim().to_owned();
    if !check_meta(kind, &m.mime, &m.thumb, &caption, m.width, m.height)
        || !valid_object_key(&m.object_key)
        || m.file_key.len() != 32
        || m.sha256.len() != 32
        || m.size == 0
        || m.size > MAX_MEDIA_BYTES
    {
        return Err(DeviceError::BadMessage);
    }
    let now = now_ms();
    let sent_at = i64::try_from(m.sent_at).ok().filter(|s| (now - 30 * 86_400_000..now + 600_000).contains(s)).unwrap_or(now);
    let reply_to = m.reply_to.as_deref().and_then(id_from_wire);
    let n = c
        .execute(
            "INSERT OR IGNORE INTO messages (id, from_me, body, reply_to, sent_at, received_at, status) VALUES (?1, 0, ?2, ?3, ?4, ?5, 0)",
            params![id, caption, reply_to, sent_at, now],
        )
        .map_err(db)?;
    if n == 0 {
        return Ok(Received::Nothing);
    }
    c.execute(
        "INSERT INTO media (message_id, kind, object_key, file_key, sha256, size, mime, width, height, duration_ms, thumb, path, state)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, NULL, 2)",
        params![id, kind, m.object_key, m.file_key, m.sha256, m.size as i64, m.mime, m.width, m.height, m.duration_ms, m.thumb],
    )
    .map_err(db)?;
    let msg = c.query_row(&format!("{SELECT} WHERE m.id = ?1"), params![id], row_to_message).map_err(db)?;
    Ok(Received::Message(msg))
}

impl Device {
    /// Chiffre la photo ou vidéo, garde le chiffré dans `dir` et ajoute le message (« en attente »).
    /// Renvoie le message et le fichier à déposer.
    pub fn create_media(&mut self, dir: &Path, plain: &[u8], m: NewMedia<'_>) -> R<(ChatMessage, PendingUpload)> {
        let caption = m.caption.trim();
        if plain.is_empty() || !check_meta(m.kind, m.mime, m.thumb, caption, m.width, m.height) {
            return Err(invalid("type, taille ou légende"));
        }
        if media::ciphertext_len(plain.len() as u64) > MAX_MEDIA_BYTES {
            return Err(invalid("fichier trop volumineux"));
        }
        let reply = match m.reply_to {
            Some(r) => Some(unhex(r).filter(|b| b.len() == 16).map(|_| r.to_owned()).ok_or(DeviceError::BadMessage)?),
            None => None,
        };
        let enc = media::encrypt(plain).map_err(|e| invalid(&e.to_string()))?;
        let id = hex(&random16());
        fs::create_dir_all(dir).map_err(io)?;
        let path: PathBuf = dir.join(format!("{id}.flm"));
        write_atomic(&path, &enc.ciphertext).map_err(io)?;
        self.record_created(&id, &path, &enc.key, &enc.sha256, enc.ciphertext.len() as u64, &m, caption, reply)
    }

    /// Comme [`create_media`], mais chiffre directement depuis un fichier (vidéos) : jamais tout en mémoire.
    pub fn create_media_file(&mut self, dir: &Path, src: &Path, m: NewMedia<'_>) -> R<(ChatMessage, PendingUpload)> {
        let caption = m.caption.trim();
        let len = fs::metadata(src).map_err(io)?.len();
        if len == 0 || !check_meta(m.kind, m.mime, m.thumb, caption, m.width, m.height) {
            return Err(invalid("type, taille ou légende"));
        }
        if media::ciphertext_len(len) > MAX_MEDIA_BYTES {
            return Err(invalid("fichier trop volumineux"));
        }
        let reply = match m.reply_to {
            Some(r) => Some(unhex(r).filter(|b| b.len() == 16).map(|_| r.to_owned()).ok_or(DeviceError::BadMessage)?),
            None => None,
        };
        let id = hex(&random16());
        fs::create_dir_all(dir).map_err(io)?;
        let path: PathBuf = dir.join(format!("{id}.flm"));
        let enc = media::encrypt_file(src, &path).map_err(|e| invalid(&e.to_string()))?;
        self.record_created(&id, &path, &enc.key, &enc.sha256, enc.size, &m, caption, reply)
    }

    #[allow(clippy::too_many_arguments)]
    fn record_created(
        &mut self,
        id: &str,
        path: &Path,
        key: &[u8; 32],
        sha256: &[u8; 32],
        size: u64,
        m: &NewMedia<'_>,
        caption: &str,
        reply: Option<String>,
    ) -> R<(ChatMessage, PendingUpload)> {
        let path_s = path.to_string_lossy().into_owned();

        let last: Option<i64> = self
            .store
            .conn
            .lock()
            .query_row("SELECT max(sent_at) FROM messages WHERE from_me = 1", [], |r| r.get(0))
            .map_err(db)?;
        let sent_at = now_ms().max(last.map_or(0, |l| l + 1));
        let tx = self.store.conn.clone();
        let res = tx.atomically(|| {
            let c = self.store.conn.lock();
            c.execute(
                "INSERT INTO messages (id, from_me, body, reply_to, sent_at, received_at, status) VALUES (?1, 1, ?2, ?3, ?4, ?4, 0)",
                params![id, caption, reply, sent_at],
            )
            .map_err(db)?;
            c.execute(
                "INSERT INTO media (message_id, kind, object_key, file_key, sha256, size, mime, width, height, duration_ms, thumb, path, state)
                 VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 0)",
                params![id, m.kind, key.to_vec(), sha256.to_vec(), size as i64, m.mime, m.width, m.height, m.duration_ms, m.thumb, path_s],
            )
            .map_err(db)?;
            c.query_row(&format!("{SELECT} WHERE m.id = ?1"), params![id], row_to_message).map_err(db)
        });
        match res {
            Ok(msg) => Ok((msg, PendingUpload { message_id: id.to_owned(), path: path_s, size })),
            Err(e) => {
                let _ = fs::remove_file(path);
                Err(e)
            }
        }
    }

    /// Chiffre un fichier qui n'est pas un message (photo du couple, instant) et le garde dans `dir`, « à envoyer ».
    /// `src` : chemin d'un fichier en clair (vidéo), sinon `plain`.
    pub(crate) fn create_file(
        &mut self,
        dir: &Path,
        id: &str,
        plain: Option<&[u8]>,
        src: Option<&Path>,
        m: &NewMedia<'_>,
        purpose: i64,
    ) -> R<PendingUpload> {
        if !check_meta(m.kind, m.mime, m.thumb, "", m.width, m.height) {
            return Err(invalid("type ou miniature"));
        }
        fs::create_dir_all(dir).map_err(io)?;
        let path: PathBuf = dir.join(format!("{id}.flm"));
        let (key, sha, size) = match (plain, src) {
            (Some(p), _) if !p.is_empty() && media::ciphertext_len(p.len() as u64) <= MAX_MEDIA_BYTES => {
                let enc = media::encrypt(p).map_err(|e| invalid(&e.to_string()))?;
                write_atomic(&path, &enc.ciphertext).map_err(io)?;
                (enc.key, enc.sha256, enc.ciphertext.len() as u64)
            }
            (None, Some(s)) => {
                let len = fs::metadata(s).map_err(io)?.len();
                if len == 0 || media::ciphertext_len(len) > MAX_MEDIA_BYTES {
                    return Err(invalid("fichier vide ou trop volumineux"));
                }
                let enc = media::encrypt_file(s, &path).map_err(|e| invalid(&e.to_string()))?;
                (enc.key, enc.sha256, enc.size)
            }
            _ => return Err(invalid("fichier vide ou trop volumineux")),
        };
        let path_s = path.to_string_lossy().into_owned();
        let r = self.store.conn.lock().execute(
            "INSERT INTO media (message_id, kind, object_key, file_key, sha256, size, mime, width, height, duration_ms, thumb, path, state, purpose)
             VALUES (?1, ?2, NULL, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, 0, ?12)",
            params![id, m.kind, key.to_vec(), sha.to_vec(), size as i64, m.mime, m.width, m.height, m.duration_ms, m.thumb, path_s, purpose],
        );
        if let Err(e) = r {
            let _ = fs::remove_file(&path);
            return Err(db(e));
        }
        Ok(PendingUpload { message_id: id.to_owned(), path: path_s, size })
    }

    /// Le chiffré est sur R2 sous `object_key` : envoie au partenaire ce qu'il décrit (message, photo du couple,
    /// instant). `None` : plus rien à envoyer (photo remplacée entre-temps, instant retiré ou expiré).
    pub fn media_uploaded(&mut self, partner: &str, message_id: &str, object_key: &str) -> R<Option<Outgoing>> {
        if !valid_object_key(object_key) {
            return Err(invalid("nom d'objet"));
        }
        let row: Option<(i64, i64)> = self
            .store
            .conn
            .lock()
            .query_row("SELECT purpose, state FROM media WHERE message_id = ?1", params![message_id], |r| Ok((r.get(0)?, r.get(1)?)))
            .optional()
            .map_err(db)?;
        let purpose = match row {
            // Retiré pendant le dépôt (photo remplacée, instant supprimé) : l'objet déposé ne sert plus.
            None => {
                self.store
                    .conn
                    .lock()
                    .execute("INSERT OR IGNORE INTO r2_trash (object_key) VALUES (?1)", params![object_key])
                    .map_err(db)?;
                return Ok(None);
            }
            Some((p, 0)) => Some(p),
            Some(_) => None,
        };
        match purpose {
            None => return Err(invalid("rien à envoyer pour ce fichier")),
            Some(FOR_PICTURE) => return self.picture_uploaded(partner, message_id, object_key),
            Some(FOR_MOMENT) => return self.moment_uploaded(partner, message_id, object_key),
            Some(FOR_TRANSFER) => return self.history_uploaded(partner, message_id, object_key),
            Some(FOR_MESSAGE) => {}
            Some(_) => return Err(invalid("usage inconnu")),
        }
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let row = {
                let c = self.store.conn.lock();
                let n = c
                    .execute(
                        "UPDATE media SET object_key = ?2, state = 1 WHERE message_id = ?1 AND state = 0",
                        params![message_id, object_key],
                    )
                    .map_err(db)?;
                if n == 0 {
                    return Err(invalid("rien à envoyer pour ce message"));
                }
                c.query_row(
                    "SELECT m.sent_at, m.body, m.reply_to, md.kind, md.file_key, md.sha256, md.size, md.mime, md.width,
                            md.height, md.duration_ms, md.thumb
                     FROM messages m JOIN media md ON md.message_id = m.id WHERE m.id = ?1",
                    params![message_id],
                    |r| {
                        Ok(pb::Media {
                            id: unhex(message_id).unwrap_or_default(),
                            sent_at: r.get::<_, i64>(0)? as u64,
                            caption: r.get(1)?,
                            reply_to: r.get::<_, Option<String>>(2)?.and_then(|s| unhex(&s)),
                            kind: r.get::<_, i64>(3)? as u32,
                            object_key: object_key.to_owned(),
                            file_key: r.get(4)?,
                            sha256: r.get(5)?,
                            size: r.get::<_, i64>(6)? as u64,
                            mime: r.get(7)?,
                            width: r.get::<_, i64>(8)? as u32,
                            height: r.get::<_, i64>(9)? as u32,
                            duration_ms: r.get::<_, i64>(10)? as u32,
                            thumb: r.get(11)?,
                        })
                    },
                )
                .map_err(db)?
            };
            let body = if row.kind == KIND_STICKER as u32 { pb::Body::Sticker(row) } else { pb::Body::Media(row) };
            self.enqueue(partner, body, Some(message_id)).map(Some)
        })
    }

    /// Photos et vidéos créées mais pas encore déposées (l'app s'est arrêtée, coupure réseau).
    pub fn pending_uploads(&self) -> R<Vec<PendingUpload>> {
        let c = self.store.conn.lock();
        let mut st = c.prepare("SELECT message_id, path, size FROM media WHERE state = 0 AND path IS NOT NULL ORDER BY rowid").map_err(db)?;
        let rows = st
            .query_map([], |r| Ok(PendingUpload { message_id: r.get(0)?, path: r.get(1)?, size: r.get::<_, i64>(2)? as u64 }))
            .map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    /// Photos et vidéos reçues à télécharger.
    pub fn pending_downloads(&self) -> R<Vec<PendingDownload>> {
        let c = self.store.conn.lock();
        let mut st = c.prepare("SELECT message_id, object_key, size FROM media WHERE state = 2 ORDER BY rowid DESC").map_err(db)?;
        let rows = st
            .query_map([], |r| {
                Ok(PendingDownload { message_id: r.get(0)?, object_key: r.get(1)?, size: r.get::<_, i64>(2)? as u64 })
            })
            .map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    /// Le chiffré a été téléchargé dans `downloaded` : vérifie sa taille et son empreinte, puis le range dans `dir`.
    /// Renvoie faux (et efface le fichier) si le contenu n'est pas exactement celui annoncé par le partenaire.
    pub fn media_downloaded(&mut self, message_id: &str, downloaded: &Path, dir: &Path) -> R<bool> {
        let row: Option<(i64, Vec<u8>)> = self
            .store
            .conn
            .lock()
            .query_row("SELECT size, sha256 FROM media WHERE message_id = ?1 AND state = 2", params![message_id], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })
            .optional()
            .map_err(db)?;
        let Some((size, sha)) = row else { return Ok(false) };
        let expected: [u8; 32] = sha.try_into().map_err(|_| DeviceError::BadMessage)?;
        // Empreinte calculée par blocs : une vidéo n'est jamais chargée entière en mémoire.
        let len = fs::metadata(downloaded).map_err(io)?.len();
        let ok = len as i64 == size
            && media::sha256_file(downloaded).map(|h| h.iter().zip(&expected).fold(0u8, |a, (x, y)| a | (x ^ y)) == 0).unwrap_or(false);
        if !ok {
            let _ = fs::remove_file(downloaded);
            // Altéré ou substitué : on ne réessaie pas indéfiniment, la photo est marquée illisible.
            self.store
                .conn
                .lock()
                .execute("UPDATE media SET state = 3 WHERE message_id = ?1", params![message_id])
                .map_err(db)?;
            return Ok(false);
        }
        fs::create_dir_all(dir).map_err(io)?;
        let path = dir.join(format!("{message_id}.flm"));
        fs::rename(downloaded, &path).or_else(|_| fs::copy(downloaded, &path).map(|_| ())).map_err(io)?;
        let _ = fs::remove_file(downloaded);
        self.store
            .conn
            .lock()
            .execute(
                "UPDATE media SET path = ?2, state = 1 WHERE message_id = ?1",
                params![message_id, path.to_string_lossy().into_owned()],
            )
            .map_err(db)?;
        Ok(true)
    }

    /// Toutes les photos et vidéos (onglet Souvenirs ; les vocaux seulement avec `kind` = 3), de la plus récente à la plus ancienne, par pages.
    /// `kind` : 1 photos, 2 vidéos, 3 vocaux, `None` photos et vidéos. Les médias illisibles (altérés) sont exclus.
    pub fn media_gallery(&self, before: Option<(i64, String)>, limit: u32, kind: Option<u8>) -> R<Vec<ChatMessage>> {
        let c = self.store.conn.lock();
        let (sa, id) = before.unwrap_or((i64::MAX, String::new()));
        let mut st = c
            .prepare(&format!(
                "{SELECT} WHERE md.state != 3 AND m.deleted = 0 AND ((?4 IS NULL AND md.kind IN (1, 2)) OR md.kind = ?4)
                 AND (m.sent_at, m.id) < (?1, ?2) ORDER BY m.sent_at DESC, m.id DESC LIMIT ?3"
            ))
            .map_err(db)?;
        let rows = st.query_map(params![sa, id, limit.min(500), kind], row_to_message).map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    fn reader(&self, message_id: &str) -> R<media::MediaReader> {
        let row: Option<(Option<String>, Vec<u8>)> = self
            .store
            .conn
            .lock()
            .query_row("SELECT path, file_key FROM media WHERE message_id = ?1 AND state IN (0, 1)", params![message_id], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })
            .optional()
            .map_err(db)?;
        let Some((Some(path), key)) = row else { return Err(invalid("pas encore disponible")) };
        let key: [u8; 32] = key.try_into().map_err(|_| DeviceError::BadMessage)?;
        media::MediaReader::open(&key, Path::new(&path)).map_err(|_| DeviceError::BadMessage)
    }

    /// Taille réelle (déchiffrée) d'une photo ou vidéo.
    pub fn media_len(&self, message_id: &str) -> R<u64> {
        Ok(self.reader(message_id)?.len)
    }

    /// Lit `len` octets déchiffrés à partir de `offset` : la lecture vidéo se fait ainsi, morceau par morceau,
    /// sans jamais écrire la vidéo en clair. Chaque bloc lu est authentifié.
    pub fn media_read(&self, message_id: &str, offset: u64, len: u32) -> R<Vec<u8>> {
        self.reader(message_id)?.read_at(offset, len.min(4 * 1024 * 1024) as usize).map_err(|_| DeviceError::BadMessage)
    }

    /// Déchiffre la photo ou vidéo en mémoire, pour l'affichage. Rien n'est écrit en clair.
    pub fn open_media(&self, message_id: &str) -> R<Vec<u8>> {
        let row: Option<(Option<String>, Vec<u8>)> = self
            .store
            .conn
            .lock()
            .query_row("SELECT path, file_key FROM media WHERE message_id = ?1 AND state IN (0, 1)", params![message_id], |r| {
                Ok((r.get(0)?, r.get(1)?))
            })
            .optional()
            .map_err(db)?;
        let (Some(path), key) = row.ok_or_else(|| invalid("pas encore disponible"))? else {
            return Err(invalid("pas encore disponible"));
        };
        let key: [u8; 32] = key.try_into().map_err(|_| DeviceError::BadMessage)?;
        let data = fs::read(&path).map_err(io)?;
        media::decrypt(&key, &data).map_err(|_| DeviceError::BadMessage)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn noms_d_objets() {
        assert!(valid_object_key("c/0f2c1a6e-1111-4222-8333-444455556666/0123456789abcdef0123456789abcdef"));
        assert!(!valid_object_key("c/0f2c1a6e-1111-4222-8333-444455556666/../../etc"));
        assert!(!valid_object_key("c/x/0123456789abcdef0123456789abcdef"));
        assert!(!valid_object_key("d/0f2c1a6e-1111-4222-8333-444455556666/0123456789abcdef0123456789abcdef"));
    }
}
