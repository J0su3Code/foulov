//! Stockage local chiffré (`docs/SECURITY.md` §7) : base SQLite entièrement chiffrée par SQLCipher.
//!
//! - La clé de 256 bits est fournie par l'app : elle est générée une fois puis protégée par la puce
//!   sécurisée du téléphone (Android Keystore, iOS Keychain / Secure Enclave). Elle n'est jamais écrite en clair.
//! - Toute la base est chiffrée : contenu, index et structure. Sans la clé, le fichier est indiscernable
//!   de données aléatoires (pas même l'en-tête « SQLite format 3 »).
//! - Implémente les magasins de libsignal (identité, sessions, pré-clés) au-dessus de cette base.
//!
//! Règle de confiance des identités : la première clé vue est acceptée ; si elle change ensuite, les
//! messages sont refusés (`UntrustedIdentity`) tant que l'utilisateur n'a pas accepté le changement
//! après une nouvelle vérification des symboles (§5).

use std::path::Path;
use std::sync::{Arc, Mutex, MutexGuard};

use async_trait::async_trait;
use libsignal_protocol::{
    Direction, GenericSignedPreKey, IdentityChange, IdentityKey, IdentityKeyPair, IdentityKeyStore, KyberPreKeyId,
    KyberPreKeyRecord, KyberPreKeyStore, PreKeyId, PreKeyRecord, PreKeyStore, ProtocolAddress, PublicKey,
    SessionRecord, SessionStore, SignalProtocolError, SignedPreKeyId, SignedPreKeyRecord, SignedPreKeyStore,
};
use rusqlite::{Connection, OptionalExtension, params};

type SResult<T> = Result<T, SignalProtocolError>;

/// Connexion SQLCipher partagée entre les magasins, utilisable depuis plusieurs fils (appels venant de Flutter).
#[derive(Clone)]
pub(crate) struct Db(Arc<Mutex<Connection>>);

