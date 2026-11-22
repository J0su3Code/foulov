//! Bibliothèque de stickers : ceux que tu as enregistrés (reçus de ton amour) ou importés (galerie, fichiers,
//! stickers WhatsApp). Ils vivent dans la base chiffrée de ce téléphone et ne sont jamais envoyés en bloc :
//! un sticker ne part que quand tu l'envoies, comme une photo.

use rusqlite::{OptionalExtension, params};
use sha2::{Digest, Sha256};

use crate::chat::{R, db, hex, now_ms};
use crate::device::{Device, DeviceError};

/// Taille maximale d'un sticker enregistré (un sticker WhatsApp animé pèse au plus 500 Ko).
pub const MAX_STICKER_BYTES: usize = 1024 * 1024;
/// Nombre maximal de stickers enregistrés.
pub const MAX_STICKERS: i64 = 2000;

const MIMES: &[&str] = &["image/webp", "image/png", "image/gif", "image/jpeg"];

/// Un sticker de la bibliothèque (sans son image, lue à part avec [`Device::sticker_data`]).
#[derive(Clone, Debug, PartialEq)]
pub struct Sticker {
    /// SHA-256 de l'image, en hexadécimal : le même sticker n'est jamais enregistré deux fois.
    pub id: String,
    pub mime: String,
    pub width: u32,
    pub height: u32,
    pub favorite: bool,
    pub added_at: i64,
    /// Dernier envoi (0 : jamais envoyé).
    pub used_at: i64,
}

impl Device {
    /// Enregistre un sticker. Renvoie son identifiant et vrai s'il est nouveau (faux : il y était déjà).
    pub fn sticker_add(&self, data: &[u8], mime: &str, width: u32, height: u32) -> R<(String, bool)> {
        if data.is_empty() || data.len() > MAX_STICKER_BYTES || !MIMES.contains(&mime) || width > 4096 || height > 4096 {
            return Err(DeviceError::Protocol("sticker invalide".into()));
        }
        let id = hex(&Sha256::digest(data));
        let c = self.store.conn.lock();
        let exists = c.query_row("SELECT 1 FROM stickers WHERE id = ?1", params![id], |_| Ok(())).optional().map_err(db)?;
        if exists.is_some() {
            return Ok((id, false));
        }
        let count: i64 = c.query_row("SELECT count(*) FROM stickers", [], |r| r.get(0)).map_err(db)?;
        if count >= MAX_STICKERS {
            return Err(DeviceError::Protocol("trop de stickers enregistrés".into()));
        }
        let n = c
            .execute(
                "INSERT OR IGNORE INTO stickers (id, data, mime, width, height, added_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![id, data, mime, width, height, now_ms()],
            )
            .map_err(db)?;
        Ok((id, n > 0))
    }

    /// Tous les stickers, du plus récemment ajouté au plus ancien.
    pub fn stickers(&self) -> R<Vec<Sticker>> {
        let c = self.store.conn.lock();
        let mut st = c
            .prepare("SELECT id, mime, width, height, favorite, added_at, used_at FROM stickers ORDER BY added_at DESC, id")
            .map_err(db)?;
        let rows = st
            .query_map([], |r| {
                Ok(Sticker {
                    id: r.get(0)?,
                    mime: r.get(1)?,
                    width: r.get::<_, i64>(2)? as u32,
                    height: r.get::<_, i64>(3)? as u32,
                    favorite: r.get::<_, i64>(4)? == 1,
                    added_at: r.get(5)?,
                    used_at: r.get(6)?,
                })
            })
            .map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    pub fn sticker_data(&self, id: &str) -> R<Option<Vec<u8>>> {
        self.store
            .conn
            .lock()
            .query_row("SELECT data FROM stickers WHERE id = ?1", params![id], |r| r.get(0))
            .optional()
            .map_err(db)
    }

    /// Le sticker est-il déjà dans la bibliothèque ? Renvoie son identifiant et s'il est en favori.
    pub fn sticker_find(&self, data: &[u8]) -> R<Option<(String, bool)>> {
        let id = hex(&Sha256::digest(data));
        self.store
            .conn
            .lock()
            .query_row("SELECT favorite FROM stickers WHERE id = ?1", params![id], |r| r.get::<_, i64>(0))
            .optional()
            .map(|f| f.map(|f| (id, f == 1)))
            .map_err(db)
    }

    pub fn sticker_set_favorite(&self, id: &str, favorite: bool) -> R<()> {
        self.store
            .conn
            .lock()
            .execute("UPDATE stickers SET favorite = ?2 WHERE id = ?1", params![id, favorite as i64])
            .map_err(db)?;
        Ok(())
    }

    /// Envoyé à l'instant : remonte dans « Récents ».
    pub fn sticker_used(&self, id: &str) -> R<()> {
        self.store.conn.lock().execute("UPDATE stickers SET used_at = ?2 WHERE id = ?1", params![id, now_ms()]).map_err(db)?;
        Ok(())
    }

    pub fn sticker_delete(&self, id: &str) -> R<()> {
        self.store.conn.lock().execute("DELETE FROM stickers WHERE id = ?1", params![id]).map_err(db)?;
        Ok(())
    }
}
