//! Messagerie exposée à Flutter. Toute la logique (chiffrement, remplissage, transactions, doublons)
//! est dans `foulov_core::chat` ; ici on ne fait que convertir les types.

use foulov_core::chat as core;
use foulov_core::device::Envelope as CoreEnvelope;

use crate::api::device::{Envelope, with_device};

pub struct ChatMessage {
    pub id: String,
    pub from_me: bool,
    pub body: String,
    pub reply_to: Option<String>,
    pub sent_at: i64,
    /// Envoyés : 0 en attente, 1 envoyé, 2 distribué, 3 lu. Reçus : 0 non lu, 3 lu.
    pub status: u8,
    pub my_reaction: Option<String>,
    pub their_reaction: Option<String>,
    pub media: Option<MediaInfo>,
    /// Supprimé : seule la trace « Message supprimé » reste.
    pub deleted: bool,
    /// Réponse à un instant : son texte et sa miniature.
    pub quote: Option<Quote>,
    /// Modifié par son auteur : heure de la dernière modification.
    pub edited_at: Option<i64>,
}

pub struct Quote {
    pub text: String,
    pub thumb: Vec<u8>,
}

/// Photo ou vidéo jointe. `state` : 0 à envoyer, 1 sur ce téléphone, 2 à télécharger, 3 illisible.
pub struct MediaInfo {
    pub kind: u8,
    pub mime: String,
    pub width: u32,
    pub height: u32,
    pub duration_ms: u32,
    pub thumb: Vec<u8>,
    pub state: u8,
}

impl From<core::ChatMessage> for ChatMessage {
    fn from(m: core::ChatMessage) -> Self {
        ChatMessage {
            id: m.id,
            from_me: m.from_me,
            body: m.body,
            reply_to: m.reply_to,
            sent_at: m.sent_at,
            status: m.status,
            my_reaction: m.my_reaction,
            their_reaction: m.their_reaction,
            media: m.media.map(|x| MediaInfo {
                kind: x.kind,
                mime: x.mime,
                width: x.width,
                height: x.height,
                duration_ms: x.duration_ms,
                thumb: x.thumb,
                state: x.state,
            }),
            deleted: m.deleted,
            quote: m.quote.map(|q| Quote { text: q.text, thumb: q.thumb }),
            edited_at: m.edited_at,
        }
    }
}

/// Enveloppe à déposer dans la table `envelopes` (l'identifiant sert de clé primaire : renvoi sans doublon).
pub struct Outgoing {
    pub envelope_id: String,
    pub kind: u8,
    pub body: Vec<u8>,
    /// Mérite une notification (message, réaction) ; faux pour les accusés de réception.
    pub urgent: bool,
}

impl From<core::Outgoing> for Outgoing {
    fn from(o: core::Outgoing) -> Self {
        Outgoing { envelope_id: o.envelope_id, kind: o.envelope.kind, body: o.envelope.body, urgent: o.urgent }
    }
}

pub struct SentText {
    pub message: ChatMessage,
    pub outgoing: Outgoing,
}

/// Effet d'une enveloppe reçue : un nouveau message, des messages modifiés (statut, réaction), ou rien.
pub struct Received {
    pub message: Option<ChatMessage>,
    pub updated: Vec<String>,
    /// Enveloppe illisible (altérée ou corrompue), écartée définitivement.
    pub rejected: bool,
    /// Le profil du couple a changé (prénom du partenaire, date « ensemble depuis »).
    pub profile_changed: bool,
    /// Les dates importantes ont changé.
    pub dates_changed: bool,
    pub moments_changed: bool,
    pub letters_changed: bool,
    pub albums_changed: bool,
    /// Son nouveau téléphone demande notre historique.
    pub history_requested: bool,
    /// Notre historique arrive (à télécharger puis importer).
    pub history_offered: bool,
}

/// Profil du couple, jamais visible du serveur.
pub struct CoupleProfile {
    pub my_name: Option<String>,
    pub partner_name: Option<String>,
    /// Surnom donné au partenaire : reste sur ce téléphone.
    pub partner_nickname: Option<String>,
    /// « AAAA-MM-JJ ».
    pub together_since: Option<String>,
}

pub fn chat_profile() -> anyhow::Result<CoupleProfile> {
    with_device(|d| {
        let p = d.profile()?;
        Ok(CoupleProfile {
            my_name: p.my_name,
            partner_name: p.partner_name,
            partner_nickname: p.partner_nickname,
            together_since: p.together_since,
        })
    })
}

pub fn chat_set_my_name(partner: String, name: String) -> anyhow::Result<Outgoing> {
    with_device(|d| Ok(d.set_my_name(&partner, &name)?.into()))
}

