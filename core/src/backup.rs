//! Sauvegarde chiffrée et phrase de récupération (`docs/SECURITY.md` §7).
//!
//! - **Phrase de 24 mots** (BIP39, liste française officielle) = 256 bits aléatoires + 8 bits de contrôle.
//!   Elle reste sur le téléphone (coffre du système) et sur le papier de l'utilisateur, jamais ailleurs.
//! - **Clé de chaque sauvegarde** = HKDF-SHA256(phrase, sel aléatoire de 256 bits, « FouLove-backup-v1 »).
//!   Le secret fait déjà 256 bits aléatoires : une dérivation lente (Argon2) n'apporterait rien contre la force
//!   brute, HKDF suffit et chaque sauvegarde a sa propre clé.
//! - **Contenu** : messages, médias (clés des fichiers et noms des objets R2, miniatures), profil, dates.
//!   **Pas** les clés Signal : une phrase volée ne permet pas de lire les échanges futurs. À la restauration, le
//!   téléphone crée une nouvelle identité et le couple revérifie ses 7 symboles.
//! - **Format** : `FLB1 ‖ sel (32) ‖ fichier chiffré STREAM AES-256-GCM` (même construction que les médias,
//!   remplissage Padmé compris) : toute modification ou troncature est détectée.

use bip39::{Language, Mnemonic};
use hkdf::Hkdf;
use prost::Message as _;
use rand::TryRngCore as _;
use rand::rngs::OsRng;
use rusqlite::params;
use sha2::Sha256;

use crate::chat::{R, db};
use crate::device::{Device, DeviceError};
use crate::media;

pub const MAGIC: &[u8; 4] = b"FLB1";
const SALT: usize = 32;

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum BackupError {
    #[error("phrase de récupération invalide (mot inconnu, nombre de mots ou contrôle)")]
    BadPhrase,
    #[error("sauvegarde illisible : mauvaise phrase, ou fichier altéré")]
    Unreadable,
}

impl From<BackupError> for DeviceError {
    fn from(e: BackupError) -> Self {
        DeviceError::Protocol(e.to_string())
    }
}

/// Nouvelle phrase de 24 mots. Renvoie (phrase, secret de 256 bits).
pub fn new_phrase() -> (String, [u8; 32]) {
    let mut entropy = [0u8; 32];
    OsRng.try_fill_bytes(&mut entropy).expect("générateur du système");
    let m = Mnemonic::from_entropy_in(Language::French, &entropy).expect("32 octets : 24 mots");
    (m.to_string(), entropy)
}

/// Mot sans accents ni majuscules (« éléphant » → « elephant »), quelle que soit la forme Unicode tapée.
pub fn plain_word(w: &str) -> String {
    use unicode_normalization::UnicodeNormalization;
    w.nfkd().filter(|c| !('\u{0300}'..='\u{036f}').contains(c)).flat_map(char::to_lowercase).collect()
}

/// Relit une phrase tapée : espaces et majuscules tolérés, et les accents peuvent être omis (les mots de la liste
/// française restent distincts sans eux, vérifié par un test). Le contrôle BIP39 détecte une faute de frappe.
pub fn phrase_to_secret(phrase: &str) -> Result<[u8; 32], BackupError> {
    let list = Language::French.word_list();
    let words: Vec<&'static str> = phrase
        .split_whitespace()
        .map(|w| {
            let p = plain_word(w);
            list.iter().copied().find(|x| plain_word(x) == p).ok_or(BackupError::BadPhrase)
        })
        .collect::<Result<_, _>>()?;
    let m = Mnemonic::parse_in(Language::French, words.join(" ")).map_err(|_| BackupError::BadPhrase)?;
    m.to_entropy().try_into().map_err(|_| BackupError::BadPhrase)
}

/// La phrase correspondant à un secret (pour la réafficher).
pub fn secret_to_phrase(secret: &[u8; 32]) -> String {
    Mnemonic::from_entropy_in(Language::French, secret).expect("32 octets").to_string()
}

