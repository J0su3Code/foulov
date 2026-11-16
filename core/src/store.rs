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
use std::rc::Rc;

use async_trait::async_trait;
use libsignal_protocol::{
    Direction, GenericSignedPreKey, IdentityChange, IdentityKey, IdentityKeyPair, IdentityKeyStore, KyberPreKeyId,
    KyberPreKeyRecord, KyberPreKeyStore, PreKeyId, PreKeyRecord, PreKeyStore, ProtocolAddress, PublicKey,
    SessionRecord, SessionStore, SignalProtocolError, SignedPreKeyId, SignedPreKeyRecord, SignedPreKeyStore,
};
use rusqlite::{Connection, OptionalExtension, params};

type SResult<T> = Result<T, SignalProtocolError>;

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

const SCHEMA_VERSION: i64 = 1;

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
";

/// Base locale chiffrée et ses magasins libsignal (une poignée par magasin, connexion partagée).
pub struct Store {
    conn: Rc<Connection>,
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
        conn.execute("INSERT OR IGNORE INTO meta (k, v) VALUES ('schema_version', ?1)", params![SCHEMA_VERSION.to_be_bytes().to_vec()])?;
        let conn = Rc::new(conn);
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
        let tx = self.conn.unchecked_transaction()?;
        tx.execute("INSERT INTO meta (k, v) VALUES ('identity', ?1)", params![identity.serialize().to_vec()])?;
        tx.execute("INSERT INTO meta (k, v) VALUES ('registration_id', ?1)", params![registration_id.to_be_bytes().to_vec()])?;
        tx.commit()?;
        Ok(())
    }

    pub fn has_identity(&self) -> Result<bool, StoreError> {
        Ok(self.conn.query_row("SELECT count(*) FROM meta WHERE k = 'identity'", [], |r| r.get::<_, i64>(0))? == 1)
    }

    /// Le couple a comparé les 7 symboles et confirmé qu'ils sont identiques.
    pub fn mark_verified(&self, address: &ProtocolAddress) -> Result<(), StoreError> {
        self.conn.execute("UPDATE identities SET verified = 1 WHERE address = ?1", params![addr_key(address)])?;
        Ok(())
    }

    pub fn is_verified(&self, address: &ProtocolAddress) -> Result<bool, StoreError> {
        let v: Option<i64> = self
            .conn
            .query_row("SELECT verified FROM identities WHERE address = ?1", params![addr_key(address)], |r| r.get(0))
            .optional()?;
        Ok(v == Some(1))
    }

    /// Accepte une nouvelle clé du partenaire (nouveau téléphone), après décision explicite de l'utilisateur.
    /// La nouvelle clé repart « non vérifiée » : il faudra recomparer les symboles.
    pub fn accept_identity_change(&self, address: &ProtocolAddress, identity: &IdentityKey) -> Result<(), StoreError> {
        let tx = self.conn.unchecked_transaction()?;
        tx.execute(
            "INSERT INTO identities (address, identity, verified, first_seen) VALUES (?1, ?2, 0, unixepoch())
             ON CONFLICT (address) DO UPDATE SET identity = excluded.identity, verified = 0",
            params![addr_key(address), identity.serialize().to_vec()],
        )?;
        tx.execute("DELETE FROM sessions WHERE address = ?1", params![addr_key(address)])?;
        tx.commit()?;
        Ok(())
    }

    /// Change la clé de chiffrement de la base (par exemple après restauration).
    pub fn rekey(&self, new_key: &[u8; 32]) -> Result<(), StoreError> {
        let hex: String = new_key.iter().map(|b| format!("{b:02x}")).collect();
        self.conn.execute_batch(&format!("PRAGMA rekey = \"x'{hex}'\";"))?;
        Ok(())
    }
}

// ------------------------------------------------------------------ identité

pub struct IdentityHandle(Rc<Connection>);

impl IdentityHandle {
    fn meta(&self, k: &str) -> SResult<Vec<u8>> {
        self.0
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
                self.0
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
            .0
            .query_row("SELECT identity FROM identities WHERE address = ?1", params![addr_key(address)], |r| r.get(0))
            .optional()
            .map_err(cb("get_identity"))?;
        v.map(|b| IdentityKey::decode(&b)).transpose()
    }
}

// ------------------------------------------------------------------ sessions

pub struct SessionHandle(Rc<Connection>);

