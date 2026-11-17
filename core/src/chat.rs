//! Messagerie du couple (`docs/SECURITY.md` §4bis).
//!
//! - Chaque contenu (texte, accusé de réception, réaction) est encodé en protobuf, préfixé d'un octet de
//!   version, puis complété jusqu'au multiple de 160 octets suivant (remplissage de Signal : 0x80 puis des
//!   zéros). Le serveur ne voit donc qu'une taille arrondie, puis le tout est chiffré par la session Signal.
//! - Déchiffrer et enregistrer se font dans **une seule transaction** : si l'app s'arrête au milieu, ni le
//!   ratchet ni l'historique n'avancent, et l'enveloppe sera simplement retraitée.
//! - Envoyer : le message et son enveloppe chiffrée sont enregistrés ensemble dans la boîte d'envoi. En cas
//!   d'échec réseau, on renvoie exactement la même enveloppe (même identifiant) : le serveur ignore le doublon.
//! - Une enveloppe déjà traitée n'est jamais appliquée deux fois (table `seen_envelopes`).

use std::time::{SystemTime, UNIX_EPOCH};

use prost::Message as _;
use rand::TryRngCore as _;
use rand::rngs::OsRng;
use rusqlite::{OptionalExtension, params};

use crate::device::{Device, DeviceError, Envelope};
use crate::store::StoreError;

/// Version du format des contenus, en tête du texte clair.
const FORMAT_V1: u8 = 1;
/// Taille des blocs de remplissage (la même que Signal).
const PAD_BLOCK: usize = 160;
/// Longueur maximale d'un message texte, en octets UTF-8.
pub const MAX_TEXT_BYTES: usize = 16 * 1024;
/// Plaintext historique envoyé à l'appairage (`CoupleService._hello`) : reconnu et ignoré.
const LEGACY_HELLO: &[u8] = b"FOULOVE:BONJOUR:1";

pub mod pb {
    //! Schéma des contenus chiffrés. Ne jamais réutiliser un numéro de champ.

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Content {
        #[prost(oneof = "Body", tags = "1, 2, 3, 4, 5, 6, 7, 8")]
        pub body: Option<Body>,
    }

    #[derive(Clone, PartialEq, prost::Oneof)]
    pub enum Body {
        #[prost(message, tag = "1")]
        Text(Text),
        #[prost(message, tag = "2")]
        Receipt(Receipt),
        #[prost(message, tag = "3")]
        Reaction(Reaction),
        #[prost(message, tag = "4")]
        Profile(Profile),
        #[prost(message, tag = "5")]
        Couple(Couple),
        #[prost(message, tag = "6")]
        Media(Media),
        #[prost(message, tag = "7")]
        Delete(Delete),
        #[prost(message, tag = "8")]
        Date(DateEntry),
    }

    /// Une date importante du couple (ou sa suppression).
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct DateEntry {
        #[prost(bytes = "vec", tag = "1")]
        pub id: Vec<u8>,
        #[prost(string, tag = "2")]
        pub title: String,
        /// « AAAA-MM-JJ ».
        #[prost(string, tag = "3")]
        pub date: String,
        #[prost(bool, tag = "4")]
        pub yearly: bool,
        #[prost(uint32, optional, tag = "5")]
        pub remind_days: Option<u32>,
        #[prost(uint64, tag = "6")]
        pub updated_at: u64,
        #[prost(bool, tag = "7")]
        pub deleted: bool,
    }

    /// « Supprimer pour nous deux » : l'expéditeur retire un de ses propres messages.
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Delete {
        #[prost(bytes = "vec", tag = "1")]
        pub target: Vec<u8>,
    }

    /// Photo ou vidéo. Le fichier, chiffré sur le téléphone, est sur R2 sous un nom aléatoire ; sa clé, son
    /// empreinte, ses dimensions et une miniature voyagent ici, dans le message chiffré.
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Media {
        #[prost(bytes = "vec", tag = "1")]
        pub id: Vec<u8>,
        #[prost(uint64, tag = "2")]
        pub sent_at: u64,
        #[prost(string, tag = "3")]
        pub caption: String,
        #[prost(bytes = "vec", optional, tag = "4")]
        pub reply_to: Option<Vec<u8>>,
        /// 1 = photo, 2 = vidéo.
        #[prost(uint32, tag = "5")]
        pub kind: u32,
        #[prost(string, tag = "6")]
        pub object_key: String,
        #[prost(bytes = "vec", tag = "7")]
        pub file_key: Vec<u8>,
        /// SHA-256 du fichier chiffré.
        #[prost(bytes = "vec", tag = "8")]
        pub sha256: Vec<u8>,
        /// Taille du fichier chiffré.
        #[prost(uint64, tag = "9")]
        pub size: u64,
        #[prost(string, tag = "10")]
        pub mime: String,
        #[prost(uint32, tag = "11")]
        pub width: u32,
        #[prost(uint32, tag = "12")]
        pub height: u32,
        #[prost(uint32, tag = "13")]
        pub duration_ms: u32,
        /// Miniature JPEG, affichée aussitôt pendant le téléchargement.
        #[prost(bytes = "vec", tag = "14")]
        pub thumb: Vec<u8>,
    }