fn subkey(secret: &[u8; 32], salt: &[u8]) -> [u8; 32] {
    let mut k = [0u8; 32];
    Hkdf::<Sha256>::new(Some(salt), secret).expand(b"FouLove-backup-v1", &mut k).expect("32 octets : longueur valide");
    k
}

pub mod bpb {
    //! Schéma de la sauvegarde. Ne jamais réutiliser un numéro de champ.

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Backup {
        #[prost(uint32, tag = "1")]
        pub version: u32,
        #[prost(uint64, tag = "2")]
        pub created_at: u64,
        #[prost(message, repeated, tag = "3")]
        pub messages: Vec<Msg>,
        #[prost(message, repeated, tag = "4")]
        pub media: Vec<Media>,
        #[prost(message, repeated, tag = "5")]
        pub kv: Vec<Kv>,
        #[prost(message, repeated, tag = "6")]
        pub dates: Vec<Date>,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Msg {
        #[prost(string, tag = "1")]
        pub id: String,
        #[prost(bool, tag = "2")]
        pub from_me: bool,
        #[prost(string, tag = "3")]
        pub body: String,
        #[prost(string, optional, tag = "4")]
        pub reply_to: Option<String>,
        #[prost(int64, tag = "5")]
        pub sent_at: i64,
        #[prost(int64, tag = "6")]
        pub received_at: i64,
        #[prost(uint32, tag = "7")]
        pub status: u32,
        #[prost(string, optional, tag = "8")]
        pub my_reaction: Option<String>,
        #[prost(string, optional, tag = "9")]
        pub their_reaction: Option<String>,
        #[prost(bool, tag = "10")]
        pub deleted: bool,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Media {
        #[prost(string, tag = "1")]
        pub message_id: String,
        #[prost(uint32, tag = "2")]
        pub kind: u32,
        #[prost(string, tag = "3")]
        pub object_key: String,
        #[prost(bytes = "vec", tag = "4")]
        pub file_key: Vec<u8>,
        #[prost(bytes = "vec", tag = "5")]
        pub sha256: Vec<u8>,
        #[prost(uint64, tag = "6")]
        pub size: u64,
        #[prost(string, tag = "7")]
        pub mime: String,
        #[prost(uint32, tag = "8")]
        pub width: u32,
        #[prost(uint32, tag = "9")]
        pub height: u32,
        #[prost(uint32, tag = "10")]
        pub duration_ms: u32,
        #[prost(bytes = "vec", tag = "11")]
        pub thumb: Vec<u8>,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Kv {
        #[prost(string, tag = "1")]
        pub k: String,
        #[prost(string, optional, tag = "2")]
        pub v: Option<String>,
        #[prost(int64, tag = "3")]
        pub at: i64,
    }

    #[derive(Clone, PartialEq, prost::Message)]
    pub struct Date {
        #[prost(string, tag = "1")]
        pub id: String,
        #[prost(string, tag = "2")]
        pub title: String,
        #[prost(string, tag = "3")]
        pub date: String,
        #[prost(bool, tag = "4")]
        pub yearly: bool,
        #[prost(uint32, optional, tag = "5")]
        pub remind_days: Option<u32>,
        #[prost(int64, tag = "6")]
        pub updated_at: i64,
        #[prost(bool, tag = "7")]
        pub deleted: bool,
    }
}

/// Ce que la restauration a remis en place.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct RestoreSummary {
    pub messages: u32,
    pub media: u32,
    pub dates: u32,
}

impl Device {
    /// Construit la sauvegarde chiffrée (octets à déposer sur R2).
    pub fn export_backup(&self, secret: &[u8; 32]) -> R<Vec<u8>> {
        let b = {
            let c = self.store.conn.lock();
            let mut b = bpb::Backup { version: 1, created_at: crate::chat::now_ms() as u64, ..Default::default() };
            let mut st = c
                .prepare("SELECT id, from_me, body, reply_to, sent_at, received_at, status, my_reaction, their_reaction, deleted FROM messages")
                .map_err(db)?;
            b.messages = st
                .query_map([], |r| {
                    Ok(bpb::Msg {
                        id: r.get(0)?,
                        from_me: r.get::<_, i64>(1)? == 1,
                        body: r.get(2)?,
                        reply_to: r.get(3)?,
                        sent_at: r.get(4)?,
                        received_at: r.get(5)?,
                        status: r.get::<_, i64>(6)? as u32,
                        my_reaction: r.get(7)?,
                        their_reaction: r.get(8)?,
                        deleted: r.get::<_, i64>(9)? == 1,
                    })
                })
                .map_err(db)?
                .collect::<Result<_, _>>()
                .map_err(db)?;
            // Seuls les médias déjà déposés sur R2 peuvent être retrouvés ; les autres restent sans fichier.
            let mut st = c
                .prepare(
                    "SELECT message_id, kind, object_key, file_key, sha256, size, mime, width, height, duration_ms, thumb
                     FROM media WHERE object_key IS NOT NULL AND state != 3",
                )
                .map_err(db)?;
            b.media = st
                .query_map([], |r| {
                    Ok(bpb::Media {
                        message_id: r.get(0)?,
                        kind: r.get::<_, i64>(1)? as u32,
                        object_key: r.get(2)?,
                        file_key: r.get(3)?,
                        sha256: r.get(4)?,
                        size: r.get::<_, i64>(5)? as u64,
                        mime: r.get(6)?,
                        width: r.get::<_, i64>(7)? as u32,
                        height: r.get::<_, i64>(8)? as u32,
                        duration_ms: r.get::<_, i64>(9)? as u32,
                        thumb: r.get(10)?,
                    })
                })
                .map_err(db)?
                .collect::<Result<_, _>>()
                .map_err(db)?;
            let mut st = c.prepare("SELECT k, v, at FROM kv").map_err(db)?;
            b.kv = st
                .query_map([], |r| Ok(bpb::Kv { k: r.get(0)?, v: r.get(1)?, at: r.get(2)? }))
                .map_err(db)?
                .collect::<Result<_, _>>()
                .map_err(db)?;
            let mut st = c.prepare("SELECT id, title, date, yearly, remind_days, updated_at, deleted FROM dates").map_err(db)?;
            b.dates = st
                .query_map([], |r| {
                    Ok(bpb::Date {
                        id: r.get(0)?,
                        title: r.get(1)?,
                        date: r.get(2)?,
                        yearly: r.get(3)?,
                        remind_days: r.get::<_, Option<i64>>(4)?.map(|x| x as u32),
                        updated_at: r.get(5)?,
                        deleted: r.get::<_, i64>(6)? == 1,
                    })
                })
                .map_err(db)?
                .collect::<Result<_, _>>()
                .map_err(db)?;
            b
        };
        let mut salt = [0u8; SALT];
        OsRng.try_fill_bytes(&mut salt).expect("générateur du système");
        let body = media::encrypt_with_key(&subkey(secret, &salt), &b.encode_to_vec()).map_err(|_| BackupError::Unreadable)?;
        let mut out = Vec::with_capacity(MAGIC.len() + SALT + body.len());
        out.extend_from_slice(MAGIC);
        out.extend_from_slice(&salt);
        out.extend_from_slice(&body);
        Ok(out)
    }

    /// Remet en place une sauvegarde sur ce téléphone (sans toucher aux clés Signal, toutes neuves).
    /// Les médias sont marqués « à télécharger » : leurs fichiers chiffrés sont toujours sur R2.
    pub fn import_backup(&mut self, secret: &[u8; 32], data: &[u8]) -> R<RestoreSummary> {
        if data.len() < MAGIC.len() + SALT || &data[..4] != MAGIC {
            return Err(BackupError::Unreadable.into());
        }
        let salt = &data[4..4 + SALT];
        let plain = media::decrypt(&subkey(secret, salt), &data[4 + SALT..]).map_err(|_| BackupError::Unreadable)?;
        let b = bpb::Backup::decode(plain.as_slice()).map_err(|_| BackupError::Unreadable)?;
        if b.version != 1 {
            return Err(BackupError::Unreadable.into());
        }
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let c = self.store.conn.lock();
            let mut sum = RestoreSummary::default();
            for m in &b.messages {
                sum.messages += c
                    .execute(
                        "INSERT OR IGNORE INTO messages (id, from_me, body, reply_to, sent_at, received_at, status, my_reaction,
                           their_reaction, deleted) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                        params![
                            m.id, m.from_me, m.body, m.reply_to, m.sent_at, m.received_at, m.status, m.my_reaction,
                            m.their_reaction, m.deleted
                        ],
                    )
                    .map_err(db)? as u32;
            }
            for m in &b.media {
                sum.media += c
                    .execute(
                        "INSERT OR IGNORE INTO media (message_id, kind, object_key, file_key, sha256, size, mime, width, height,
                           duration_ms, thumb, path, state) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, NULL, 2)",
                        params![
                            m.message_id, m.kind, m.object_key, m.file_key, m.sha256, m.size as i64, m.mime, m.width, m.height,
                            m.duration_ms, m.thumb
                        ],
                    )
                    .map_err(db)? as u32;
            }
            for k in &b.kv {
                c.execute(
                    "INSERT INTO kv (k, v, at) VALUES (?1, ?2, ?3)
                     ON CONFLICT (k) DO UPDATE SET v = excluded.v, at = excluded.at WHERE excluded.at > kv.at",
                    params![k.k, k.v, k.at],
                )
                .map_err(db)?;
            }
            for d in &b.dates {
                sum.dates += c
                    .execute(
                        "INSERT INTO dates (id, title, date, yearly, remind_days, updated_at, deleted) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
                         ON CONFLICT (id) DO UPDATE SET title = excluded.title, date = excluded.date, yearly = excluded.yearly,
                           remind_days = excluded.remind_days, updated_at = excluded.updated_at, deleted = excluded.deleted
                         WHERE excluded.updated_at > dates.updated_at",
                        params![d.id, d.title, d.date, d.yearly, d.remind_days, d.updated_at, d.deleted],
                    )
                    .map_err(db)? as u32;
            }
            Ok(sum)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phrase_de_24_mots_aller_retour() {
        let (p, s) = new_phrase();
        assert_eq!(p.split(' ').count(), 24);
        assert_eq!(phrase_to_secret(&p).unwrap(), s);
        assert_eq!(secret_to_phrase(&s), p);
        // Majuscules et espaces en trop tolérés.
        let messy = format!("  {}  ", p.to_uppercase().replace(' ', "   "));
        assert_eq!(phrase_to_secret(&messy).unwrap(), s);
    }

