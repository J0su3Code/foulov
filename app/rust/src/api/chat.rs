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
        let none = Received { message: None, updated: vec![], rejected: false, profile_changed: false };
        Ok(match d.receive(&partner, &envelope_id, &CoreEnvelope { kind: envelope.kind, body: envelope.body })? {
            core::Received::Message(m) => Received { message: Some(m.into()), ..none },
            core::Received::Updated(ids) => Received { updated: ids, ..none },
            core::Received::Profile => Received { profile_changed: true, ..none },
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
pub fn chat_media_uploaded(partner: String, message_id: String, object_key: String) -> anyhow::Result<Outgoing> {
    with_device(|d| Ok(d.media_uploaded(&partner, &message_id, &object_key)?.into()))
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