    /// Le prénom que l'expéditeur se donne (affiché chez le partenaire, sauf s'il lui a choisi un surnom).
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Profile {
        #[prost(string, tag = "1")]
        pub name: String,
        #[prost(uint64, tag = "2")]
        pub updated_at: u64,
    }

    /// Informations communes au couple. La modification la plus récente l'emporte, des deux côtés.
    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Couple {
        /// « AAAA-MM-JJ », vide si non renseignée.
        #[prost(string, tag = "1")]
        pub together_since: String,
        #[prost(uint64, tag = "2")]
        pub updated_at: u64,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Text {
        /// Identifiant aléatoire de 16 octets choisi par l'expéditeur.
        #[prost(bytes = "vec", tag = "1")]
        pub id: Vec<u8>,
        /// Heure d'envoi selon l'expéditeur, en millisecondes.
        #[prost(uint64, tag = "2")]
        pub sent_at: u64,
        #[prost(string, tag = "3")]
        pub body: String,
        #[prost(bytes = "vec", optional, tag = "4")]
        pub reply_to: Option<Vec<u8>>,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Receipt {
        /// 2 = distribué, 3 = lu (mêmes valeurs que `status`).
        #[prost(uint32, tag = "1")]
        pub kind: u32,
        #[prost(bytes = "vec", repeated, tag = "2")]
        pub ids: Vec<Vec<u8>>,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Reaction {
        #[prost(bytes = "vec", tag = "1")]
        pub target: Vec<u8>,
        /// Vide = réaction retirée.
        #[prost(string, tag = "2")]
        pub emoji: String,
    }
}

pub const STATUS_PENDING: u8 = 0;
pub const STATUS_SENT: u8 = 1;
pub const STATUS_DELIVERED: u8 = 2;
pub const STATUS_READ: u8 = 3;

/// Photo ou vidéo jointe à un message.
#[derive(Clone, Debug, PartialEq)]
pub struct MediaInfo {
    /// 1 = photo, 2 = vidéo.
    pub kind: u8,
    pub mime: String,
    pub width: u32,
    pub height: u32,
    pub duration_ms: u32,
    pub thumb: Vec<u8>,
    /// 0 = à envoyer, 1 = sur ce téléphone, 2 = à télécharger, 3 = illisible (altéré).
    pub state: u8,
}

/// Un message de l'historique local.
#[derive(Clone, Debug, PartialEq)]
pub struct ChatMessage {
    /// 32 caractères hexadécimaux.
    pub id: String,
    pub from_me: bool,
    pub body: String,
    pub reply_to: Option<String>,
    pub sent_at: i64,
    pub status: u8,
    pub my_reaction: Option<String>,
    pub their_reaction: Option<String>,
    pub media: Option<MediaInfo>,
    /// Supprimé : il ne reste que la trace « Message supprimé » (ni texte, ni fichier, ni réaction).
    pub deleted: bool,
}

/// Enveloppe chiffrée à déposer sur le serveur, avec son identifiant (format UUID, choisi ici).
#[derive(Clone, Debug)]
pub struct Outgoing {
    pub envelope_id: String,
    pub envelope: Envelope,
    /// Mérite une notification (message, réaction). Les accusés de réception ne réveillent pas le téléphone :
    /// le serveur apprend seulement « notifier ou non », comme avec l'indicateur `urgent` de Signal.
    pub urgent: bool,
}

/// Profil du couple, tel que vu par ce téléphone. Rien de tout cela n'est visible du serveur.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct CoupleProfile {
    pub my_name: Option<String>,
    /// Prénom envoyé par le partenaire.
    pub partner_name: Option<String>,
    /// Surnom donné au partenaire : reste sur ce téléphone, jamais envoyé.
    pub partner_nickname: Option<String>,
    /// « AAAA-MM-JJ ».
    pub together_since: Option<String>,
}

const MAX_NAME_CHARS: usize = 40;

fn clean_name(s: &str) -> Option<String> {
    let t: String = s.trim().chars().filter(|c| !c.is_control()).collect();
    (!t.is_empty() && t.chars().count() <= MAX_NAME_CHARS).then_some(t)
}

/// Date « AAAA-MM-JJ » plausible (de 1900 à aujourd'hui + 1 an), vérifiée sans dépendance.
pub(crate) fn valid_date(s: &str) -> bool {
    let b = s.as_bytes();
    if b.len() != 10 || b[4] != b'-' || b[7] != b'-' {
        return false;
    }
    let (Ok(y), Ok(m), Ok(d)) = (s[0..4].parse::<u32>(), s[5..7].parse::<u32>(), s[8..10].parse::<u32>()) else {
        return false;
    };
    let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
    let days = [31, if leap { 29 } else { 28 }, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    (1900..=2200).contains(&y) && (1..=12).contains(&m) && d >= 1 && d <= days[(m - 1) as usize]
}

/// Ce que la réception d'une enveloppe a changé.
#[derive(Clone, Debug, PartialEq)]
pub enum Received {
    /// Nouveau message du partenaire (il faut lui renvoyer un accusé « distribué »).
    Message(ChatMessage),
    /// Messages dont le statut ou les réactions ont changé.
    Updated(Vec<String>),
    /// Le profil du couple a changé (prénom du partenaire, date « ensemble depuis »).
    Profile,
    /// Les dates importantes ont changé.
    Dates,
    /// Rien à afficher : doublon, message d'appairage, contenu d'une version future.
    Nothing,
    /// Enveloppe illisible (altérée ou corrompue) : écartée, jamais affichée.
    Rejected,
}

pub(crate) type R<T> = Result<T, DeviceError>;

pub(crate) fn db(e: rusqlite::Error) -> DeviceError {
    DeviceError::Store(StoreError::from(e))
}

pub(crate) fn now_ms() -> i64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0)
}

pub(crate) fn random16() -> [u8; 16] {
    let mut b = [0u8; 16];
    OsRng.try_fill_bytes(&mut b).expect("générateur du système");
    b
}

pub(crate) fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

pub(crate) fn unhex(s: &str) -> Option<Vec<u8>> {
    if s.len() % 2 != 0 {
        return None;
    }
    (0..s.len()).step_by(2).map(|i| u8::from_str_radix(s.get(i..i + 2)?, 16).ok()).collect()
}

/// Identifiant de message reçu : exactement 16 octets.
pub(crate) fn id_from_wire(b: &[u8]) -> Option<String> {
    (b.len() == 16).then(|| hex(b))
}

/// UUID version 4 (format attendu par la colonne `envelopes.id`).
fn uuid_v4() -> String {
    let mut b = random16();
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    let h = hex(&b);
    format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

/// Remplissage de Signal : 0x80 puis des zéros jusqu'au multiple de 160 octets suivant.
pub fn pad(mut plain: Vec<u8>) -> Vec<u8> {
    plain.push(0x80);
    let target = plain.len().div_ceil(PAD_BLOCK) * PAD_BLOCK;
    plain.resize(target, 0);
    plain
}

/// Retire le remplissage ; refuse tout ce qui n'en a pas la forme exacte.
pub fn unpad(padded: &[u8]) -> Option<&[u8]> {
    let end = padded.iter().rposition(|&b| b != 0)?;
    (padded[end] == 0x80).then(|| &padded[..end])
}

fn encode(body: pb::Body) -> Vec<u8> {
    let mut v = vec![FORMAT_V1];
    pb::Content { body: Some(body) }.encode(&mut v).expect("Vec extensible");
    pad(v)
}

pub(crate) fn row_to_message(r: &rusqlite::Row<'_>) -> rusqlite::Result<ChatMessage> {
    let kind: Option<i64> = r.get(8)?;
    let media = match kind {
        Some(k) => Some(MediaInfo {
            kind: k as u8,
            mime: r.get(9)?,
            width: r.get::<_, i64>(10)? as u32,
            height: r.get::<_, i64>(11)? as u32,
            duration_ms: r.get::<_, i64>(12)? as u32,
            thumb: r.get(13)?,
            state: r.get::<_, i64>(14)? as u8,
        }),
        None => None,
    };
    Ok(ChatMessage {
        id: r.get(0)?,
        from_me: r.get::<_, i64>(1)? == 1,
        body: r.get(2)?,
        reply_to: r.get(3)?,
        sent_at: r.get(4)?,
        status: r.get::<_, i64>(5)? as u8,
        my_reaction: r.get(6)?,
        their_reaction: r.get(7)?,
        media,
        deleted: r.get::<_, i64>(15)? == 1,
    })
}

/// Efface le contenu d'un message (texte, réactions, photo ou vidéo et son fichier chiffré local) et ne garde que
/// la trace « supprimé ». `from_me` : n'agit que sur les messages de cet auteur (`None` : n'importe lequel).
pub(crate) fn erase(c: &rusqlite::Connection, id: &str, from_me: Option<bool>) -> R<bool> {
    let n = c
        .execute(
            "UPDATE messages SET body = '', my_reaction = NULL, their_reaction = NULL, deleted = 1
             WHERE id = ?1 AND deleted = 0 AND (?2 IS NULL OR from_me = ?2)",
            params![id, from_me],
        )
        .map_err(db)?;
    if n == 0 {
        return Ok(false);
    }
    let path: Option<Option<String>> =
        c.query_row("SELECT path FROM media WHERE message_id = ?1", params![id], |r| r.get(0)).optional().map_err(db)?;
    if let Some(Some(p)) = path {
        let _ = std::fs::remove_file(p);
    }
    c.execute("DELETE FROM media WHERE message_id = ?1", params![id]).map_err(db)?;
    Ok(true)
}

// ------------------------------------------------------------------ petites valeurs du profil (table kv)

fn kv_get(c: &rusqlite::Connection, k: &str) -> R<Option<String>> {
    c.query_row("SELECT v FROM kv WHERE k = ?1", params![k], |r| r.get::<_, Option<String>>(0))
        .optional()
        .map(Option::flatten)
        .map_err(db)
}

fn kv_newer(c: &rusqlite::Connection, k: &str, at: u64) -> R<bool> {
    let cur: Option<i64> = c.query_row("SELECT at FROM kv WHERE k = ?1", params![k], |r| r.get(0)).optional().map_err(db)?;
    Ok(cur.is_none_or(|cur| (at as i64) > cur))
}

fn kv_set(c: &rusqlite::Connection, k: &str, v: Option<&str>, at: u64) -> R<()> {
    c.execute(
        "INSERT INTO kv (k, v, at) VALUES (?1, ?2, ?3) ON CONFLICT (k) DO UPDATE SET v = excluded.v, at = excluded.at",
        params![k, v, at as i64],
    )
    .map_err(db)?;
    Ok(())
}

/// Message et, s'il y en a une, sa photo ou vidéo.
pub(crate) const SELECT: &str = "SELECT m.id, m.from_me, m.body, m.reply_to, m.sent_at, m.status, m.my_reaction, \
    m.their_reaction, md.kind, md.mime, md.width, md.height, md.duration_ms, md.thumb, md.state, m.deleted \
    FROM messages m LEFT JOIN media md ON md.message_id = m.id";

impl Device {
    pub(crate) fn enqueue(&mut self, partner: &str, body: pb::Body, message_id: Option<&str>) -> R<Outgoing> {
        // Accusés, profil, dates, suppressions : rien qui mérite de réveiller le téléphone du partenaire.
        // Une suppression ne réveille pas le téléphone : elle s'appliquera à la prochaine ouverture.
        let urgent = matches!(body, pb::Body::Text(_) | pb::Body::Reaction(_) | pb::Body::Media(_));
        let envelope = self.encrypt(partner, &encode(body))?;
        let envelope_id = uuid_v4();
        self.store
            .conn
            .lock()
            .execute(
                "INSERT INTO outbox (envelope_id, kind, body, message_id, created_at, urgent) VALUES (?1, ?2, ?3, ?4, ?5, ?6)",
                params![envelope_id, envelope.kind as i64, envelope.body, message_id, now_ms(), urgent as i64],
            )
            .map_err(db)?;
        Ok(Outgoing { envelope_id, envelope, urgent })
    }

    /// Chiffre un message texte, l'ajoute à l'historique (« en attente ») et à la boîte d'envoi.
    pub fn send_text(&mut self, partner: &str, body: &str, reply_to: Option<&str>) -> R<(ChatMessage, Outgoing)> {
        let body = body.trim();
        if body.is_empty() || body.len() > MAX_TEXT_BYTES {
            return Err(DeviceError::Protocol("message vide ou trop long".into()));
        }
        let reply_wire = match reply_to {
            Some(r) => Some(unhex(r).filter(|b| b.len() == 16).ok_or(DeviceError::BadMessage)?),
            None => None,
        };
        let id = random16();
        // Heures d'envoi strictement croissantes sur ce téléphone : deux messages envoyés dans la même
        // milliseconde s'affichent toujours dans l'ordre, chez soi comme chez le partenaire.
        let last: Option<i64> = self
            .store
            .conn
            .lock()
            .query_row("SELECT max(sent_at) FROM messages WHERE from_me = 1", [], |r| r.get(0))
            .map_err(db)?;
        let sent_at = now_ms().max(last.map_or(0, |l| l + 1));
        let msg = ChatMessage {
            id: hex(&id),
            from_me: true,
            body: body.to_owned(),
            reply_to: reply_to.map(str::to_owned),
            sent_at,
            status: STATUS_PENDING,
            my_reaction: None,
            their_reaction: None,
            media: None,
            deleted: false,
        };
        let text = pb::Text { id: id.to_vec(), sent_at: sent_at as u64, body: msg.body.clone(), reply_to: reply_wire };
        let tx = self.store.conn.clone();
        let out = tx.atomically(|| {
            self.store
                .conn
                .lock()
                .execute(
                    "INSERT INTO messages (id, from_me, body, reply_to, sent_at, received_at, status) VALUES (?1, 1, ?2, ?3, ?4, ?4, 0)",
                    params![msg.id, msg.body, msg.reply_to, sent_at],
                )
                .map_err(db)?;
            self.enqueue(partner, pb::Body::Text(text), Some(&msg.id))
        })?;
        Ok((msg, out))
    }

    /// Réagit à un message (emoji vide = retirer sa réaction).
    pub fn send_reaction(&mut self, partner: &str, target: &str, emoji: &str) -> R<Outgoing> {
        let wire = unhex(target).filter(|b| b.len() == 16).ok_or(DeviceError::BadMessage)?;
        if emoji.chars().count() > 8 {
            return Err(DeviceError::Protocol("réaction invalide".into()));
        }
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            self.store
                .conn
                .lock()
                .execute(
                    "UPDATE messages SET my_reaction = ?2 WHERE id = ?1 AND deleted = 0",
                    params![target, (!emoji.is_empty()).then_some(emoji)],
                )
                .map_err(db)?;
            self.enqueue(partner, pb::Body::Reaction(pb::Reaction { target: wire, emoji: emoji.to_owned() }), None)
        })
    }