    #[test]
    fn mots_francais_distincts_sans_accents_et_saisie_sans_accents() {
        let list = Language::French.word_list();
        let mut seen = std::collections::HashSet::new();
        for w in list {
            assert!(seen.insert(plain_word(w)), "« {w} » se confond avec un autre mot sans accents");
        }
        // Une phrase avec des mots accentués, tapée sans accents (et en forme composée « é » unique).
        let (p, s) = new_phrase();
        let typed: String = p.split(' ').map(plain_word).collect::<Vec<_>>().join(" ");
        assert_eq!(phrase_to_secret(&typed).unwrap(), s);
        use unicode_normalization::UnicodeNormalization;
        assert_eq!(phrase_to_secret(&p.nfc().collect::<String>()).unwrap(), s);
    }

    #[test]
    fn phrase_fausse_refusee() {
        let (p, _) = new_phrase();
        let mut w: Vec<&str> = p.split(' ').collect();
        w.swap(0, 1); // mots inversés : le contrôle échoue (presque toujours)
        let swapped = w.join(" ");
        let r = phrase_to_secret(&swapped);
        assert!(r.is_err() || r.unwrap() != phrase_to_secret(&p).unwrap());
        assert_eq!(phrase_to_secret("abeille abeille"), Err(BackupError::BadPhrase), "pas 24 mots");
        assert_eq!(phrase_to_secret(&p.replacen(' ', " xyzzy ", 1)), Err(BackupError::BadPhrase), "mot inconnu");
    }

    #[test]
    fn sous_cles_differentes_par_sel() {
        let s = [7u8; 32];
        assert_ne!(subkey(&s, &[1; 32]), subkey(&s, &[2; 32]));
        assert_eq!(subkey(&s, &[1; 32]), subkey(&s, &[1; 32]));
    }
}
