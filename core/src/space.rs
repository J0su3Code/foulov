//! Notre espace : profil du couple, photos, instants (24 h), albums, lettres et capsules, chiffres.
//!
//! Tout voyage chiffré par la session Signal, comme les messages : le serveur ne voit ni la bio, ni les photos,
//! ni les lettres, ni même qu'il s'agit d'un instant plutôt que d'un message (même remplissage, même taille arrondie).
//!
//! - **Réglages** (bio, histoire, style des bulles, anniversaire…) : petites valeurs horodatées, la plus récente
//!   l'emporte. Une valeur « personnelle » décrit son auteur (son anniversaire, la couleur de ses bulles).
//! - **Photos du couple** (photo à deux, couverture, fond de conversation) : fichier chiffré sur R2 comme une photo
//!   de la conversation ; la plus récente l'emporte, l'ancienne est effacée (et retirée de R2 par son auteur).
//! - **Instants** : visibles 24 h, puis effacés des deux téléphones et de R2.
//! - **Capsules** : une lettre dont l'ouverture est datée. Elle arrive tout de suite, chiffrée, et l'app ne
//!   l'affiche pas avant la date choisie (chez l'un comme chez l'autre). Ce n'est pas un verrou cryptographique
//!   dans le temps : c'est une promesse de l'app, dite telle quelle dans `docs/SECURITY.md`.

use std::collections::{BTreeSet, HashMap};
use std::path::Path;

use rusqlite::{OptionalExtension, params};

use crate::chat::{
    MediaInfo, Outgoing, R, Received, db, hex, id_from_wire, kv_newer, kv_set, now_ms, pb, random16, unhex,
    valid_date,
};
use crate::chat_media::{
    FOR_MOMENT, FOR_PICTURE, KIND_PHOTO, KIND_VIDEO, NewMedia, PendingUpload, drop_file, file_ref, insert_remote,
    valid_file,
};
use crate::device::{Device, DeviceError};

/// Durée de vie d'un instant.
pub const MOMENT_TTL_MS: i64 = 24 * 3_600_000;
pub const KIND_TEXT: u8 = 4;
const MAX_MOMENT_TEXT: usize = 500;
/// Nombre de styles (dégradés, couleurs de bulles, fonds) que l'app sait dessiner.
const STYLES: u32 = 32;
const MAX_ALBUM_ITEMS: usize = 5000;
const MAX_ALBUM_TITLE: usize = 60;
const MAX_LETTER_TITLE: usize = 80;
pub const MAX_LETTER_BYTES: usize = 32 * 1024;
const DAY_MS: i64 = 86_400_000;

/// Emplacements de photos du couple.
pub const SLOTS: &[&str] = &["avatar", "cover", "wallpaper"];

fn bad(what: &str) -> DeviceError {
    DeviceError::Protocol(what.to_owned())
}

fn wire_id(id: &str) -> R<Vec<u8>> {
    unhex(id).filter(|b| b.len() == 16).ok_or(DeviceError::BadMessage)
}

/// Heure annoncée par l'expéditeur, ramenée à l'heure de réception si elle est absurde (horloge déréglée).
fn sane_time(t: u64, now: i64) -> i64 {
    i64::try_from(t).ok().filter(|s| (now - 30 * DAY_MS..now + 600_000).contains(s)).unwrap_or(now)
}

fn no_controls(s: &str) -> bool {
    !s.chars().any(|c| c.is_control() && c != '\n')
}

// ------------------------------------------------------------------ réglages

const SHARED_KEYS: &[&str] = &[
    "bio", "story_title", "story", "bubble_shape", "wallpaper", "pattern", "pattern_opacity", "photo_blur", "photo_dim",
    "bubble_style", "theme",
];
const PERSONAL_KEYS: &[&str] = &["birthday", "bubble_color", "text_size"];

/// Anniversaire : « MM-JJ » (année gardée pour soi) ou « AAAA-MM-JJ ».
fn valid_birthday(v: &str) -> bool {
    match v.len() {
        5 => valid_date(&format!("2000-{v}")),
        10 => valid_date(v),
        _ => false,
    }
}

fn valid_setting(key: &str, v: &str, personal: bool) -> bool {
    let n = v.chars().count();
    let small = |max: u32| v.len() <= 3 && v.bytes().all(|b| b.is_ascii_digit()) && v.parse::<u32>().is_ok_and(|x| x < max);
    no_controls(v)
        && match (personal, key) {
            (false, "bio") => n <= 160 && !v.contains('\n'),
            (false, "story_title") => n <= 80 && !v.contains('\n'),
            (false, "story") => n <= 4000,
            (false, "bubble_shape") => small(3),
            (false, "wallpaper") => v == "photo" || small(STYLES),
            (false, "pattern") => small(STYLES),
            (false, "pattern_opacity") | (false, "photo_dim") => small(101),
            (false, "photo_blur") => small(41),
            (false, "bubble_style") => small(4),
            (false, "theme") => small(STYLES),
            (true, "text_size") => small(3),
            (true, "birthday") => valid_birthday(v),
            (true, "bubble_color") => small(STYLES),
            _ => false,
        }
}

/// Une valeur de « Notre espace ». Clés : `s.<clé>` pour le couple, `me.<clé>` pour soi, `p.<clé>` pour lui.
#[derive(Clone, Debug, PartialEq)]
pub struct Setting {
    pub key: String,
    pub value: String,
}

pub(crate) fn apply_setting(c: &rusqlite::Connection, x: pb::Setting) -> R<Received> {
    let known = if x.personal { PERSONAL_KEYS } else { SHARED_KEYS };
    if !known.contains(&x.key.as_str()) {
        // Réglage d'une version plus récente de l'app : sans effet ici.
        return Ok(Received::Nothing);
    }
    if x.value.as_deref().is_some_and(|v| !valid_setting(&x.key, v, x.personal)) {
        return Err(DeviceError::BadMessage);
    }
    let k = format!("{}.{}", if x.personal { "p" } else { "s" }, x.key);
    if !kv_newer(c, &k, x.updated_at)? {
        return Ok(Received::Nothing);
    }
    kv_set(c, &k, x.value.as_deref(), x.updated_at)?;
    Ok(Received::Profile)
}

// ------------------------------------------------------------------ photos du couple

