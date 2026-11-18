//! « Notre espace » exposé à Flutter : réglages, photos du couple, instants, albums, lettres, chiffres.
//! La logique (chiffrement, validation, « le plus récent l'emporte ») est dans `foulov_core::space`.

use std::path::Path;

use foulov_core::chat_media::NewMedia;
use foulov_core::space as core;

use crate::api::chat::{ChatMessage, MediaInfo, Outgoing, PendingUpload, SentText};
use crate::api::device::with_device;

fn info(m: foulov_core::chat::MediaInfo) -> MediaInfo {
    MediaInfo {
        kind: m.kind,
        mime: m.mime,
        width: m.width,
        height: m.height,
        duration_ms: m.duration_ms,
        thumb: m.thumb,
        state: m.state,
    }
}

fn upload(u: foulov_core::chat_media::PendingUpload) -> PendingUpload {
    PendingUpload { message_id: u.message_id, path: u.path, size: u.size }
}

// ------------------------------------------------------------------ réglages

/// Clés : `s.<clé>` pour le couple, `me.<clé>` pour soi, `p.<clé>` pour le partenaire.
pub struct SpaceSetting {
    pub key: String,
    pub value: String,
}

pub fn space_settings() -> anyhow::Result<Vec<SpaceSetting>> {
    with_device(|d| Ok(d.settings()?.into_iter().map(|s| SpaceSetting { key: s.key, value: s.value }).collect()))
}

/// Valeur vide = retirée. `personal` : anniversaire, couleur de ses bulles ; sinon bio, histoire, forme, fond.
pub fn space_set_setting(partner: String, key: String, value: String, personal: bool) -> anyhow::Result<Outgoing> {
    with_device(|d| Ok(d.set_setting(&partner, &key, &value, personal)?.into()))
}

// ------------------------------------------------------------------ photos du couple

pub struct SpacePicture {
    /// « avatar », « cover » ou « wallpaper ».
    pub slot: String,
    pub media_id: String,
    pub from_me: bool,
    pub media: MediaInfo,
}

pub fn space_pictures() -> anyhow::Result<Vec<SpacePicture>> {
    with_device(|d| {
        Ok(d.pictures()?
            .into_iter()
            .map(|p| SpacePicture { slot: p.slot, media_id: p.media_id, from_me: p.from_me, media: info(p.media) })
            .collect())
    })
}

#[allow(clippy::too_many_arguments)]
pub fn space_set_picture(
    dir: String,
    slot: String,
    plain: Vec<u8>,
    mime: String,
    width: u32,
    height: u32,
    thumb: Vec<u8>,
) -> anyhow::Result<PendingUpload> {
    with_device(|d| Ok(upload(d.set_picture(Path::new(&dir), &slot, &plain, &mime, width, height, &thumb)?)))
}

pub fn space_remove_picture(partner: String, slot: String) -> anyhow::Result<Outgoing> {
    with_device(|d| Ok(d.remove_picture(&partner, &slot)?.into()))
}

// ------------------------------------------------------------------ instants

pub struct Moment {
    pub id: String,
    pub from_me: bool,
    pub created_at: i64,
    /// 1 photo, 2 vidéo, 4 texte.
    pub kind: u8,
    pub text: String,
    pub style: u32,
    /// Les siens : vus par moi. Les miens : vus par lui.
    pub seen: bool,
    pub media: Option<MediaInfo>,
}

fn moment(m: core::Moment) -> Moment {
    Moment {
        id: m.id,
        from_me: m.from_me,
        created_at: m.created_at,
        kind: m.kind,
        text: m.text,
        style: m.style,
        seen: m.seen,
        media: m.media.map(info),
    }
}

pub struct PostedMoment {
    pub moment: Moment,
    pub outgoing: Option<Outgoing>,
    pub upload: Option<PendingUpload>,
}

pub fn space_moments() -> anyhow::Result<Vec<Moment>> {
    with_device(|d| Ok(d.moments()?.into_iter().map(moment).collect()))
}

pub fn space_post_text_moment(partner: String, text: String, style: u32) -> anyhow::Result<PostedMoment> {
    with_device(|d| {
        let (m, o) = d.post_text_moment(&partner, &text, style)?;
        Ok(PostedMoment { moment: moment(m), outgoing: Some(o.into()), upload: None })
    })
}

/// Photo (`plain`) ou vidéo (`src`, fichier en clair chiffré par blocs).
#[allow(clippy::too_many_arguments)]
pub fn space_post_media_moment(
    dir: String,
    plain: Option<Vec<u8>>,
    src: Option<String>,
    kind: u8,
    mime: String,
    width: u32,
    height: u32,
    duration_ms: u32,
    thumb: Vec<u8>,
    text: String,
) -> anyhow::Result<PostedMoment> {
    with_device(|d| {
        let m = NewMedia { kind, mime: &mime, width, height, duration_ms, thumb: &thumb, caption: "", reply_to: None };
        let (mo, up) = d.post_media_moment(Path::new(&dir), plain.as_deref(), src.as_deref().map(Path::new), m, &text)?;
        Ok(PostedMoment { moment: moment(mo), outgoing: None, upload: Some(upload(up)) })
    })
}