pub fn chat_set_partner_nickname(nickname: String) -> anyhow::Result<()> {
    with_device(|d| Ok(d.set_partner_nickname(&nickname)?))
}

pub fn chat_set_together_since(partner: String, date: String) -> anyhow::Result<Outgoing> {
    with_device(|d| Ok(d.set_together_since(&partner, &date)?.into()))
}

pub fn chat_send_text(partner: String, body: String, reply_to: Option<String>) -> anyhow::Result<SentText> {
    with_device(|d| {
        let (m, o) = d.send_text(&partner, &body, reply_to.as_deref())?;
        Ok(SentText { message: m.into(), outgoing: o.into() })
    })
}

/// Modifie un de ses messages (texte ou légende) dans les 15 minutes après l'envoi.
pub fn chat_edit_message(partner: String, id: String, body: String) -> anyhow::Result<SentText> {
    with_device(|d| {
        let (m, o) = d.edit_message(&partner, &id, &body)?;
        Ok(SentText { message: m.into(), outgoing: o.into() })
    })
}

/// Délai pour modifier un message, en millisecondes.
#[flutter_rust_bridge::frb(sync)]
pub fn chat_edit_window_ms() -> i64 {
    core::EDIT_WINDOW_MS
}

pub fn chat_send_reaction(partner: String, target: String, emoji: String) -> anyhow::Result<Outgoing> {
    with_device(|d| Ok(d.send_reaction(&partner, &target, &emoji)?.into()))
}

/// `kind` : 2 = distribué, 3 = lu.
pub fn chat_send_receipt(partner: String, ids: Vec<String>, kind: u8) -> anyhow::Result<Option<Outgoing>> {
    with_device(|d| Ok(d.send_receipt(&partner, &ids, kind)?.map(Into::into)))
}

pub fn chat_outbox() -> anyhow::Result<Vec<Outgoing>> {
    with_device(|d| Ok(d.outbox()?.into_iter().map(Into::into).collect()))
}

/// Le serveur a accepté l'enveloppe ; renvoie le message passé à « envoyé », s'il y en a un.
pub fn chat_outbox_sent(envelope_id: String) -> anyhow::Result<Option<String>> {
    with_device(|d| Ok(d.outbox_sent(&envelope_id)?))
}

pub fn chat_receive(partner: String, envelope_id: String, envelope: Envelope) -> anyhow::Result<Received> {
    with_device(|d| {
        let none = Received {
            message: None,
            updated: vec![],
            rejected: false,
            profile_changed: false,
            dates_changed: false,
            moments_changed: false,
            letters_changed: false,
            albums_changed: false,
            history_requested: false,
            history_offered: false,
        };
        Ok(match d.receive(&partner, &envelope_id, &CoreEnvelope { kind: envelope.kind, body: envelope.body })? {
            core::Received::Message(m) => Received { message: Some(m.into()), ..none },
            core::Received::Updated(ids) => Received { updated: ids, ..none },
            core::Received::Profile => Received { profile_changed: true, ..none },
            core::Received::Dates => Received { dates_changed: true, ..none },
            core::Received::Moments => Received { moments_changed: true, ..none },
            core::Received::Letters => Received { letters_changed: true, ..none },
            core::Received::Albums => Received { albums_changed: true, ..none },
            core::Received::HistoryRequested => Received { history_requested: true, ..none },
            core::Received::HistoryOffered => Received { history_offered: true, ..none },
            core::Received::Nothing => none,
            core::Received::Rejected => Received { rejected: true, ..none },
        })
    })
}

/// Historique du plus récent au plus ancien ; `before_*` : dernier message déjà affiché.
pub fn chat_messages(before_sent_at: Option<i64>, before_id: Option<String>, limit: u32) -> anyhow::Result<Vec<ChatMessage>> {
    with_device(|d| {
        let before = before_sent_at.zip(before_id);
        Ok(d.messages(before, limit)?.into_iter().map(Into::into).collect())
    })
}

pub fn chat_message(id: String) -> anyhow::Result<Option<ChatMessage>> {
    with_device(|d| Ok(d.message(&id)?.map(Into::into)))
}

pub fn chat_unread() -> anyhow::Result<Vec<String>> {
    with_device(|d| Ok(d.unread()?))
}

pub fn chat_purge() -> anyhow::Result<()> {
    with_device(|d| Ok(d.purge_seen()?))
}

/// Relit les contenus qu'une version précédente de l'app n'avait pas su lire (au démarrage).
pub fn chat_reprocess_unknown() -> anyhow::Result<bool> {
    with_device(|d| Ok(d.reprocess_unknown()?))
}

// ------------------------------------------------------------------ photos et vidéos

pub struct PendingUpload {
    pub message_id: String,
    pub path: String,
    pub size: u64,
}

pub struct PendingDownload {
    pub message_id: String,
    pub object_key: String,
    pub size: u64,
}