    /// Accusé « distribué » (2) ou « lu » (3) pour des messages reçus. « Lu » les marque aussi lus ici.
    pub fn send_receipt(&mut self, partner: &str, ids: &[String], kind: u8) -> R<Option<Outgoing>> {
        if kind != STATUS_DELIVERED && kind != STATUS_READ {
            return Err(DeviceError::Protocol("accusé invalide".into()));
        }
        let wire: Vec<Vec<u8>> = ids.iter().filter_map(|i| unhex(i).filter(|b| b.len() == 16)).collect();
        if wire.is_empty() {
            return Ok(None);
        }
        let tx = self.store.conn.clone();
        tx
            .atomically(|| {
                if kind == STATUS_READ {
                    let c = self.store.conn.lock();
                    for id in ids {
                        c.execute("UPDATE messages SET status = 3 WHERE id = ?1 AND from_me = 0", params![id]).map_err(db)?;
                    }
                }
                self.enqueue(partner, pb::Body::Receipt(pb::Receipt { kind: kind as u32, ids: wire }), None)
            })
            .map(Some)
    }

    /// Enveloppes encore à déposer, dans l'ordre de création.
    pub fn outbox(&self) -> R<Vec<Outgoing>> {
        let c = self.store.conn.lock();
        let mut st = c.prepare("SELECT envelope_id, kind, body, urgent FROM outbox ORDER BY created_at, rowid").map_err(db)?;
        let rows = st
            .query_map([], |r| {
                Ok(Outgoing {
                    envelope_id: r.get(0)?,
                    envelope: Envelope { kind: r.get::<_, i64>(1)? as u8, body: r.get(2)? },
                    urgent: r.get::<_, i64>(3)? == 1,
                })
            })
            .map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    /// Le serveur a bien reçu l'enveloppe. Renvoie l'identifiant du message passé à « envoyé », s'il y en a un.
    pub fn outbox_sent(&mut self, envelope_id: &str) -> R<Option<String>> {
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let c = self.store.conn.lock();
            let mid: Option<Option<String>> = c
                .query_row("SELECT message_id FROM outbox WHERE envelope_id = ?1", params![envelope_id], |r| r.get(0))
                .optional()
                .map_err(db)?;
            c.execute("DELETE FROM outbox WHERE envelope_id = ?1", params![envelope_id]).map_err(db)?;
            let mid = mid.flatten();
            if let Some(m) = &mid {
                c.execute("UPDATE messages SET status = max(status, 1) WHERE id = ?1 AND from_me = 1", params![m]).map_err(db)?;
            }
            Ok(mid)
        })
    }

    /// Déchiffre et applique une enveloppe reçue, de façon atomique et idempotente.
    pub fn receive(&mut self, partner: &str, envelope_id: &str, envelope: &Envelope) -> R<Received> {
        let seen: bool = self
            .store
            .conn
            .lock()
            .query_row("SELECT 1 FROM seen_envelopes WHERE id = ?1", params![envelope_id], |_| Ok(()))
            .optional()
            .map_err(db)?
            .is_some();
        if seen {
            return Ok(Received::Nothing);
        }
        let tx = self.store.conn.clone();
        let result = tx.atomically(|| {
            let plain = self.decrypt(partner, envelope)?;
            let effect = self.apply(&plain)?;
            self.mark_seen(envelope_id)?;
            Ok::<_, DeviceError>(effect)
        });
        match result {
            Ok(e) => Ok(e),
            // Clé du partenaire changée : on garde l'enveloppe, elle sera lue après une nouvelle vérification.
            // Erreur de la base locale : on réessaiera.
            Err(e @ (DeviceError::PartnerKeyChanged | DeviceError::Store(_))) => Err(e),
            // Altérée, rejouée, pré-clé déjà consommée… : écartée définitivement pour ne pas bloquer la file.
            Err(_) => {
                self.mark_seen(envelope_id)?;
                Ok(Received::Rejected)
            }
        }
    }

    fn mark_seen(&self, envelope_id: &str) -> R<()> {
        self.store
            .conn
            .lock()
            .execute("INSERT OR IGNORE INTO seen_envelopes (id, at) VALUES (?1, ?2)", params![envelope_id, now_ms()])
            .map_err(db)?;
        Ok(())
    }

    fn apply(&mut self, plain: &[u8]) -> R<Received> {
        if plain == LEGACY_HELLO {
            return Ok(Received::Nothing);
        }
        let data = unpad(plain).ok_or(DeviceError::BadMessage)?;
        let (&version, rest) = data.split_first().ok_or(DeviceError::BadMessage)?;
        let content = if version == FORMAT_V1 { pb::Content::decode(rest).ok() } else { None };
        let Some(body) = content.and_then(|c| c.body) else {
            // Contenu authentique (la session l'a vérifié) mais d'une version plus récente de l'app : on le garde,
            // chiffré dans la base locale, pour le relire après la mise à jour (`reprocess_unknown`).
            if version > FORMAT_V1 || (version == FORMAT_V1 && pb::Content::decode(rest).is_ok()) {
                self.store
                    .conn
                    .lock()
                    .execute("INSERT INTO unknown_contents (plain, at) VALUES (?1, ?2)", params![plain, now_ms()])
                    .map_err(db)?;
                return Ok(Received::Nothing);
            }
            return Err(DeviceError::BadMessage);
        };
        let c = self.store.conn.lock();
        match body {
            pb::Body::Text(t) => {
                let id = id_from_wire(&t.id).ok_or(DeviceError::BadMessage)?;
                let body = t.body.trim().to_owned();
                if body.is_empty() || body.len() > MAX_TEXT_BYTES {
                    return Err(DeviceError::BadMessage);
                }
                let reply_to = t.reply_to.as_deref().and_then(id_from_wire);
                let now = now_ms();
                // Une heure d'envoi absurde (horloge déréglée) est remplacée par l'heure de réception.
                let sent_at = i64::try_from(t.sent_at).ok().filter(|s| (now - 30 * 86_400_000..now + 600_000).contains(s)).unwrap_or(now);
                let n = c
                    .execute(
                        "INSERT OR IGNORE INTO messages (id, from_me, body, reply_to, sent_at, received_at, status) VALUES (?1, 0, ?2, ?3, ?4, ?5, 0)",
                        params![id, body, reply_to, sent_at, now],
                    )
                    .map_err(db)?;
                if n == 0 {
                    return Ok(Received::Nothing);
                }
                let m = c
                    .query_row(&format!("{SELECT} WHERE m.id = ?1"), params![id], row_to_message)
                    .map_err(db)?;
                Ok(Received::Message(m))
            }
            pb::Body::Receipt(r) => {
                if r.kind != STATUS_DELIVERED as u32 && r.kind != STATUS_READ as u32 {
                    return Ok(Received::Nothing);
                }
                let mut changed = Vec::new();
                for id in r.ids.iter().filter_map(|b| id_from_wire(b)) {
                    // Le statut ne fait qu'avancer, et seulement pour nos propres messages.
                    let n = c
                        .execute(
                            "UPDATE messages SET status = ?2 WHERE id = ?1 AND from_me = 1 AND status < ?2",
                            params![id, r.kind as i64],
                        )
                        .map_err(db)?;
                    if n > 0 {
                        changed.push(id);
                    }
                }
                Ok(Received::Updated(changed))
            }
            pb::Body::Reaction(r) => {
                let id = id_from_wire(&r.target).ok_or(DeviceError::BadMessage)?;
                if r.emoji.chars().count() > 8 {
                    return Err(DeviceError::BadMessage);
                }
                let n = c
                    .execute(
                        "UPDATE messages SET their_reaction = ?2 WHERE id = ?1 AND deleted = 0",
                        params![id, (!r.emoji.is_empty()).then_some(r.emoji)],
                    )
                    .map_err(db)?;
                Ok(Received::Updated(if n > 0 { vec![id] } else { vec![] }))
            }
            pb::Body::Media(m) => crate::chat_media::apply_media(&c, m),
            pb::Body::Date(d) => crate::dates::apply_date(&c, d),
            pb::Body::Delete(d) => {
                let id = id_from_wire(&d.target).ok_or(DeviceError::BadMessage)?;
                // Le partenaire ne peut retirer que ses propres messages, jamais les nôtres.
                let n = erase(&c, &id, Some(false))?;
                Ok(Received::Updated(if n { vec![id] } else { vec![] }))
            }
            pb::Body::Profile(p) => {
                let Some(name) = clean_name(&p.name) else { return Err(DeviceError::BadMessage) };
                let newer = kv_newer(&c, "partner_name", p.updated_at)?;
                if newer {
                    kv_set(&c, "partner_name", Some(&name), p.updated_at)?;
                }
                Ok(if newer { Received::Profile } else { Received::Nothing })
            }
            pb::Body::Couple(k) => {
                let date = (!k.together_since.is_empty()).then_some(k.together_since.as_str());
                if date.is_some_and(|d| !valid_date(d)) {
                    return Err(DeviceError::BadMessage);
                }
                let newer = kv_newer(&c, "together_since", k.updated_at)?;
                if newer {
                    kv_set(&c, "together_since", date, k.updated_at)?;
                }
                Ok(if newer { Received::Profile } else { Received::Nothing })
            }
        }
    }

    /// Relit les contenus gardés faute d'être compris par une version précédente de l'app.
    /// Renvoie vrai si quelque chose a changé (à appeler au démarrage).
    pub fn reprocess_unknown(&mut self) -> R<bool> {
        let rows: Vec<(i64, Vec<u8>)> = {
            let c = self.store.conn.lock();
            let mut st = c.prepare("SELECT rowid, plain FROM unknown_contents ORDER BY rowid").map_err(db)?;
            st.query_map([], |r| Ok((r.get(0)?, r.get(1)?))).map_err(db)?.collect::<Result<_, _>>().map_err(db)?
        };
        let mut changed = false;
        for (rowid, plain) in rows {
            let tx = self.store.conn.clone();
            let effect = tx.atomically(|| {
                self.store.conn.lock().execute("DELETE FROM unknown_contents WHERE rowid = ?1", params![rowid]).map_err(db)?;
                // Toujours pas compris : `apply` le remet dans la table.
                self.apply(&plain)
            });
            changed |= !matches!(effect, Ok(Received::Nothing) | Err(_));
        }
        Ok(changed)
    }

    /// Profil du couple vu par ce téléphone.
    pub fn profile(&self) -> R<CoupleProfile> {
        let c = self.store.conn.lock();
        Ok(CoupleProfile {
            my_name: kv_get(&c, "my_name")?,
            partner_name: kv_get(&c, "partner_name")?,
            partner_nickname: kv_get(&c, "partner_nickname")?,
            together_since: kv_get(&c, "together_since")?,
        })
    }

    /// Ton prénom : enregistré ici et envoyé, chiffré, au partenaire.
    pub fn set_my_name(&mut self, partner: &str, name: &str) -> R<Outgoing> {
        let name = clean_name(name).ok_or_else(|| DeviceError::Protocol("prénom vide ou trop long".into()))?;
        let at = now_ms() as u64;
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            kv_set(&self.store.conn.lock(), "my_name", Some(&name), at)?;
            self.enqueue(partner, pb::Body::Profile(pb::Profile { name: name.clone(), updated_at: at }), None)
        })
    }

    /// Surnom donné au partenaire : uniquement sur ce téléphone (vide = retirer).
    pub fn set_partner_nickname(&self, nickname: &str) -> R<()> {
        let nick = if nickname.trim().is_empty() {
            None
        } else {
            Some(clean_name(nickname).ok_or_else(|| DeviceError::Protocol("surnom trop long".into()))?)
        };
        kv_set(&self.store.conn.lock(), "partner_nickname", nick.as_deref(), now_ms() as u64)
    }

    /// Date « ensemble depuis » (« AAAA-MM-JJ », vide = retirer), partagée avec le partenaire.
    pub fn set_together_since(&mut self, partner: &str, date: &str) -> R<Outgoing> {
        let date = date.trim();
        if !date.is_empty() && !valid_date(date) {
            return Err(DeviceError::Protocol("date invalide".into()));
        }
        let at = now_ms() as u64;
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            kv_set(&self.store.conn.lock(), "together_since", (!date.is_empty()).then_some(date), at)?;
            self.enqueue(partner, pb::Body::Couple(pb::Couple { together_since: date.to_owned(), updated_at: at }), None)
        })
    }

    /// « Supprimer pour moi » : efface le message de ce téléphone seulement (le sien ou celui du partenaire).
    pub fn delete_for_me(&mut self, id: &str) -> R<bool> {
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let c = self.store.conn.lock();
            // Un envoi pas encore parti est annulé.
            c.execute("DELETE FROM outbox WHERE message_id = ?1", params![id]).map_err(db)?;
            erase(&c, id, None)
        })
    }

    /// « Supprimer pour nous deux » (ses propres messages seulement). Renvoie l'enveloppe à envoyer et, pour une
    /// photo ou vidéo déjà déposée, le nom de l'objet à effacer sur R2.
    pub fn delete_for_both(&mut self, partner: &str, id: &str) -> R<(Outgoing, Option<String>)> {
        let wire = unhex(id).filter(|b| b.len() == 16).ok_or(DeviceError::BadMessage)?;
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let object_key = {
                let c = self.store.conn.lock();
                let mine: Option<i64> =
                    c.query_row("SELECT from_me FROM messages WHERE id = ?1", params![id], |r| r.get(0)).optional().map_err(db)?;
                if mine != Some(1) {
                    return Err(DeviceError::Protocol("on ne peut supprimer pour les deux que ses propres messages".into()));
                }
                let key: Option<Option<String>> = c
                    .query_row("SELECT object_key FROM media WHERE message_id = ?1", params![id], |r| r.get(0))
                    .optional()
                    .map_err(db)?;
                c.execute("DELETE FROM outbox WHERE message_id = ?1", params![id]).map_err(db)?;
                erase(&c, id, Some(true))?;
                key.flatten()
            };
            let out = self.enqueue(partner, pb::Body::Delete(pb::Delete { target: wire }), None)?;
            Ok((out, object_key))
        })
    }

    /// Historique, du plus récent au plus ancien. `before` : (sent_at, id) du dernier message déjà chargé.
    pub fn messages(&self, before: Option<(i64, String)>, limit: u32) -> R<Vec<ChatMessage>> {
        let c = self.store.conn.lock();
        let (sa, id) = before.unwrap_or((i64::MAX, String::new()));
        let mut st = c
            .prepare(&format!(
                "{SELECT} WHERE (m.sent_at, m.id) < (?1, ?2) ORDER BY m.sent_at DESC, m.id DESC LIMIT ?3"
            ))
            .map_err(db)?;
        let rows = st.query_map(params![sa, id, limit.min(500)], row_to_message).map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    pub fn message(&self, id: &str) -> R<Option<ChatMessage>> {
        self.store
            .conn
            .lock()
            .query_row(&format!("{SELECT} WHERE m.id = ?1"), params![id], row_to_message)
            .optional()
            .map_err(db)
    }

    /// Messages reçus pas encore lus.
    pub fn unread(&self) -> R<Vec<String>> {
        let c = self.store.conn.lock();
        let mut st = c.prepare("SELECT id FROM messages WHERE from_me = 0 AND status = 0 ORDER BY sent_at").map_err(db)?;
        let rows = st.query_map([], |r| r.get(0)).map_err(db)?;
        rows.collect::<Result<_, _>>().map_err(db)
    }

    /// Oublie les traces d'enveloppes de plus de 60 jours (le serveur supprime les siennes à la réception).
    pub fn purge_seen(&self) -> R<()> {
        self.store
            .conn
            .lock()
            .execute("DELETE FROM seen_envelopes WHERE at < ?1", params![now_ms() - 60 * 86_400_000])
            .map_err(db)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn remplissage_aller_retour() {
        for n in [0usize, 1, 158, 159, 160, 161, 1000] {
            let v: Vec<u8> = (0..n).map(|i| (i % 251) as u8 + 1).collect();
            let p = pad(v.clone());
            assert_eq!(p.len() % PAD_BLOCK, 0);
            assert!(p.len() > n);
            assert_eq!(unpad(&p).unwrap(), v.as_slice());
        }
        assert!(unpad(&[1, 2, 3, 0, 0]).is_none(), "sans 0x80 final : refusé");
        assert!(unpad(&[0, 0, 0]).is_none());
    }

    #[test]
    fn dates_validees() {
        assert!(valid_date("2022-03-12"));
        assert!(valid_date("2024-02-29"));
        assert!(!valid_date("2023-02-29"), "pas d'année bissextile");
        assert!(!valid_date("2022-13-01"));
        assert!(!valid_date("2022-3-12"));
        assert!(!valid_date("1899-12-31"));
        assert!(!valid_date("abcd-ef-gh"));
    }

    #[test]
    fn uuid_bien_forme() {
        let u = uuid_v4();
        assert_eq!(u.len(), 36);
        assert_eq!(&u[14..15], "4");
        assert!(matches!(&u[19..20], "8" | "9" | "a" | "b"));
    }
}