/// Photo du couple, couverture ou fond. `media` : sa miniature et son état (à télécharger, disponible…).
#[derive(Clone, Debug, PartialEq)]
pub struct Picture {
    pub slot: String,
    /// Identifiant du fichier, à ouvrir avec `open_media`.
    pub media_id: String,
    pub from_me: bool,
    pub media: MediaInfo,
}

/// Remplace la photo d'un emplacement ; l'ancienne est effacée (retirée de R2 si c'est la nôtre).
fn replace_slot(c: &rusqlite::Connection, slot: &str, media_id: Option<&str>, from_me: bool, at: i64) -> R<()> {
    let old: Option<(Option<String>, bool)> = c
        .query_row("SELECT media_id, from_me FROM pictures WHERE slot = ?1", params![slot], |r| Ok((r.get(0)?, r.get(1)?)))
        .optional()
        .map_err(db)?;
    if let Some((Some(old), mine)) = old
        && Some(old.as_str()) != media_id
    {
        drop_file(c, &old, mine)?;
    }
    c.execute(
        "INSERT OR REPLACE INTO pictures (slot, media_id, from_me, updated_at) VALUES (?1, ?2, ?3, ?4)",
        params![slot, media_id, from_me, at],
    )
    .map_err(db)?;
    Ok(())
}

fn slot_time(c: &rusqlite::Connection, slot: &str) -> R<Option<i64>> {
    c.query_row("SELECT updated_at FROM pictures WHERE slot = ?1", params![slot], |r| r.get(0)).optional().map_err(db)
}

pub(crate) fn apply_picture(c: &rusqlite::Connection, x: pb::Picture) -> R<Received> {
    if !SLOTS.contains(&x.slot.as_str()) {
        return Ok(Received::Nothing);
    }
    if x.file.as_ref().is_some_and(|f| !valid_file(f, &[KIND_PHOTO])) {
        return Err(DeviceError::BadMessage);
    }
    let at = i64::try_from(x.updated_at).map_err(|_| DeviceError::BadMessage)?;
    if slot_time(c, &x.slot)?.is_some_and(|cur| cur >= at) {
        return Ok(Received::Nothing);
    }
    let id = x.file.as_ref().map(|_| hex(&random16()));
    if let (Some(id), Some(f)) = (&id, &x.file) {
        insert_remote(c, id, f, FOR_PICTURE)?;
    }
    replace_slot(c, &x.slot, id.as_deref(), false, at)?;
    Ok(Received::Profile)
}

// ------------------------------------------------------------------ instants

/// Un instant, visible 24 h. `seen` : les siens, vus par moi ; les miens, vus par lui.
#[derive(Clone, Debug, PartialEq)]
pub struct Moment {
    pub id: String,
    pub from_me: bool,
    pub created_at: i64,
    /// 1 photo, 2 vidéo, 4 texte.
    pub kind: u8,
    pub text: String,
    pub style: u32,
    pub seen: bool,
    pub media: Option<MediaInfo>,
}

fn valid_moment_text(text: &str, style: u32) -> bool {
    text.chars().count() <= MAX_MOMENT_TEXT && no_controls(text) && style < STYLES
}

pub(crate) fn apply_moment(c: &rusqlite::Connection, x: pb::Moment) -> R<Received> {
    let id = id_from_wire(&x.id).ok_or(DeviceError::BadMessage)?;
    let kind = u8::try_from(x.kind).map_err(|_| DeviceError::BadMessage)?;
    let text = x.text.trim();
    let ok = valid_moment_text(text, x.style)
        && match (kind, &x.file) {
            (KIND_TEXT, None) => !text.is_empty(),
            (KIND_PHOTO | KIND_VIDEO, Some(f)) => valid_file(f, &[kind]) && f.kind == x.kind,
            _ => false,
        };
    if !ok {
        return Err(DeviceError::BadMessage);
    }
    let now = now_ms();
    let created = i64::try_from(x.created_at).map_err(|_| DeviceError::BadMessage)?;
    if created <= now - MOMENT_TTL_MS || created > now + 600_000 {
        // Arrivé trop tard (téléphone éteint plus de 24 h) : déjà expiré, on ne l'affiche pas.
        return Ok(Received::Nothing);
    }
    let n = c
        .execute(
            "INSERT OR IGNORE INTO moments (id, from_me, created_at, kind, text, style) VALUES (?1, 0, ?2, ?3, ?4, ?5)",
            params![id, created.min(now), kind, text, x.style],
        )
        .map_err(db)?;
    if n == 0 {
        return Ok(Received::Nothing);
    }
    if let Some(f) = &x.file {
        insert_remote(c, &id, f, FOR_MOMENT)?;
    }
    Ok(Received::Moments)
}

pub(crate) fn apply_moment_seen(c: &rusqlite::Connection, x: pb::Ref) -> R<Received> {
    let id = id_from_wire(&x.id).ok_or(DeviceError::BadMessage)?;
    let n = c.execute("UPDATE moments SET seen = 1 WHERE id = ?1 AND from_me = 1", params![id]).map_err(db)?;
    Ok(if n > 0 { Received::Moments } else { Received::Nothing })
}

pub(crate) fn apply_moment_gone(c: &rusqlite::Connection, x: pb::Ref) -> R<Received> {
    let id = id_from_wire(&x.id).ok_or(DeviceError::BadMessage)?;
    // Le partenaire ne peut retirer que ses propres instants.
    let n = c.execute("DELETE FROM moments WHERE id = ?1 AND from_me = 0", params![id]).map_err(db)?;
    if n > 0 {
        drop_file(c, &id, false)?;
    }
    Ok(if n > 0 { Received::Moments } else { Received::Nothing })
}

/// Réponse à un instant : son texte et sa miniature sont copiés dans le message (ils survivent à l'instant).
pub(crate) fn attach_quote(c: &rusqlite::Connection, message_id: &str, moment_id: &str) -> R<()> {
    let q: Option<(String, Option<Vec<u8>>)> = c
        .query_row(
            "SELECT mo.text, md.thumb FROM moments mo LEFT JOIN media md ON md.message_id = mo.id WHERE mo.id = ?1",
            params![moment_id],
            |r| Ok((r.get(0)?, r.get(1)?)),
        )
        .optional()
        .map_err(db)?;
    // Instant déjà expiré ou inconnu : la réponse reste un message ordinaire, avec une citation vide.
    let (text, thumb) = q.unwrap_or_default();
    c.execute(
        "UPDATE messages SET quote_text = ?2, quote_thumb = ?3 WHERE id = ?1",
        params![message_id, text, thumb.unwrap_or_default()],
    )
    .map_err(db)?;
    Ok(())
}