pub struct CreatedMedia {
    pub message: ChatMessage,
    pub upload: PendingUpload,
}

/// Chiffre la photo (ou vidéo), garde le chiffré dans `dir`, ajoute le message « en attente ».
#[allow(clippy::too_many_arguments)]
pub fn chat_create_media(
    dir: String,
    plain: Vec<u8>,
    kind: u8,
    mime: String,
    width: u32,
    height: u32,
    duration_ms: u32,
    thumb: Vec<u8>,
    caption: String,
    reply_to: Option<String>,
) -> anyhow::Result<CreatedMedia> {
    with_device(|d| {
        let (m, u) = d.create_media(
            std::path::Path::new(&dir),
            &plain,
            foulov_core::chat_media::NewMedia {
                kind,
                mime: &mime,
                width,
                height,
                duration_ms,
                thumb: &thumb,
                caption: &caption,
                reply_to: reply_to.as_deref(),
            },
        )?;
        Ok(CreatedMedia {
            message: m.into(),
            upload: PendingUpload { message_id: u.message_id, path: u.path, size: u.size },
        })
    })
}

/// Le chiffré est sur R2 : prépare le message chiffré pour le partenaire (à vider par la boîte d'envoi).
/// `None` : plus rien à envoyer (photo du couple remplacée, instant retiré pendant le dépôt).
pub fn chat_media_uploaded(partner: String, message_id: String, object_key: String) -> anyhow::Result<Option<Outgoing>> {
    with_device(|d| Ok(d.media_uploaded(&partner, &message_id, &object_key)?.map(Into::into)))
}

pub fn chat_pending_uploads() -> anyhow::Result<Vec<PendingUpload>> {
    with_device(|d| {
        Ok(d.pending_uploads()?
            .into_iter()
            .map(|u| PendingUpload { message_id: u.message_id, path: u.path, size: u.size })
            .collect())
    })
}

pub fn chat_pending_downloads() -> anyhow::Result<Vec<PendingDownload>> {
    with_device(|d| {
        Ok(d.pending_downloads()?
            .into_iter()
            .map(|u| PendingDownload { message_id: u.message_id, object_key: u.object_key, size: u.size })
            .collect())
    })
}

/// Vérifie le fichier téléchargé (taille, empreinte) et le range dans `dir`. Faux s'il a été altéré.
pub fn chat_media_downloaded(message_id: String, downloaded: String, dir: String) -> anyhow::Result<bool> {
    with_device(|d| Ok(d.media_downloaded(&message_id, std::path::Path::new(&downloaded), std::path::Path::new(&dir))?))
}

/// Déchiffre en mémoire pour l'affichage.
pub fn chat_open_media(message_id: String) -> anyhow::Result<Vec<u8>> {
    with_device(|d| Ok(d.open_media(&message_id)?))
}

/// Comme `chat_create_media`, mais chiffre directement depuis un fichier (vidéos), sans tout charger en mémoire.
#[allow(clippy::too_many_arguments)]
pub fn chat_create_media_file(
    dir: String,
    src: String,
    kind: u8,
    mime: String,
    width: u32,
    height: u32,
    duration_ms: u32,
    thumb: Vec<u8>,
    caption: String,
    reply_to: Option<String>,
) -> anyhow::Result<CreatedMedia> {
    with_device(|d| {
        let (m, u) = d.create_media_file(
            std::path::Path::new(&dir),
            std::path::Path::new(&src),
            foulov_core::chat_media::NewMedia {
                kind,
                mime: &mime,
                width,
                height,
                duration_ms,
                thumb: &thumb,
                caption: &caption,
                reply_to: reply_to.as_deref(),
            },
        )?;
        Ok(CreatedMedia {
            message: m.into(),
            upload: PendingUpload { message_id: u.message_id, path: u.path, size: u.size },
        })
    })
}

/// Taille réelle (déchiffrée) d'une photo ou vidéo.
pub fn chat_media_len(message_id: String) -> anyhow::Result<u64> {
    with_device(|d| Ok(d.media_len(&message_id)?))
}

/// Morceau déchiffré (au plus 4 Mio) : lecture vidéo sans fichier en clair.
pub fn chat_media_read(message_id: String, offset: u64, len: u32) -> anyhow::Result<Vec<u8>> {
    with_device(|d| Ok(d.media_read(&message_id, offset, len)?))
}

/// Photos et vidéos (onglet Souvenirs), de la plus récente à la plus ancienne. `kind` : 1 photos, 2 vidéos, 3 vocaux.
pub fn chat_media_gallery(
    before_sent_at: Option<i64>,
    before_id: Option<String>,
    limit: u32,
    kind: Option<u8>,
) -> anyhow::Result<Vec<ChatMessage>> {
    with_device(|d| Ok(d.media_gallery(before_sent_at.zip(before_id), limit, kind)?.into_iter().map(Into::into).collect()))
}

