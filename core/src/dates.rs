//! Dates importantes du couple (anniversaires, dates à vous), partagées entre les deux téléphones.
//!
//! - Chaque date voyage chiffrée par la session Signal (contenu `DateEntry`) : le serveur n'en voit rien.
//! - La modification la plus récente l'emporte, date par date ; une suppression laisse une trace datée pour
//!   qu'une ancienne version arrivée en retard ne la fasse pas réapparaître.
//! - Les rappels sont programmés par l'app sur le téléphone lui-même : le serveur ne sait ni quand ni quoi.

use rusqlite::params;

use crate::chat::{Outgoing, R, Received, db, hex, now_ms, pb, random16};
use crate::device::{Device, DeviceError};

/// Rappel : `None` = aucun, sinon nombre de jours avant (0 = le jour même).
#[derive(Clone, Debug, PartialEq)]
pub struct DateEntry {
    /// 32 caractères hexadécimaux.
    pub id: String,
    pub title: String,
    /// « AAAA-MM-JJ ».
    pub date: String,
    /// Revient chaque année (anniversaire).
    pub yearly: bool,
    pub remind_days: Option<u8>,
    pub updated_at: i64,
}

const MAX_TITLE_CHARS: usize = 80;

fn valid(e: &DateEntry) -> bool {
    let t = e.title.trim();
    !t.is_empty()
        && t.chars().count() <= MAX_TITLE_CHARS
        && crate::chat::valid_date(&e.date)
        && e.remind_days.is_none_or(|d| d <= 60)
        && e.id.len() == 32
        && e.id.chars().all(|c| c.is_ascii_hexdigit())
}

/// Applique une date reçue (dans la transaction de `receive`).
pub(crate) fn apply_date(c: &rusqlite::Connection, d: pb::DateEntry) -> R<Received> {
    let entry = DateEntry {
        id: crate::chat::id_from_wire(&d.id).ok_or(DeviceError::BadMessage)?,
        title: d.title.trim().to_owned(),
        date: d.date,
        yearly: d.yearly,
        // Au-delà de 60 jours : refusé par `valid` (255 n'est jamais accepté).
        remind_days: d.remind_days.map(|x| u8::try_from(x).unwrap_or(u8::MAX)),
        updated_at: i64::try_from(d.updated_at).map_err(|_| DeviceError::BadMessage)?,
    };
    if !d.deleted && !valid(&entry) {
        return Err(DeviceError::BadMessage);
    }
    Ok(if store(c, &entry, d.deleted)? { Received::Dates } else { Received::Nothing })
}

/// Enregistre si plus récent que ce qu'on a déjà. Renvoie vrai si quelque chose a changé.
fn store(c: &rusqlite::Connection, e: &DateEntry, deleted: bool) -> R<bool> {
    let n = c
        .execute(
            "INSERT INTO dates (id, title, date, yearly, remind_days, updated_at, deleted) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
             ON CONFLICT (id) DO UPDATE SET title = excluded.title, date = excluded.date, yearly = excluded.yearly,
               remind_days = excluded.remind_days, updated_at = excluded.updated_at, deleted = excluded.deleted
             WHERE excluded.updated_at > dates.updated_at",
            params![e.id, e.title, e.date, e.yearly, e.remind_days, e.updated_at, deleted],
        )
        .map_err(db)?;
    Ok(n > 0)
}

fn to_wire(e: &DateEntry, deleted: bool) -> pb::DateEntry {
    pb::DateEntry {
        id: crate::chat::unhex(&e.id).unwrap_or_default(),
        title: if deleted { String::new() } else { e.title.clone() },
        date: if deleted { String::new() } else { e.date.clone() },
        yearly: e.yearly,
        remind_days: e.remind_days.map(u32::from),
        updated_at: e.updated_at as u64,
        deleted,
    }
}

impl Device {
    /// Dates du couple (hors supprimées), par date.
    pub fn dates(&self) -> R<Vec<DateEntry>> {
        let c = self.store.conn.lock();
        let mut st = c
            .prepare("SELECT id, title, date, yearly, remind_days, updated_at FROM dates WHERE deleted = 0 ORDER BY date")
            .map_err(db)?;
        let rows = st
            .query_map([], |r| {
                Ok(DateEntry {
                    id: r.get(0)?,
                    title: r.get(1)?,
                    date: r.get(2)?,
                    yearly: r.get(3)?,
                    remind_days: r.get::<_, Option<i64>>(4)?.map(|x| x as u8),
                    updated_at: r.get(5)?,
                })
            })
            .map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    /// Crée (id vide) ou modifie une date, et l'envoie chiffrée au partenaire.
    pub fn save_date(&mut self, partner: &str, mut e: DateEntry) -> R<(DateEntry, Outgoing)> {
        if e.id.is_empty() {
            e.id = hex(&random16());
        }
        e.title = e.title.trim().to_owned();
        e.updated_at = now_ms();
        if !valid(&e) {
            return Err(DeviceError::Protocol("date invalide (titre, jour ou rappel)".into()));
        }
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            store(&self.store.conn.lock(), &e, false)?;
            let out = self.enqueue(partner, pb::Body::Date(to_wire(&e, false)), None)?;
            Ok((e.clone(), out))
        })
    }

    /// Supprime une date chez vous deux.
    pub fn delete_date(&mut self, partner: &str, id: &str) -> R<Outgoing> {
        let tomb = DateEntry {
            id: id.to_owned(),
            title: String::new(),
            date: String::new(),
            yearly: false,
            remind_days: None,
            updated_at: now_ms(),
        };
        if crate::chat::unhex(id).is_none_or(|b| b.len() != 16) {
            return Err(DeviceError::BadMessage);
        }
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            store(&self.store.conn.lock(), &tomb, true)?;
            self.enqueue(partner, pb::Body::Date(to_wire(&tomb, true)), None)
        })
    }
}