// ------------------------------------------------------------------ albums

#[derive(Clone, Debug, PartialEq)]
pub struct Album {
    pub id: String,
    pub title: String,
    /// Messages photo ou vidéo, dans l'ordre.
    pub items: Vec<String>,
    pub updated_at: i64,
}

fn store_album(c: &rusqlite::Connection, id: &str, title: &str, at: i64, deleted: bool, items: &[String]) -> R<bool> {
    let n = c
        .execute(
            "INSERT INTO albums (id, title, updated_at, deleted) VALUES (?1, ?2, ?3, ?4)
             ON CONFLICT (id) DO UPDATE SET title = excluded.title, updated_at = excluded.updated_at, deleted = excluded.deleted
             WHERE excluded.updated_at > albums.updated_at",
            params![id, title, at, deleted],
        )
        .map_err(db)?;
    if n == 0 {
        return Ok(false);
    }
    c.execute("DELETE FROM album_items WHERE album_id = ?1", params![id]).map_err(db)?;
    if !deleted {
        let mut st = c.prepare("INSERT OR IGNORE INTO album_items (album_id, message_id, pos) VALUES (?1, ?2, ?3)").map_err(db)?;
        for (pos, m) in items.iter().enumerate() {
            st.execute(params![id, m, pos as i64]).map_err(db)?;
        }
    }
    Ok(true)
}

pub(crate) fn apply_album(c: &rusqlite::Connection, x: pb::Album) -> R<Received> {
    let id = id_from_wire(&x.id).ok_or(DeviceError::BadMessage)?;
    let title = x.title.trim();
    let items: Vec<String> = x.items.iter().filter_map(|b| id_from_wire(b)).collect();
    let ok = x.deleted
        || (items.len() == x.items.len()
            && items.len() <= MAX_ALBUM_ITEMS
            && clean_title(title, MAX_ALBUM_TITLE).is_some());
    if !ok {
        return Err(DeviceError::BadMessage);
    }
    let at = i64::try_from(x.updated_at).map_err(|_| DeviceError::BadMessage)?;
    Ok(if store_album(c, &id, title, at, x.deleted, &items)? { Received::Albums } else { Received::Nothing })
}

fn clean_title(s: &str, max: usize) -> Option<String> {
    let t: String = s.trim().chars().filter(|c| !c.is_control()).collect();
    (!t.is_empty() && t.chars().count() <= max).then_some(t)
}

// ------------------------------------------------------------------ lettres et capsules

#[derive(Clone, Debug, PartialEq)]
pub struct Letter {
    pub id: String,
    pub from_me: bool,
    pub title: String,
    /// Vide tant que la capsule est scellée.
    pub body: String,
    pub sent_at: i64,
    /// Capsule : ne s'ouvre pas avant cette heure.
    pub open_at: Option<i64>,
    /// Les siennes : quand je l'ai ouverte. Les miennes : quand il l'a ouverte.
    pub read_at: Option<i64>,
    pub starred: bool,
    pub sealed: bool,
}

fn valid_letter(title: &str, body: &str) -> bool {
    clean_title(title, MAX_LETTER_TITLE).is_some() && !body.trim().is_empty() && body.len() <= MAX_LETTER_BYTES && no_controls(body)
}

/// Une capsule s'ouvre au plus tôt dans une minute, au plus tard dans 30 ans.
fn valid_open_at(open_at: i64, now: i64) -> bool {
    open_at > now + 60_000 && open_at < now + 30 * 366 * DAY_MS
}

pub(crate) fn apply_letter(c: &rusqlite::Connection, x: pb::Letter) -> R<Received> {
    let id = id_from_wire(&x.id).ok_or(DeviceError::BadMessage)?;
    let title = x.title.trim();
    if !valid_letter(title, &x.body) {
        return Err(DeviceError::BadMessage);
    }
    let now = now_ms();
    let sent_at = sane_time(x.sent_at, now);
    let open_at = match x.open_at {
        // Une date d'ouverture déjà passée à l'arrivée reste valable (capsule reçue en retard).
        Some(t) => Some(i64::try_from(t).ok().filter(|&t| t < now + 30 * 366 * DAY_MS).ok_or(DeviceError::BadMessage)?),
        None => None,
    };
    let n = c
        .execute(
            "INSERT OR IGNORE INTO letters (id, from_me, title, body, sent_at, open_at) VALUES (?1, 0, ?2, ?3, ?4, ?5)",
            params![id, title, x.body.trim_end(), sent_at, open_at],
        )
        .map_err(db)?;
    Ok(if n > 0 { Received::Letters } else { Received::Nothing })
}

pub(crate) fn apply_letter_read(c: &rusqlite::Connection, x: pb::Ref) -> R<Received> {
    let id = id_from_wire(&x.id).ok_or(DeviceError::BadMessage)?;
    let n = c
        .execute("UPDATE letters SET read_at = ?2 WHERE id = ?1 AND from_me = 1 AND read_at IS NULL", params![id, now_ms()])
        .map_err(db)?;
    Ok(if n > 0 { Received::Letters } else { Received::Nothing })
}

// ------------------------------------------------------------------ chiffres

/// « Vous en chiffres » et jours de flamme (jours d'affilée où vous vous êtes écrit tous les deux).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SpaceStats {
    pub messages: u32,
    pub photos: u32,
    pub videos: u32,
    pub voices: u32,
    pub letters: u32,
    /// Série en cours (aujourd'hui compris s'il est déjà « allumé », sinon jusqu'à hier).
    pub flame_days: u32,
    /// Vous vous êtes déjà écrit tous les deux aujourd'hui.
    pub flame_today: bool,
    pub best_flame: u32,
    pub first_message_at: Option<i64>,
}