/// « Supprimer pour moi » : sur ce téléphone seulement.
pub fn chat_delete_for_me(id: String) -> anyhow::Result<bool> {
    with_device(|d| Ok(d.delete_for_me(&id)?))
}

pub struct DeletedForBoth {
    pub outgoing: Outgoing,
    /// Photo ou vidéo déjà déposée : objet à effacer sur R2.
    pub object_key: Option<String>,
}

/// « Supprimer pour nous deux » (ses propres messages seulement).
pub fn chat_delete_for_both(partner: String, id: String) -> anyhow::Result<DeletedForBoth> {
    with_device(|d| {
        let (o, k) = d.delete_for_both(&partner, &id)?;
        Ok(DeletedForBoth { outgoing: o.into(), object_key: k })
    })
}

// ------------------------------------------------------------------ dates importantes

/// `remind_days` : aucun rappel (`None`) ou nombre de jours avant (0 = le jour même).
pub struct DateEntry {
    pub id: String,
    pub title: String,
    /// « AAAA-MM-JJ ».
    pub date: String,
    pub yearly: bool,
    pub remind_days: Option<u8>,
    pub updated_at: i64,
}

impl From<foulov_core::dates::DateEntry> for DateEntry {
    fn from(e: foulov_core::dates::DateEntry) -> Self {
        DateEntry { id: e.id, title: e.title, date: e.date, yearly: e.yearly, remind_days: e.remind_days, updated_at: e.updated_at }
    }
}

pub struct SavedDate {
    pub entry: DateEntry,
    pub outgoing: Outgoing,
}

pub fn chat_dates() -> anyhow::Result<Vec<DateEntry>> {
    with_device(|d| Ok(d.dates()?.into_iter().map(Into::into).collect()))
}

/// Crée (id vide) ou modifie une date, envoyée chiffrée au partenaire.
pub fn chat_save_date(partner: String, entry: DateEntry) -> anyhow::Result<SavedDate> {
    with_device(|d| {
        let (e, o) = d.save_date(
            &partner,
            foulov_core::dates::DateEntry {
                id: entry.id,
                title: entry.title,
                date: entry.date,
                yearly: entry.yearly,
                remind_days: entry.remind_days,
                updated_at: 0,
            },
        )?;
        Ok(SavedDate { entry: e.into(), outgoing: o.into() })
    })
}

pub fn chat_delete_date(partner: String, id: String) -> anyhow::Result<Outgoing> {
    with_device(|d| Ok(d.delete_date(&partner, &id)?.into()))
}

// ------------------------------------------------------------------ stickers

/// Un sticker de la bibliothèque (son image se lit avec `sticker_data`).
pub struct Sticker {
    pub id: String,
    pub mime: String,
    pub width: u32,
    pub height: u32,
    pub favorite: bool,
    pub added_at: i64,
    pub used_at: i64,
}

pub struct StickerAdded {
    pub id: String,
    /// Faux : il y était déjà.
    pub added: bool,
}

pub struct StickerFound {
    pub id: String,
    pub favorite: bool,
}

pub fn sticker_list() -> anyhow::Result<Vec<Sticker>> {
    with_device(|d| {
        Ok(d.stickers()?
            .into_iter()
            .map(|s| Sticker {
                id: s.id,
                mime: s.mime,
                width: s.width,
                height: s.height,
                favorite: s.favorite,
                added_at: s.added_at,
                used_at: s.used_at,
            })
            .collect())
    })
}

pub fn sticker_add(data: Vec<u8>, mime: String, width: u32, height: u32) -> anyhow::Result<StickerAdded> {
    with_device(|d| {
        let (id, added) = d.sticker_add(&data, &mime, width, height)?;
        Ok(StickerAdded { id, added })
    })
}

pub fn sticker_data(id: String) -> anyhow::Result<Option<Vec<u8>>> {
    with_device(|d| Ok(d.sticker_data(&id)?))
}

pub fn sticker_find(data: Vec<u8>) -> anyhow::Result<Option<StickerFound>> {
    with_device(|d| Ok(d.sticker_find(&data)?.map(|(id, favorite)| StickerFound { id, favorite })))
}

pub fn sticker_set_favorite(id: String, favorite: bool) -> anyhow::Result<()> {
    with_device(|d| Ok(d.sticker_set_favorite(&id, favorite)?))
}

pub fn sticker_used(id: String) -> anyhow::Result<()> {
    with_device(|d| Ok(d.sticker_used(&id)?))
}

pub fn sticker_delete(id: String) -> anyhow::Result<()> {
    with_device(|d| Ok(d.sticker_delete(&id)?))
}