impl Db {
    pub(crate) fn lock(&self) -> MutexGuard<'_, Connection> {
        // Un fil qui a paniqué ne doit pas rendre la base inutilisable : la connexion reste cohérente
        // (chaque écriture est atomique côté SQLite).
        self.0.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Exécute `f` dans une transaction : tout ou rien (avancée du ratchet + message enregistré, par exemple).
    /// Les magasins libsignal écrivent sur la même connexion, donc dans cette même transaction.
    /// Les appels arrivent un par un (verrou du pont Flutter), il n'y a pas de transactions concurrentes.
    pub(crate) fn atomically<T, E: From<StoreError>>(&self, f: impl FnOnce() -> Result<T, E>) -> Result<T, E> {
        self.lock().execute_batch("BEGIN IMMEDIATE").map_err(StoreError::from)?;
        match f() {
            Ok(v) => match self.lock().execute_batch("COMMIT") {
                Ok(()) => Ok(v),
                Err(e) => {
                    let _ = self.lock().execute_batch("ROLLBACK");
                    Err(StoreError::from(e).into())
                }
            },
            Err(e) => {
                let _ = self.lock().execute_batch("ROLLBACK");
                Err(e)
            }
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum StoreError {
    #[error("clé de la base locale incorrecte ou fichier endommagé")]
    WrongKeyOrCorrupted,
    #[error("SQLCipher n'est pas actif : refus d'ouvrir une base non chiffrée")]
    NotEncrypted,
    #[error("identité locale absente : appeler initialize_identity d'abord")]
    NoIdentity,
    #[error("erreur de la base locale : {0}")]
    Db(String),
}

impl From<rusqlite::Error> for StoreError {
    fn from(e: rusqlite::Error) -> Self {
        StoreError::Db(e.to_string())
    }
}

/// Erreur sans données non « UnwindSafe », transportable dans `SignalProtocolError`.
#[derive(Debug, thiserror::Error)]
#[error("{0}")]
struct CallbackError(String);

fn cb(method: &'static str) -> impl FnOnce(rusqlite::Error) -> SignalProtocolError {
    move |e| SignalProtocolError::for_application_callback(method)(CallbackError(e.to_string()))
}

fn addr_key(a: &ProtocolAddress) -> String {
    format!("{}.{}", a.name(), u32::from(a.device_id()))
}

const SCHEMA_VERSION: i64 = 5;

const SCHEMA: &str = "
CREATE TABLE IF NOT EXISTS meta (k TEXT PRIMARY KEY, v BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS identities (
  address TEXT PRIMARY KEY, identity BLOB NOT NULL,
  verified INTEGER NOT NULL DEFAULT 0, first_seen INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS sessions (address TEXT PRIMARY KEY, record BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS prekeys (id INTEGER PRIMARY KEY, record BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS signed_prekeys (id INTEGER PRIMARY KEY, record BLOB NOT NULL);
CREATE TABLE IF NOT EXISTS kyber_prekeys (id INTEGER PRIMARY KEY, record BLOB NOT NULL, last_resort INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS kyber_base_keys_seen (
  kyber_id INTEGER NOT NULL, signed_id INTEGER NOT NULL, base_key BLOB NOT NULL,
  PRIMARY KEY (kyber_id, signed_id, base_key));
-- Messagerie (version 2). L'historique ne vit que sur le téléphone, dans cette base chiffrée.
-- status : messages envoyés 0 en attente, 1 envoyé, 2 distribué, 3 lu ; messages reçus 0 non lu, 3 lu.
CREATE TABLE IF NOT EXISTS messages (
  id TEXT PRIMARY KEY, from_me INTEGER NOT NULL, body TEXT NOT NULL, reply_to TEXT,
  sent_at INTEGER NOT NULL, received_at INTEGER NOT NULL, status INTEGER NOT NULL,
  my_reaction TEXT, their_reaction TEXT);
CREATE INDEX IF NOT EXISTS messages_order ON messages (sent_at, id);
-- Enveloppes chiffrées pas encore déposées sur le serveur : renvoyées telles quelles, jamais rechiffrées.
CREATE TABLE IF NOT EXISTS outbox (
  envelope_id TEXT PRIMARY KEY, kind INTEGER NOT NULL, body BLOB NOT NULL, message_id TEXT, created_at INTEGER NOT NULL,
  urgent INTEGER NOT NULL DEFAULT 1);
-- Enveloppes déjà traitées : une enveloppe livrée deux fois n'est jamais appliquée deux fois.
CREATE TABLE IF NOT EXISTS seen_envelopes (id TEXT PRIMARY KEY, at INTEGER NOT NULL);
-- Profil du couple (prénoms, surnom, date « ensemble depuis ») : petites valeurs horodatées.
CREATE TABLE IF NOT EXISTS kv (k TEXT PRIMARY KEY, v TEXT, at INTEGER NOT NULL);
-- Contenus authentiques venant d'une version plus récente de l'app : relus après la mise à jour.
CREATE TABLE IF NOT EXISTS unknown_contents (plain BLOB NOT NULL, at INTEGER NOT NULL);
-- Dates importantes du couple ; une suppression garde une trace datée (deleted = 1).
CREATE TABLE IF NOT EXISTS dates (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, date TEXT NOT NULL, yearly INTEGER NOT NULL,
  remind_days INTEGER, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
-- Photos et vidéos. La clé du fichier ne quitte jamais cette base chiffrée ; le fichier lui-même reste chiffré
-- sur le téléphone (`path`) et n'est déchiffré qu'en mémoire, à l'affichage.
-- state : 0 à envoyer, 1 sur ce téléphone, 2 à télécharger, 3 illisible (altéré).
CREATE TABLE IF NOT EXISTS media (
  message_id TEXT PRIMARY KEY, kind INTEGER NOT NULL, object_key TEXT, file_key BLOB NOT NULL,
  sha256 BLOB NOT NULL, size INTEGER NOT NULL, mime TEXT NOT NULL, width INTEGER NOT NULL, height INTEGER NOT NULL,
  duration_ms INTEGER NOT NULL, thumb BLOB NOT NULL, path TEXT, state INTEGER NOT NULL);
-- Notre espace (version 5). Photos du couple : un emplacement (« avatar », « cover », « wallpaper ») → un fichier.
CREATE TABLE IF NOT EXISTS pictures (
  slot TEXT PRIMARY KEY, media_id TEXT, from_me INTEGER NOT NULL, updated_at INTEGER NOT NULL);
-- Instants (24 h). kind : 1 photo, 2 vidéo, 4 texte. seen : vu par moi (les siens) ou par lui (les miens).
CREATE TABLE IF NOT EXISTS moments (
  id TEXT PRIMARY KEY, from_me INTEGER NOT NULL, created_at INTEGER NOT NULL, kind INTEGER NOT NULL,
  text TEXT NOT NULL, style INTEGER NOT NULL, seen INTEGER NOT NULL DEFAULT 0);
-- Albums : la version la plus récente l'emporte, une suppression laisse une trace datée.
CREATE TABLE IF NOT EXISTS albums (
  id TEXT PRIMARY KEY, title TEXT NOT NULL, updated_at INTEGER NOT NULL, deleted INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS album_items (
  album_id TEXT NOT NULL, message_id TEXT NOT NULL, pos INTEGER NOT NULL, PRIMARY KEY (album_id, message_id));
-- Lettres et capsules (open_at : ne s'ouvre pas avant cette heure, en millisecondes).
CREATE TABLE IF NOT EXISTS letters (
  id TEXT PRIMARY KEY, from_me INTEGER NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, sent_at INTEGER NOT NULL,
  open_at INTEGER, read_at INTEGER, starred INTEGER NOT NULL DEFAULT 0);
-- Fichiers chiffrés à retirer de R2 (photo remplacée, instant expiré).
CREATE TABLE IF NOT EXISTS r2_trash (object_key TEXT PRIMARY KEY);
";

/// Mises à niveau des bases créées par une version précédente (CREATE IF NOT EXISTS n'ajoute pas de colonne).
fn migrate(conn: &Connection) -> Result<(), StoreError> {
    let has_urgent: bool = conn
        .prepare("SELECT 1 FROM pragma_table_info('outbox') WHERE name = 'urgent'")?
        .exists([])?;
    if !has_urgent {
        // Version 3 : les accusés de réception ne réveillent pas le téléphone du partenaire.
        conn.execute_batch("ALTER TABLE outbox ADD COLUMN urgent INTEGER NOT NULL DEFAULT 1")?;
    }
    let has_deleted: bool = conn
        .prepare("SELECT 1 FROM pragma_table_info('messages') WHERE name = 'deleted'")?
        .exists([])?;
    if !has_deleted {
        // Version 4 : messages supprimés (pour soi ou pour les deux) : il ne reste qu'une trace « supprimé ».
        conn.execute_batch("ALTER TABLE messages ADD COLUMN deleted INTEGER NOT NULL DEFAULT 0")?;
    }
    // Version 5 : à quoi sert un fichier (0 message, 1 photo du couple, 2 instant) ; citation d'un instant.
    let has_purpose: bool = conn.prepare("SELECT 1 FROM pragma_table_info('media') WHERE name = 'purpose'")?.exists([])?;
    if !has_purpose {
        conn.execute_batch("ALTER TABLE media ADD COLUMN purpose INTEGER NOT NULL DEFAULT 0")?;
    }
    let has_quote: bool = conn.prepare("SELECT 1 FROM pragma_table_info('messages') WHERE name = 'quote_text'")?.exists([])?;
    if !has_quote {
        conn.execute_batch("ALTER TABLE messages ADD COLUMN quote_text TEXT; ALTER TABLE messages ADD COLUMN quote_thumb BLOB;")?;
    }
    Ok(())
}

/// Base locale chiffrée et ses magasins libsignal (une poignée par magasin, connexion partagée).
pub struct Store {
    pub(crate) conn: Db,
    pub identity: IdentityHandle,
    pub sessions: SessionHandle,
    pub prekeys: PreKeyHandle,
    pub signed_prekeys: SignedPreKeyHandle,
    pub kyber_prekeys: KyberPreKeyHandle,
}

impl Store {
    /// Ouvre (ou crée) la base chiffrée. Échoue si la clé est fausse ou si SQLCipher n'est pas actif.
    pub fn open(path: &Path, key: &[u8; 32]) -> Result<Self, StoreError> {
        Self::with_connection(Connection::open(path)?, key)
    }

    fn with_connection(conn: Connection, key: &[u8; 32]) -> Result<Self, StoreError> {
        let hex: String = key.iter().map(|b| format!("{b:02x}")).collect();
        // La clé brute (256 bits) est passée directement : pas de dérivation PBKDF2 inutile.
        conn.execute_batch(&format!("PRAGMA key = \"x'{hex}'\";"))?;
        let cipher: Option<String> = conn.query_row("PRAGMA cipher_version", [], |r| r.get(0)).optional()?;
        if cipher.unwrap_or_default().is_empty() {
            return Err(StoreError::NotEncrypted);
        }
        // Lecture de contrôle : avec une mauvaise clé, SQLCipher échoue ici.
        conn.query_row("SELECT count(*) FROM sqlite_master", [], |r| r.get::<_, i64>(0))
            .map_err(|_| StoreError::WrongKeyOrCorrupted)?;
        conn.execute_batch(
            "PRAGMA cipher_memory_security = ON; PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA secure_delete = ON;",
        )?;
        conn.execute_batch(SCHEMA)?;
        migrate(&conn)?;
        conn.execute(
            "INSERT INTO meta (k, v) VALUES ('schema_version', ?1) ON CONFLICT (k) DO UPDATE SET v = excluded.v",
            params![SCHEMA_VERSION.to_be_bytes().to_vec()],
        )?;
        let conn = Db(Arc::new(Mutex::new(conn)));
        Ok(Store {
            identity: IdentityHandle(conn.clone()),
            sessions: SessionHandle(conn.clone()),
            prekeys: PreKeyHandle(conn.clone()),
            signed_prekeys: SignedPreKeyHandle(conn.clone()),
            kyber_prekeys: KyberPreKeyHandle(conn.clone()),
            conn,
        })
    }

    /// Enregistre l'identité de ce téléphone (première ouverture uniquement).
    pub fn initialize_identity(&self, identity: &IdentityKeyPair, registration_id: u32) -> Result<(), StoreError> {
        let guard = self.conn.lock();
        let tx = guard.unchecked_transaction()?;
        tx.execute("INSERT INTO meta (k, v) VALUES ('identity', ?1)", params![identity.serialize().to_vec()])?;
        tx.execute("INSERT INTO meta (k, v) VALUES ('registration_id', ?1)", params![registration_id.to_be_bytes().to_vec()])?;
        tx.commit()?;
        Ok(())
    }

    pub fn has_identity(&self) -> Result<bool, StoreError> {
        Ok(self.conn.lock().query_row("SELECT count(*) FROM meta WHERE k = 'identity'", [], |r| r.get::<_, i64>(0))? == 1)
    }

    /// Le couple a comparé les 7 symboles et confirmé qu'ils sont identiques.
    pub fn mark_verified(&self, address: &ProtocolAddress) -> Result<(), StoreError> {
        self.conn.lock().execute("UPDATE identities SET verified = 1 WHERE address = ?1", params![addr_key(address)])?;
        Ok(())
    }

    pub fn is_verified(&self, address: &ProtocolAddress) -> Result<bool, StoreError> {
        let v: Option<i64> = self
            .conn.lock()
            .query_row("SELECT verified FROM identities WHERE address = ?1", params![addr_key(address)], |r| r.get(0))
            .optional()?;
        Ok(v == Some(1))
    }

    /// Accepte une nouvelle clé du partenaire (nouveau téléphone), après décision explicite de l'utilisateur.
    /// La nouvelle clé repart « non vérifiée » : il faudra recomparer les symboles.
    pub fn accept_identity_change(&self, address: &ProtocolAddress, identity: &IdentityKey) -> Result<(), StoreError> {
        let guard = self.conn.lock();
        let tx = guard.unchecked_transaction()?;
        tx.execute(
            "INSERT INTO identities (address, identity, verified, first_seen) VALUES (?1, ?2, 0, unixepoch())
             ON CONFLICT (address) DO UPDATE SET identity = excluded.identity, verified = 0",
            params![addr_key(address), identity.serialize().to_vec()],
        )?;
        tx.execute("DELETE FROM sessions WHERE address = ?1", params![addr_key(address)])?;
        tx.commit()?;
        Ok(())
    }

    /// Compteur persistant (identifiants de pré-clés). Renvoie la valeur courante puis l'incrémente de `n`.
    pub(crate) fn next_counter(&self, name: &str, n: u32) -> Result<u32, StoreError> {
        let guard = self.conn.lock();
        let tx = guard.unchecked_transaction()?;
        let cur: Option<Vec<u8>> = tx.query_row("SELECT v FROM meta WHERE k = ?1", params![name], |r| r.get(0)).optional()?;
        let start = cur.and_then(|b| b.try_into().ok()).map(u32::from_be_bytes).unwrap_or(1);
        let next = start.checked_add(n).ok_or_else(|| StoreError::Db("compteur saturé".into()))?;
        tx.execute("INSERT OR REPLACE INTO meta (k, v) VALUES (?1, ?2)", params![name, next.to_be_bytes().to_vec()])?;
        tx.commit()?;
        Ok(start)
    }

    /// Change la clé de chiffrement de la base (par exemple après restauration).
    pub fn rekey(&self, new_key: &[u8; 32]) -> Result<(), StoreError> {
        let hex: String = new_key.iter().map(|b| format!("{b:02x}")).collect();
        self.conn.lock().execute_batch(&format!("PRAGMA rekey = \"x'{hex}'\";"))?;
        Ok(())
    }
}

// ------------------------------------------------------------------ identité

pub struct IdentityHandle(Db);

impl IdentityHandle {
    fn meta(&self, k: &str) -> SResult<Vec<u8>> {
        self.0.lock()
            .query_row("SELECT v FROM meta WHERE k = ?1", params![k], |r| r.get(0))
            .optional()
            .map_err(cb("get_identity_key_pair"))?
            .ok_or_else(|| SignalProtocolError::InvalidState("store", "identité locale absente".into()))
    }
}

#[async_trait(?Send)]
impl IdentityKeyStore for IdentityHandle {
    async fn get_identity_key_pair(&self) -> SResult<IdentityKeyPair> {
        IdentityKeyPair::try_from(self.meta("identity")?.as_slice())
    }

    async fn get_local_registration_id(&self) -> SResult<u32> {
        let v = self.meta("registration_id")?;
        let b: [u8; 4] = v.try_into().map_err(|_| SignalProtocolError::InvalidState("store", "registration_id".into()))?;
        Ok(u32::from_be_bytes(b))
    }

    async fn save_identity(&mut self, address: &ProtocolAddress, identity: &IdentityKey) -> SResult<IdentityChange> {
        let existing = self.get_identity(address).await?;
        match existing {
            Some(k) if &k == identity => Ok(IdentityChange::NewOrUnchanged),
            // Clé différente : on ne remplace jamais silencieusement (voir accept_identity_change).
            Some(_) => Err(SignalProtocolError::UntrustedIdentity(address.clone())),
            None => {
                self.0.lock()
                    .execute(
                        "INSERT INTO identities (address, identity, verified, first_seen) VALUES (?1, ?2, 0, unixepoch())",
                        params![addr_key(address), identity.serialize().to_vec()],
                    )
                    .map_err(cb("save_identity"))?;
                Ok(IdentityChange::NewOrUnchanged)
            }
        }
    }

    async fn is_trusted_identity(&self, address: &ProtocolAddress, identity: &IdentityKey, _direction: Direction) -> SResult<bool> {
        Ok(match self.get_identity(address).await? {
            None => true, // première rencontre
            Some(k) => &k == identity,
        })
    }

    async fn get_identity(&self, address: &ProtocolAddress) -> SResult<Option<IdentityKey>> {
        let v: Option<Vec<u8>> = self
            .0.lock()
            .query_row("SELECT identity FROM identities WHERE address = ?1", params![addr_key(address)], |r| r.get(0))
            .optional()
            .map_err(cb("get_identity"))?;
        v.map(|b| IdentityKey::decode(&b)).transpose()
    }
}

// ------------------------------------------------------------------ sessions

pub struct SessionHandle(Db);

#[async_trait(?Send)]
impl SessionStore for SessionHandle {
    async fn load_session(&self, address: &ProtocolAddress) -> SResult<Option<SessionRecord>> {
        let v: Option<Vec<u8>> = self
            .0.lock()
            .query_row("SELECT record FROM sessions WHERE address = ?1", params![addr_key(address)], |r| r.get(0))
            .optional()
            .map_err(cb("load_session"))?;
        v.map(|b| SessionRecord::deserialize(&b)).transpose()
    }

    async fn store_session(&mut self, address: &ProtocolAddress, record: &SessionRecord) -> SResult<()> {
        self.0.lock()
            .execute(
                "INSERT INTO sessions (address, record) VALUES (?1, ?2) ON CONFLICT (address) DO UPDATE SET record = excluded.record",
                params![addr_key(address), record.serialize()?],
            )
            .map_err(cb("store_session"))?;
        Ok(())
    }
}

// ------------------------------------------------------------------ pré-clés

pub struct PreKeyHandle(Db);

#[async_trait(?Send)]
impl PreKeyStore for PreKeyHandle {
    async fn get_pre_key(&self, id: PreKeyId) -> SResult<PreKeyRecord> {
        let v: Option<Vec<u8>> = self
            .0.lock()
            .query_row("SELECT record FROM prekeys WHERE id = ?1", params![u32::from(id)], |r| r.get(0))
            .optional()
            .map_err(cb("get_pre_key"))?;
        PreKeyRecord::deserialize(&v.ok_or(SignalProtocolError::InvalidPreKeyId)?)
    }

    async fn save_pre_key(&mut self, id: PreKeyId, record: &PreKeyRecord) -> SResult<()> {
        self.0.lock()
            .execute("INSERT OR REPLACE INTO prekeys (id, record) VALUES (?1, ?2)", params![u32::from(id), record.serialize()?])
            .map_err(cb("save_pre_key"))?;
        Ok(())
    }

    async fn remove_pre_key(&mut self, id: PreKeyId) -> SResult<()> {
        self.0.lock().execute("DELETE FROM prekeys WHERE id = ?1", params![u32::from(id)]).map_err(cb("remove_pre_key"))?;
        Ok(())
    }
}

pub struct SignedPreKeyHandle(Db);

#[async_trait(?Send)]
impl SignedPreKeyStore for SignedPreKeyHandle {
    async fn get_signed_pre_key(&self, id: SignedPreKeyId) -> SResult<SignedPreKeyRecord> {
        let v: Option<Vec<u8>> = self
            .0.lock()
            .query_row("SELECT record FROM signed_prekeys WHERE id = ?1", params![u32::from(id)], |r| r.get(0))
            .optional()
            .map_err(cb("get_signed_pre_key"))?;
        SignedPreKeyRecord::deserialize(&v.ok_or(SignalProtocolError::InvalidSignedPreKeyId)?)
    }

    async fn save_signed_pre_key(&mut self, id: SignedPreKeyId, record: &SignedPreKeyRecord) -> SResult<()> {
        self.0.lock()
            .execute("INSERT OR REPLACE INTO signed_prekeys (id, record) VALUES (?1, ?2)", params![u32::from(id), record.serialize()?])
            .map_err(cb("save_signed_pre_key"))?;
        Ok(())
    }
}

pub struct KyberPreKeyHandle(Db);

impl KyberPreKeyHandle {
    /// Enregistre une pré-clé ML-KEM en précisant si c'est la clé « de dernier recours » (non supprimée à l'usage).
    pub fn save_with_kind(&self, id: KyberPreKeyId, record: &KyberPreKeyRecord, last_resort: bool) -> SResult<()> {
        self.0.lock()
            .execute(
                "INSERT OR REPLACE INTO kyber_prekeys (id, record, last_resort) VALUES (?1, ?2, ?3)",
                params![u32::from(id), record.serialize()?, last_resort as i64],
            )
            .map_err(cb("save_kyber_pre_key"))?;
        Ok(())
    }
}

#[async_trait(?Send)]
impl KyberPreKeyStore for KyberPreKeyHandle {
    async fn get_kyber_pre_key(&self, id: KyberPreKeyId) -> SResult<KyberPreKeyRecord> {
        let v: Option<Vec<u8>> = self
            .0.lock()
            .query_row("SELECT record FROM kyber_prekeys WHERE id = ?1", params![u32::from(id)], |r| r.get(0))
            .optional()
            .map_err(cb("get_kyber_pre_key"))?;
        KyberPreKeyRecord::deserialize(&v.ok_or(SignalProtocolError::InvalidKyberPreKeyId)?)
    }

    async fn save_kyber_pre_key(&mut self, id: KyberPreKeyId, record: &KyberPreKeyRecord) -> SResult<()> {
        // Par défaut, une pré-clé ML-KEM publiée seule sert de dernier recours.
        self.save_with_kind(id, record, true)
    }

    async fn mark_kyber_pre_key_used(&mut self, id: KyberPreKeyId, ec_id: SignedPreKeyId, base_key: &PublicKey) -> SResult<()> {
        let last_resort: Option<i64> = self
            .0.lock()
            .query_row("SELECT last_resort FROM kyber_prekeys WHERE id = ?1", params![u32::from(id)], |r| r.get(0))
            .optional()
            .map_err(cb("mark_kyber_pre_key_used"))?;
        match last_resort {
            None => Err(SignalProtocolError::InvalidKyberPreKeyId),
            // Pré-clé à usage unique : supprimée dès qu'elle a servi.
            Some(0) => {
                self.0.lock().execute("DELETE FROM kyber_prekeys WHERE id = ?1", params![u32::from(id)]).map_err(cb("mark_kyber_pre_key_used"))?;
                Ok(())
            }
            // Dernier recours : refuser toute réutilisation de la même combinaison (rejeu).
            Some(_) => {
                let inserted = self
                    .0.lock()
                    .execute(
                        "INSERT OR IGNORE INTO kyber_base_keys_seen (kyber_id, signed_id, base_key) VALUES (?1, ?2, ?3)",
                        params![u32::from(id), u32::from(ec_id), base_key.serialize().to_vec()],
                    )
                    .map_err(cb("mark_kyber_pre_key_used"))?;
                if inserted == 0 {
                    return Err(SignalProtocolError::InvalidMessage(
                        libsignal_protocol::CiphertextMessageType::PreKey,
                        "reused base key".to_owned(),
                    ));
                }
                Ok(())
            }
        }
    }
}

// Utilisé par les tests et par la génération des pré-clés.
#[allow(dead_code)]
fn _assert_traits() {
    fn signed<T: GenericSignedPreKey>() {}
    signed::<SignedPreKeyRecord>();
    signed::<KyberPreKeyRecord>();
}