/// Série de jours consécutifs : (en cours, meilleure).
fn streaks(days: &BTreeSet<i64>, today: i64) -> (u32, u32) {
    let mut best = 0u32;
    let mut run = 0u32;
    let mut prev: Option<i64> = None;
    for &d in days {
        run = if prev == Some(d - 1) { run + 1 } else { 1 };
        best = best.max(run);
        prev = Some(d);
    }
    let start = if days.contains(&today) { today } else { today - 1 };
    let mut cur = 0u32;
    while days.contains(&(start - cur as i64)) {
        cur += 1;
    }
    (cur, best)
}

impl Device {
    // -------------------------------------------------------------- réglages

    /// Toutes les valeurs de « Notre espace » connues de ce téléphone.
    pub fn settings(&self) -> R<Vec<Setting>> {
        let c = self.store.conn.lock();
        let mut st = c
            .prepare("SELECT k, v FROM kv WHERE v IS NOT NULL AND (k LIKE 's.%' OR k LIKE 'me.%' OR k LIKE 'p.%') ORDER BY k")
            .map_err(db)?;
        let rows = st.query_map([], |r| Ok(Setting { key: r.get(0)?, value: r.get(1)? })).map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    /// Modifie une valeur (vide = retirer) et l'envoie au partenaire. `personal` : elle décrit soi (anniversaire,
    /// couleur de ses bulles), sinon le couple (bio, histoire, forme des bulles, fond).
    pub fn set_setting(&mut self, partner: &str, key: &str, value: &str, personal: bool) -> R<Outgoing> {
        let v = value.trim();
        let v = if key == "story" { value.trim_matches(|c: char| c.is_whitespace()) } else { v };
        let known = if personal { PERSONAL_KEYS } else { SHARED_KEYS };
        if !known.contains(&key) || (!v.is_empty() && !valid_setting(key, v, personal)) {
            return Err(bad("valeur invalide"));
        }
        let value = (!v.is_empty()).then(|| v.to_owned());
        let k = format!("{}.{key}", if personal { "me" } else { "s" });
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let at = {
                let c = self.store.conn.lock();
                // Toujours plus récent que la valeur en place, même si l'horloge a reculé.
                let cur: Option<i64> =
                    c.query_row("SELECT at FROM kv WHERE k = ?1", params![k], |r| r.get(0)).optional().map_err(db)?;
                let at = now_ms().max(cur.map_or(0, |x| x + 1)) as u64;
                kv_set(&c, &k, value.as_deref(), at)?;
                at
            };
            let body = pb::Setting { key: key.to_owned(), value: value.clone(), updated_at: at, personal };
            self.enqueue(partner, pb::Body::Setting(body), None)
        })
    }

    // -------------------------------------------------------------- photos du couple

    pub fn pictures(&self) -> R<Vec<Picture>> {
        let c = self.store.conn.lock();
        let mut st = c
            .prepare(
                "SELECT p.slot, p.media_id, p.from_me, md.kind, md.mime, md.width, md.height, md.duration_ms, md.thumb, md.state
                 FROM pictures p JOIN media md ON md.message_id = p.media_id ORDER BY p.slot",
            )
            .map_err(db)?;
        let rows = st
            .query_map([], |r| {
                Ok(Picture {
                    slot: r.get(0)?,
                    media_id: r.get(1)?,
                    from_me: r.get(2)?,
                    media: media_info(r, 3)?,
                })
            })
            .map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    /// Nouvelle photo pour un emplacement (« avatar », « cover », « wallpaper ») : chiffrée et gardée dans `dir`,
    /// affichée aussitôt ici ; elle part chez le partenaire une fois déposée sur R2 (`media_uploaded`).
    #[allow(clippy::too_many_arguments)]
    pub fn set_picture(
        &mut self,
        dir: &Path,
        slot: &str,
        plain: &[u8],
        mime: &str,
        width: u32,
        height: u32,
        thumb: &[u8],
    ) -> R<PendingUpload> {
        if !SLOTS.contains(&slot) {
            return Err(bad("emplacement inconnu"));
        }
        let id = hex(&random16());
        let m = NewMedia { kind: KIND_PHOTO, mime, width, height, duration_ms: 0, thumb, caption: "", reply_to: None };
        let up = self.create_file(dir, &id, Some(plain), None, &m, FOR_PICTURE)?;
        let tx = self.store.conn.clone();
        let r = tx.atomically(|| {
            let c = self.store.conn.lock();
            let at = now_ms().max(slot_time(&c, slot)?.map_or(0, |x| x + 1));
            replace_slot(&c, slot, Some(&id), true, at)
        });
        if let Err(e) = r {
            let _ = drop_file(&self.store.conn.lock(), &id, false);
            return Err(e);
        }
        Ok(up)
    }

    /// Retire la photo d'un emplacement, chez les deux.
    pub fn remove_picture(&mut self, partner: &str, slot: &str) -> R<Outgoing> {
        if !SLOTS.contains(&slot) {
            return Err(bad("emplacement inconnu"));
        }
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let at = {
                let c = self.store.conn.lock();
                let at = now_ms().max(slot_time(&c, slot)?.map_or(0, |x| x + 1));
                replace_slot(&c, slot, None, true, at)?;
                at
            };
            self.enqueue(partner, pb::Body::Picture(pb::Picture { slot: slot.to_owned(), updated_at: at as u64, file: None }), None)
        })
    }

    pub(crate) fn picture_uploaded(&mut self, partner: &str, id: &str, object_key: &str) -> R<Option<Outgoing>> {
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let body = {
                let c = self.store.conn.lock();
                c.execute("UPDATE media SET object_key = ?2, state = 1 WHERE message_id = ?1 AND state = 0", params![id, object_key])
                    .map_err(db)?;
                let row: Option<(String, i64)> = c
                    .query_row("SELECT slot, updated_at FROM pictures WHERE media_id = ?1", params![id], |r| Ok((r.get(0)?, r.get(1)?)))
                    .optional()
                    .map_err(db)?;
                let Some((slot, at)) = row else {
                    // Remplacée ou retirée pendant le dépôt : le fichier ne sert plus.
                    drop_file(&c, id, true)?;
                    return Ok(None);
                };
                pb::Picture { slot, updated_at: at as u64, file: file_ref(&c, id)? }
            };
            self.enqueue(partner, pb::Body::Picture(body), None).map(Some)
        })
    }

    // -------------------------------------------------------------- instants

    /// Instants encore visibles (moins de 24 h), du plus ancien au plus récent.
    pub fn moments(&self) -> R<Vec<Moment>> {
        let c = self.store.conn.lock();
        let mut st = c
            .prepare(
                "SELECT mo.id, mo.from_me, mo.created_at, mo.kind, mo.text, mo.style, mo.seen,
                        md.kind, md.mime, md.width, md.height, md.duration_ms, md.thumb, md.state
                 FROM moments mo LEFT JOIN media md ON md.message_id = mo.id
                 WHERE mo.created_at > ?1 ORDER BY mo.created_at, mo.id",
            )
            .map_err(db)?;
        let rows = st
            .query_map(params![now_ms() - MOMENT_TTL_MS], |r| {
                Ok(Moment {
                    id: r.get(0)?,
                    from_me: r.get(1)?,
                    created_at: r.get(2)?,
                    kind: r.get::<_, i64>(3)? as u8,
                    text: r.get(4)?,
                    style: r.get::<_, i64>(5)? as u32,
                    seen: r.get(6)?,
                    media: match r.get::<_, Option<i64>>(7)? {
                        Some(_) => Some(media_info(r, 7)?),
                        None => None,
                    },
                })
            })
            .map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    /// Instant texte, sur un dégradé : part aussitôt.
    pub fn post_text_moment(&mut self, partner: &str, text: &str, style: u32) -> R<(Moment, Outgoing)> {
        let text = text.trim();
        if text.is_empty() || !valid_moment_text(text, style) {
            return Err(bad("texte vide ou trop long"));
        }
        let id = random16();
        let m = Moment {
            id: hex(&id),
            from_me: true,
            created_at: now_ms(),
            kind: KIND_TEXT,
            text: text.to_owned(),
            style,
            seen: false,
            media: None,
        };
        let tx = self.store.conn.clone();
        let out = tx.atomically(|| {
            self.store
                .conn
                .lock()
                .execute(
                    "INSERT INTO moments (id, from_me, created_at, kind, text, style) VALUES (?1, 1, ?2, ?3, ?4, ?5)",
                    params![m.id, m.created_at, KIND_TEXT, m.text, style],
                )
                .map_err(db)?;
            let body = pb::Moment { id: id.to_vec(), created_at: m.created_at as u64, kind: KIND_TEXT as u32, text: m.text.clone(), style, file: None };
            self.enqueue(partner, pb::Body::Moment(body), None)
        })?;
        Ok((m, out))
    }

    /// Instant photo ou vidéo (avec un texte facultatif) : chiffré dans `dir`, il part une fois déposé sur R2.
    /// `src` : fichier vidéo en clair (chiffré par blocs, jamais tout en mémoire) ; sinon `plain`.
    #[allow(clippy::too_many_arguments)]
    pub fn post_media_moment(
        &mut self,
        dir: &Path,
        plain: Option<&[u8]>,
        src: Option<&Path>,
        m: NewMedia<'_>,
        text: &str,
    ) -> R<(Moment, PendingUpload)> {
        let text = text.trim();
        if !matches!(m.kind, KIND_PHOTO | KIND_VIDEO) || !valid_moment_text(text, 0) {
            return Err(bad("instant invalide"));
        }
        let id = hex(&random16());
        let up = self.create_file(dir, &id, plain, src, &m, FOR_MOMENT)?;
        let created = now_ms();
        let r = self.store.conn.lock().execute(
            "INSERT INTO moments (id, from_me, created_at, kind, text, style) VALUES (?1, 1, ?2, ?3, ?4, 0)",
            params![id, created, m.kind, text],
        );
        if let Err(e) = r {
            let _ = drop_file(&self.store.conn.lock(), &id, false);
            return Err(db(e));
        }
        let moment = self.moments()?.into_iter().find(|x| x.id == id).ok_or_else(|| bad("instant introuvable"))?;
        Ok((moment, up))
    }

    pub(crate) fn moment_uploaded(&mut self, partner: &str, id: &str, object_key: &str) -> R<Option<Outgoing>> {
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let body = {
                let c = self.store.conn.lock();
                c.execute("UPDATE media SET object_key = ?2, state = 1 WHERE message_id = ?1 AND state = 0", params![id, object_key])
                    .map_err(db)?;
                let row: Option<(i64, i64, String, i64)> = c
                    .query_row(
                        "SELECT created_at, kind, text, style FROM moments WHERE id = ?1 AND from_me = 1 AND created_at > ?2",
                        params![id, now_ms() - MOMENT_TTL_MS],
                        |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
                    )
                    .optional()
                    .map_err(db)?;
                let Some((created, kind, text, style)) = row else {
                    drop_file(&c, id, true)?;
                    return Ok(None);
                };
                pb::Moment {
                    id: wire_id(id)?,
                    created_at: created as u64,
                    kind: kind as u32,
                    text,
                    style: style as u32,
                    file: file_ref(&c, id)?,
                }
            };
            self.enqueue(partner, pb::Body::Moment(body), None).map(Some)
        })
    }

    /// J'ai regardé un de ses instants : il le saura (une seule fois).
    pub fn see_moment(&mut self, partner: &str, id: &str) -> R<Option<Outgoing>> {
        let wire = wire_id(id)?;
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let n = self
                .store
                .conn
                .lock()
                .execute("UPDATE moments SET seen = 1 WHERE id = ?1 AND from_me = 0 AND seen = 0", params![id])
                .map_err(db)?;
            if n == 0 {
                return Ok(None);
            }
            self.enqueue(partner, pb::Body::MomentSeen(pb::Ref { id: wire.clone() }), None).map(Some)
        })
    }

    /// Retire un de mes instants avant ses 24 h, chez les deux.
    pub fn delete_moment(&mut self, partner: &str, id: &str) -> R<Option<Outgoing>> {
        let wire = wire_id(id)?;
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let n = {
                let c = self.store.conn.lock();
                let n = c.execute("DELETE FROM moments WHERE id = ?1 AND from_me = 1", params![id]).map_err(db)?;
                if n > 0 {
                    drop_file(&c, id, true)?;
                }
                n
            };
            if n == 0 {
                return Ok(None);
            }
            self.enqueue(partner, pb::Body::MomentGone(pb::Ref { id: wire.clone() }), None).map(Some)
        })
    }

    /// Efface les instants de plus de 24 h (et leurs fichiers ; les nôtres partent aussi de R2).
    pub fn purge_moments(&self) -> R<u32> {
        let c = self.store.conn.lock();
        let old: Vec<(String, bool)> = {
            let mut st = c.prepare("SELECT id, from_me FROM moments WHERE created_at <= ?1").map_err(db)?;
            st.query_map(params![now_ms() - MOMENT_TTL_MS], |r| Ok((r.get(0)?, r.get(1)?)))
                .map_err(db)?
                .collect::<Result<_, _>>()
                .map_err(db)?
        };
        for (id, mine) in &old {
            drop_file(&c, id, *mine)?;
            c.execute("DELETE FROM moments WHERE id = ?1", params![id]).map_err(db)?;
        }
        Ok(old.len() as u32)
    }

    /// Répond à un instant : un message ordinaire, qui cite l'instant.
    pub fn reply_to_moment(&mut self, partner: &str, moment_id: &str, body: &str) -> R<(crate::chat::ChatMessage, Outgoing)> {
        wire_id(moment_id)?;
        self.send_text_with(partner, body, None, Some(moment_id))
    }

    // -------------------------------------------------------------- fichiers à retirer de R2

    /// Objets R2 à supprimer (photo remplacée, instant expiré ou retiré).
    pub fn r2_trash(&self) -> R<Vec<String>> {
        let c = self.store.conn.lock();
        let mut st = c.prepare("SELECT object_key FROM r2_trash LIMIT 100").map_err(db)?;
        let rows = st.query_map([], |r| r.get(0)).map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    pub fn r2_trash_done(&self, object_key: &str) -> R<()> {
        self.store.conn.lock().execute("DELETE FROM r2_trash WHERE object_key = ?1", params![object_key]).map_err(db)?;
        Ok(())
    }

    // -------------------------------------------------------------- albums

    pub fn albums(&self) -> R<Vec<Album>> {
        let c = self.store.conn.lock();
        let heads: Vec<(String, String, i64)> = {
            let mut st = c.prepare("SELECT id, title, updated_at FROM albums WHERE deleted = 0 ORDER BY updated_at DESC").map_err(db)?;
            st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map_err(db)?.collect::<Result<_, _>>().map_err(db)?
        };
        let mut st = c
            .prepare(
                "SELECT a.message_id FROM album_items a JOIN messages m ON m.id = a.message_id AND m.deleted = 0
                 WHERE a.album_id = ?1 ORDER BY a.pos",
            )
            .map_err(db)?;
        heads
            .into_iter()
            .map(|(id, title, updated_at)| {
                let items = st.query_map(params![id], |r| r.get(0)).map_err(db)?.collect::<Result<_, _>>().map_err(db)?;
                Ok(Album { id, title, items, updated_at })
            })
            .collect()
    }

    /// Crée (`id` = `None`) ou modifie un album, et l'envoie en entier au partenaire.
    pub fn save_album(&mut self, partner: &str, id: Option<&str>, title: &str, items: &[String]) -> R<(Album, Outgoing)> {
        let title = clean_title(title, MAX_ALBUM_TITLE).ok_or_else(|| bad("titre vide ou trop long"))?;
        if items.len() > MAX_ALBUM_ITEMS {
            return Err(bad("album trop grand"));
        }
        let wire: Vec<Vec<u8>> = items.iter().map(|i| wire_id(i)).collect::<R<_>>()?;
        let id = match id {
            Some(i) => {
                wire_id(i)?;
                i.to_owned()
            }
            None => hex(&random16()),
        };
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let at = {
                let c = self.store.conn.lock();
                let cur: Option<i64> =
                    c.query_row("SELECT updated_at FROM albums WHERE id = ?1", params![id], |r| r.get(0)).optional().map_err(db)?;
                let at = now_ms().max(cur.map_or(0, |x| x + 1));
                store_album(&c, &id, &title, at, false, items)?;
                at
            };
            let body = pb::Album { id: wire_id(&id)?, title: title.clone(), updated_at: at as u64, deleted: false, items: wire.clone() };
            let out = self.enqueue(partner, pb::Body::Album(body), None)?;
            Ok((Album { id: id.clone(), title: title.clone(), items: items.to_vec(), updated_at: at }, out))
        })
    }

    pub fn delete_album(&mut self, partner: &str, id: &str) -> R<Outgoing> {
        let wire = wire_id(id)?;
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let at = {
                let c = self.store.conn.lock();
                let cur: Option<i64> =
                    c.query_row("SELECT updated_at FROM albums WHERE id = ?1", params![id], |r| r.get(0)).optional().map_err(db)?;
                let at = now_ms().max(cur.map_or(0, |x| x + 1));
                store_album(&c, id, "", at, true, &[])?;
                at
            };
            let body = pb::Album { id: wire.clone(), title: String::new(), updated_at: at as u64, deleted: true, items: vec![] };
            self.enqueue(partner, pb::Body::Album(body), None)
        })
    }

    // -------------------------------------------------------------- lettres

    pub fn letters(&self) -> R<Vec<Letter>> {
        let c = self.store.conn.lock();
        let now = now_ms();
        let mut st = c
            .prepare("SELECT id, from_me, title, body, sent_at, open_at, read_at, starred FROM letters ORDER BY sent_at DESC, id")
            .map_err(db)?;
        let rows = st
            .query_map([], |r| {
                let open_at: Option<i64> = r.get(5)?;
                let sealed = open_at.is_some_and(|t| t > now);
                Ok(Letter {
                    id: r.get(0)?,
                    from_me: r.get(1)?,
                    title: r.get(2)?,
                    body: if sealed { String::new() } else { r.get(3)? },
                    sent_at: r.get(4)?,
                    open_at,
                    read_at: r.get(6)?,
                    starred: r.get(7)?,
                    sealed,
                })
            })
            .map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    /// Envoie une lettre ; avec `open_at`, c'est une capsule qui ne s'ouvrira qu'à cette heure.
    pub fn send_letter(&mut self, partner: &str, title: &str, body: &str, open_at: Option<i64>) -> R<(Letter, Outgoing)> {
        let title = clean_title(title, MAX_LETTER_TITLE).ok_or_else(|| bad("titre vide ou trop long"))?;
        let body = body.trim_end();
        if !valid_letter(&title, body) {
            return Err(bad("lettre vide ou trop longue"));
        }
        let now = now_ms();
        if open_at.is_some_and(|t| !valid_open_at(t, now)) {
            return Err(bad("date d'ouverture invalide"));
        }
        let id = random16();
        let letter = Letter {
            id: hex(&id),
            from_me: true,
            title: title.clone(),
            body: body.to_owned(),
            sent_at: now,
            open_at,
            read_at: None,
            starred: false,
            sealed: open_at.is_some(),
        };
        let tx = self.store.conn.clone();
        let out = tx.atomically(|| {
            self.store
                .conn
                .lock()
                .execute(
                    "INSERT INTO letters (id, from_me, title, body, sent_at, open_at) VALUES (?1, 1, ?2, ?3, ?4, ?5)",
                    params![letter.id, title, body, now, open_at],
                )
                .map_err(db)?;
            let pbl = pb::Letter { id: id.to_vec(), sent_at: now as u64, title: title.clone(), body: body.to_owned(), open_at: open_at.map(|t| t as u64) };
            self.enqueue(partner, pb::Body::Letter(pbl), None)
        })?;
        Ok((Letter { body: if letter.sealed { String::new() } else { letter.body.clone() }, ..letter }, out))
    }

    /// J'ouvre une de ses lettres (si elle n'est plus scellée) : il le saura, une seule fois.
    pub fn read_letter(&mut self, partner: &str, id: &str) -> R<Option<Outgoing>> {
        let wire = wire_id(id)?;
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let now = now_ms();
            let n = self
                .store
                .conn
                .lock()
                .execute(
                    "UPDATE letters SET read_at = ?2 WHERE id = ?1 AND from_me = 0 AND read_at IS NULL AND (open_at IS NULL OR open_at <= ?2)",
                    params![id, now],
                )
                .map_err(db)?;
            if n == 0 {
                return Ok(None);
            }
            self.enqueue(partner, pb::Body::LetterRead(pb::Ref { id: wire.clone() }), None).map(Some)
        })
    }

    /// Lettre préférée (sur ce téléphone seulement).
    pub fn star_letter(&self, id: &str, on: bool) -> R<()> {
        self.store.conn.lock().execute("UPDATE letters SET starred = ?2 WHERE id = ?1", params![id, on]).map_err(db)?;
        Ok(())
    }

    // -------------------------------------------------------------- chiffres

    /// `utc_offset_min` : décalage horaire du téléphone, pour couper les jours à minuit chez vous.
    pub fn space_stats(&self, utc_offset_min: i32) -> R<SpaceStats> {
        let c = self.store.conn.lock();
        let mut s = SpaceStats::default();
        let count = |sql: &str| -> R<u32> { c.query_row(sql, [], |r| r.get::<_, i64>(0)).map(|n| n as u32).map_err(db) };
        s.messages = count("SELECT count(*) FROM messages WHERE deleted = 0")?;
        s.photos = count("SELECT count(*) FROM media WHERE purpose = 0 AND kind = 1")?;
        s.videos = count("SELECT count(*) FROM media WHERE purpose = 0 AND kind = 2")?;
        s.voices = count("SELECT count(*) FROM media WHERE purpose = 0 AND kind = 3")?;
        s.letters = count("SELECT count(*) FROM letters")?;
        s.first_message_at = c.query_row("SELECT min(sent_at) FROM messages", [], |r| r.get(0)).map_err(db)?;
        let off = utc_offset_min as i64 * 60_000;
        let mut by_day: HashMap<i64, u8> = HashMap::new();
        let mut st = c.prepare("SELECT DISTINCT (sent_at + ?1) / ?2, from_me FROM messages WHERE deleted = 0").map_err(db)?;
        for row in st.query_map(params![off, DAY_MS], |r| Ok((r.get::<_, i64>(0)?, r.get::<_, bool>(1)?))).map_err(db)? {
            let (day, mine) = row.map_err(db)?;
            *by_day.entry(day).or_default() |= if mine { 1 } else { 2 };
        }
        let both: BTreeSet<i64> = by_day.into_iter().filter(|&(_, v)| v == 3).map(|(d, _)| d).collect();
        let today = (now_ms() + off).div_euclid(DAY_MS);
        (s.flame_days, s.best_flame) = streaks(&both, today);
        s.flame_today = both.contains(&today);
        Ok(s)
    }
}