pub fn space_see_moment(partner: String, id: String) -> anyhow::Result<Option<Outgoing>> {
    with_device(|d| Ok(d.see_moment(&partner, &id)?.map(Into::into)))
}

pub fn space_delete_moment(partner: String, id: String) -> anyhow::Result<Option<Outgoing>> {
    with_device(|d| Ok(d.delete_moment(&partner, &id)?.map(Into::into)))
}

pub fn space_purge_moments() -> anyhow::Result<u32> {
    with_device(|d| Ok(d.purge_moments()?))
}

pub fn space_reply_to_moment(partner: String, moment_id: String, body: String) -> anyhow::Result<SentText> {
    with_device(|d| {
        let (m, o) = d.reply_to_moment(&partner, &moment_id, &body)?;
        let message: ChatMessage = m.into();
        Ok(SentText { message, outgoing: o.into() })
    })
}

// ------------------------------------------------------------------ corbeille R2

pub fn space_r2_trash() -> anyhow::Result<Vec<String>> {
    with_device(|d| Ok(d.r2_trash()?))
}

pub fn space_r2_trash_done(object_key: String) -> anyhow::Result<()> {
    with_device(|d| Ok(d.r2_trash_done(&object_key)?))
}

// ------------------------------------------------------------------ albums

pub struct Album {
    pub id: String,
    pub title: String,
    pub items: Vec<String>,
    pub updated_at: i64,
}

pub struct SavedAlbum {
    pub album: Album,
    pub outgoing: Outgoing,
}

fn album(a: core::Album) -> Album {
    Album { id: a.id, title: a.title, items: a.items, updated_at: a.updated_at }
}

pub fn space_albums() -> anyhow::Result<Vec<Album>> {
    with_device(|d| Ok(d.albums()?.into_iter().map(album).collect()))
}

pub fn space_save_album(partner: String, id: Option<String>, title: String, items: Vec<String>) -> anyhow::Result<SavedAlbum> {
    with_device(|d| {
        let (a, o) = d.save_album(&partner, id.as_deref(), &title, &items)?;
        Ok(SavedAlbum { album: album(a), outgoing: o.into() })
    })
}

pub fn space_delete_album(partner: String, id: String) -> anyhow::Result<Outgoing> {
    with_device(|d| Ok(d.delete_album(&partner, &id)?.into()))
}

// ------------------------------------------------------------------ lettres

pub struct Letter {
    pub id: String,
    pub from_me: bool,
    pub title: String,
    /// Vide tant que la capsule est scellée.
    pub body: String,
    pub sent_at: i64,
    pub open_at: Option<i64>,
    pub read_at: Option<i64>,
    pub starred: bool,
    pub sealed: bool,
}

pub struct SentLetter {
    pub letter: Letter,
    pub outgoing: Outgoing,
}

fn letter(l: core::Letter) -> Letter {
    Letter {
        id: l.id,
        from_me: l.from_me,
        title: l.title,
        body: l.body,
        sent_at: l.sent_at,
        open_at: l.open_at,
        read_at: l.read_at,
        starred: l.starred,
        sealed: l.sealed,
    }
}

pub fn space_letters() -> anyhow::Result<Vec<Letter>> {
    with_device(|d| Ok(d.letters()?.into_iter().map(letter).collect()))
}

pub fn space_send_letter(partner: String, title: String, body: String, open_at: Option<i64>) -> anyhow::Result<SentLetter> {
    with_device(|d| {
        let (l, o) = d.send_letter(&partner, &title, &body, open_at)?;
        Ok(SentLetter { letter: letter(l), outgoing: o.into() })
    })
}

pub fn space_read_letter(partner: String, id: String) -> anyhow::Result<Option<Outgoing>> {
    with_device(|d| Ok(d.read_letter(&partner, &id)?.map(Into::into)))
}

pub fn space_star_letter(id: String, on: bool) -> anyhow::Result<()> {
    with_device(|d| Ok(d.star_letter(&id, on)?))
}

// ------------------------------------------------------------------ chiffres

pub struct SpaceStats {
    pub messages: u32,
    pub photos: u32,
    pub videos: u32,
    pub voices: u32,
    pub letters: u32,
    pub flame_days: u32,
    pub flame_today: bool,
    pub best_flame: u32,
    pub first_message_at: Option<i64>,
}

pub fn space_stats(utc_offset_min: i32) -> anyhow::Result<SpaceStats> {
    with_device(|d| {
        let s = d.space_stats(utc_offset_min)?;
        Ok(SpaceStats {
            messages: s.messages,
            photos: s.photos,
            videos: s.videos,
            voices: s.voices,
            letters: s.letters,
            flame_days: s.flame_days,
            flame_today: s.flame_today,
            best_flame: s.best_flame,
            first_message_at: s.first_message_at,
        })
    })
}