#[async_trait(?Send)]
impl SessionStore for SessionHandle {
    async fn load_session(&self, address: &ProtocolAddress) -> SResult<Option<SessionRecord>> {
        let v: Option<Vec<u8>> = self
            .0
            .query_row("SELECT record FROM sessions WHERE address = ?1", params![addr_key(address)], |r| r.get(0))
            .optional()
            .map_err(cb("load_session"))?;
        v.map(|b| SessionRecord::deserialize(&b)).transpose()
    }

    async fn store_session(&mut self, address: &ProtocolAddress, record: &SessionRecord) -> SResult<()> {
        self.0
            .execute(
                "INSERT INTO sessions (address, record) VALUES (?1, ?2) ON CONFLICT (address) DO UPDATE SET record = excluded.record",
                params![addr_key(address), record.serialize()?],
            )
            .map_err(cb("store_session"))?;
        Ok(())
    }
}

// ------------------------------------------------------------------ pré-clés

pub struct PreKeyHandle(Rc<Connection>);

#[async_trait(?Send)]
impl PreKeyStore for PreKeyHandle {
    async fn get_pre_key(&self, id: PreKeyId) -> SResult<PreKeyRecord> {
        let v: Option<Vec<u8>> = self
            .0
            .query_row("SELECT record FROM prekeys WHERE id = ?1", params![u32::from(id)], |r| r.get(0))
            .optional()
            .map_err(cb("get_pre_key"))?;
        PreKeyRecord::deserialize(&v.ok_or(SignalProtocolError::InvalidPreKeyId)?)
    }

    async fn save_pre_key(&mut self, id: PreKeyId, record: &PreKeyRecord) -> SResult<()> {
        self.0
            .execute("INSERT OR REPLACE INTO prekeys (id, record) VALUES (?1, ?2)", params![u32::from(id), record.serialize()?])
            .map_err(cb("save_pre_key"))?;
        Ok(())
    }

    async fn remove_pre_key(&mut self, id: PreKeyId) -> SResult<()> {
        self.0.execute("DELETE FROM prekeys WHERE id = ?1", params![u32::from(id)]).map_err(cb("remove_pre_key"))?;
        Ok(())
    }
}

pub struct SignedPreKeyHandle(Rc<Connection>);

#[async_trait(?Send)]
impl SignedPreKeyStore for SignedPreKeyHandle {
    async fn get_signed_pre_key(&self, id: SignedPreKeyId) -> SResult<SignedPreKeyRecord> {
        let v: Option<Vec<u8>> = self
            .0
            .query_row("SELECT record FROM signed_prekeys WHERE id = ?1", params![u32::from(id)], |r| r.get(0))
            .optional()
            .map_err(cb("get_signed_pre_key"))?;
        SignedPreKeyRecord::deserialize(&v.ok_or(SignalProtocolError::InvalidSignedPreKeyId)?)
    }

    async fn save_signed_pre_key(&mut self, id: SignedPreKeyId, record: &SignedPreKeyRecord) -> SResult<()> {
        self.0
            .execute("INSERT OR REPLACE INTO signed_prekeys (id, record) VALUES (?1, ?2)", params![u32::from(id), record.serialize()?])
            .map_err(cb("save_signed_pre_key"))?;
        Ok(())
    }
}

pub struct KyberPreKeyHandle(Rc<Connection>);

impl KyberPreKeyHandle {
    /// Enregistre une pré-clé ML-KEM en précisant si c'est la clé « de dernier recours » (non supprimée à l'usage).
    pub fn save_with_kind(&self, id: KyberPreKeyId, record: &KyberPreKeyRecord, last_resort: bool) -> SResult<()> {
        self.0
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
            .0
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
            .0
            .query_row("SELECT last_resort FROM kyber_prekeys WHERE id = ?1", params![u32::from(id)], |r| r.get(0))
            .optional()
            .map_err(cb("mark_kyber_pre_key_used"))?;
        match last_resort {
            None => Err(SignalProtocolError::InvalidKyberPreKeyId),
            // Pré-clé à usage unique : supprimée dès qu'elle a servi.
            Some(0) => {
                self.0.execute("DELETE FROM kyber_prekeys WHERE id = ?1", params![u32::from(id)]).map_err(cb("mark_kyber_pre_key_used"))?;
                Ok(())
            }
            // Dernier recours : refuser toute réutilisation de la même combinaison (rejeu).
            Some(_) => {
                let inserted = self
                    .0
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