impl Device {
    /// Renvoie au partenaire tout ce qui est commun (après qu'on a accepté la clé de son nouveau téléphone) :
    /// prénom, date « ensemble depuis », bio, histoire, style, mes valeurs personnelles, dates, albums, photos du
    /// couple, lettres. Chaque élément garde son horodatage d'origine : chez lui, rien de plus récent n'est écrasé,
    /// et ce qu'il a déjà est ignoré. L'historique des messages, lui, ne revient que par la sauvegarde (§7).
    /// Ne fait rien si aucun renvoi n'est en attente. Renvoie le nombre d'éléments envoyés.
    /// Renvoi demandé à la main (« Renvoyer notre espace » dans les réglages).
    pub fn resync_now(&mut self, partner: &str) -> R<u32> {
        kv_set(&self.store.conn.lock(), "resync_pending", Some("1"), now_ms() as u64)?;
        self.resync_if_needed(partner)
    }

    pub fn resync_if_needed(&mut self, partner: &str) -> R<u32> {
        let pending = crate::chat::kv_get(&self.store.conn.lock(), "resync_pending")?.is_some();
        if !pending {
            return Ok(0);
        }
        let bodies: Vec<pb::Body> = {
            let c = self.store.conn.lock();
            let mut out = Vec::new();
            let kv: Vec<(String, Option<String>, i64)> = {
                let mut st = c.prepare("SELECT k, v, at FROM kv").map_err(db)?;
                st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map_err(db)?.collect::<Result<_, _>>().map_err(db)?
            };
            for (k, v, at) in kv {
                let at = at as u64;
                match k.as_str() {
                    "my_name" => {
                        if let Some(name) = v {
                            out.push(pb::Body::Profile(pb::Profile { name, updated_at: at }));
                        }
                    }
                    "together_since" => out.push(pb::Body::Couple(pb::Couple { together_since: v.unwrap_or_default(), updated_at: at })),
                    _ => {
                        let (personal, key) = match k.split_once('.') {
                            Some(("s", key)) => (false, key),
                            Some(("me", key)) => (true, key),
                            _ => continue,
                        };
                        out.push(pb::Body::Setting(pb::Setting { key: key.to_owned(), value: v, updated_at: at, personal }));
                    }
                }
            }
            let mut st = c.prepare("SELECT id, title, date, yearly, remind_days, updated_at, deleted FROM dates").map_err(db)?;
            for row in st
                .query_map([], |r| {
                    Ok((r.get::<_, String>(0)?, r.get(1)?, r.get(2)?, r.get(3)?, r.get::<_, Option<i64>>(4)?, r.get::<_, i64>(5)?, r.get(6)?))
                })
                .map_err(db)?
            {
                let (id, title, date, yearly, remind, at, deleted) = row.map_err(db)?;
                out.push(pb::Body::Date(pb::DateEntry {
                    id: wire_id(&id)?,
                    title,
                    date,
                    yearly,
                    remind_days: remind.map(|x| x as u32),
                    updated_at: at as u64,
                    deleted,
                }));
            }
            let heads: Vec<(String, String, i64, bool)> = {
                let mut st = c.prepare("SELECT id, title, updated_at, deleted FROM albums").map_err(db)?;
                st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?))).map_err(db)?.collect::<Result<_, _>>().map_err(db)?
            };
            let mut items = c.prepare("SELECT message_id FROM album_items WHERE album_id = ?1 ORDER BY pos").map_err(db)?;
            for (id, title, at, deleted) in heads {
                let ids: Vec<String> = items.query_map(params![id], |r| r.get(0)).map_err(db)?.collect::<Result<_, _>>().map_err(db)?;
                out.push(pb::Body::Album(pb::Album {
                    id: wire_id(&id)?,
                    title,
                    updated_at: at as u64,
                    deleted,
                    items: ids.iter().filter_map(|i| unhex(i)).collect(),
                }));
            }
            let pics: Vec<(String, Option<String>, i64)> = {
                let mut st = c.prepare("SELECT slot, media_id, updated_at FROM pictures").map_err(db)?;
                st.query_map([], |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?))).map_err(db)?.collect::<Result<_, _>>().map_err(db)?
            };
            for (slot, mid, at) in pics {
                let file = match mid {
                    Some(m) => match file_ref(&c, &m)? {
                        Some(f) => Some(f),
                        None => continue, // pas encore déposée : elle partira normalement après son dépôt
                    },
                    None => None,
                };
                out.push(pb::Body::Picture(pb::Picture { slot, updated_at: at as u64, file }));
            }
            // Seulement les miennes : les siennes lui reviendraient comme venant de moi.
            let mut st = c.prepare("SELECT id, title, body, sent_at, open_at FROM letters WHERE from_me = 1").map_err(db)?;
            for row in st
                .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get(1)?, r.get(2)?, r.get::<_, i64>(3)?, r.get::<_, Option<i64>>(4)?)))
                .map_err(db)?
            {
                let (id, title, body, sent_at, open_at) = row.map_err(db)?;
                out.push(pb::Body::Letter(pb::Letter {
                    id: wire_id(&id)?,
                    sent_at: sent_at as u64,
                    title,
                    body,
                    open_at: open_at.map(|x| x as u64),
                }));
            }
            out
        };
        let n = bodies.len() as u32;
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            for b in bodies.clone() {
                self.enqueue(partner, b, None)?;
            }
            self.store.conn.lock().execute("DELETE FROM kv WHERE k = 'resync_pending'", []).map_err(db)?;
            Ok(n)
        })
    }
}

