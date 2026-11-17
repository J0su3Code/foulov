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
        let none = Received { message: None, updated: vec![], rejected: false };
        Ok(match d.receive(&partner, &envelope_id, &CoreEnvelope { kind: envelope.kind, body: envelope.body })? {
            core::Received::Message(m) => Received { message: Some(m.into()), ..none },
            core::Received::Updated(ids) => Received { updated: ids, ..none },
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