/// Lit `kind, mime, width, height, duration_ms, thumb, state` à partir de la colonne `i`.
fn media_info(r: &rusqlite::Row<'_>, i: usize) -> rusqlite::Result<MediaInfo> {
    Ok(MediaInfo {
        kind: r.get::<_, i64>(i)? as u8,
        mime: r.get(i + 1)?,
        width: r.get::<_, i64>(i + 2)? as u32,
        height: r.get::<_, i64>(i + 3)? as u32,
        duration_ms: r.get::<_, i64>(i + 4)? as u32,
        thumb: r.get(i + 5)?,
        state: r.get::<_, i64>(i + 6)? as u8,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn series_de_jours() {
        let days: BTreeSet<i64> = [1, 2, 3, 7, 8, 10, 11, 12, 13].into_iter().collect();
        assert_eq!(streaks(&days, 13), (4, 4), "aujourd'hui allumé");
        assert_eq!(streaks(&days, 14), (4, 4), "pas encore aujourd'hui : la série tient jusqu'à ce soir");
        assert_eq!(streaks(&days, 15), (0, 4), "un jour manqué : la série s'éteint");
        assert_eq!(streaks(&BTreeSet::new(), 5), (0, 0));
    }

    #[test]
    fn reglages_valides() {
        assert!(valid_setting("bio", "Deux cœurs, une seule bulle.", false));
        assert!(!valid_setting("bio", &"a".repeat(161), false));
        assert!(!valid_setting("bio", "deux\nlignes", false));
        assert!(valid_setting("story", "Il pleuvait…\nOn est restés trois heures.", false));
        assert!(valid_setting("birthday", "04-12", true));
        assert!(valid_setting("birthday", "02-29", true));
        assert!(valid_setting("birthday", "1998-04-12", true));
        assert!(!valid_setting("birthday", "13-01", true));
        assert!(!valid_setting("birthday", "04-12", false), "l'anniversaire est personnel");
        assert!(valid_setting("wallpaper", "photo", false));
        assert!(valid_setting("wallpaper", "3", false));
        assert!(!valid_setting("wallpaper", "99", false));
        assert!(!valid_setting("bubble_shape", "3", false));
        assert!(!valid_setting("inconnu", "x", false));
        assert!(valid_setting("pattern_opacity", "100", false) && !valid_setting("pattern_opacity", "101", false));
        assert!(valid_setting("photo_blur", "40", false) && !valid_setting("photo_blur", "-1", false));
        assert!(valid_setting("bubble_style", "3", false) && !valid_setting("bubble_style", "4", false));
        assert!(valid_setting("text_size", "2", true) && !valid_setting("text_size", "2", false));
        assert!(!valid_setting("pattern", "007", false) || valid_setting("pattern", "7", false));
    }
}
