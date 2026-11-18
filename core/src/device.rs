//! Le téléphone et ses clés : interface de haut niveau utilisée par l'app.
//!
//! Toute la logique cryptographique de l'appairage et des messages passe par ici, pour être testée en Rust
//! et identique sur Android et iOS. L'app ne manipule que des octets opaques.

use std::path::Path;
use std::time::SystemTime;

use futures_util::FutureExt;
use libsignal_protocol::{
    CiphertextMessage, CiphertextMessageType, DeviceId, GenericSignedPreKey, IdentityKey, IdentityKeyPair, IdentityKeyStore, KeyPair,
    KyberPreKeyRecord, PreKeyBundle, PreKeyRecord, PreKeySignalMessage, PreKeyStore, ProtocolAddress, PublicKey,
    SignalMessage, SignalProtocolError, SignedPreKeyRecord, SignedPreKeyStore, Timestamp, kem, message_decrypt,
    message_encrypt, initiate_session,
};
use rand::rngs::OsRng;
use rand::{Rng, TryRngCore as _};
use sha2::{Digest, Sha256};

use crate::sas::{self, Symbol};
use crate::store::{Store, StoreError};

/// Version 1 : un seul téléphone par personne.
const DEVICE_ID: u32 = 1;

#[derive(Debug, thiserror::Error)]
pub enum DeviceError {
    #[error(transparent)]
    Store(#[from] StoreError),
    #[error("la clé de ton partenaire a changé : vérifiez de nouveau vos symboles")]
    PartnerKeyChanged,
    #[error("message illisible ou altéré")]
    BadMessage,
    #[error("clés du partenaire invalides (signature incorrecte)")]
    BadBundle,
    #[error("erreur du protocole : {0}")]
    Protocol(String),
}

impl From<SignalProtocolError> for DeviceError {
    fn from(e: SignalProtocolError) -> Self {
        match e {
            SignalProtocolError::UntrustedIdentity(_) => DeviceError::PartnerKeyChanged,
            SignalProtocolError::SignatureValidationFailed => DeviceError::BadBundle,
            SignalProtocolError::InvalidMessage(..)
            | SignalProtocolError::InvalidProtobufEncoding
            | SignalProtocolError::DuplicatedMessage(..) => DeviceError::BadMessage,
            other => DeviceError::Protocol(other.to_string()),
        }
    }
}

type R<T> = Result<T, DeviceError>;

fn bad<E>(_: E) -> DeviceError {
    DeviceError::BadBundle
}

fn sig_err<E: std::fmt::Display>(e: E) -> DeviceError {
    DeviceError::Protocol(format!("signature : {e}"))
}

/// Pré-clé à usage unique publiée sur le serveur.
#[derive(Clone, Debug)]
pub struct OneTimePreKey {
    pub id: u32,
    pub public_key: Vec<u8>,
}

/// Clés publiques à publier sur le serveur (table `devices` et `one_time_prekeys`).
#[derive(Clone, Debug)]
pub struct LocalBundle {
    pub registration_id: u32,
    pub device_id: u32,
    pub identity_key: Vec<u8>,
    pub signed_prekey_id: u32,
    pub signed_prekey: Vec<u8>,
    pub signed_prekey_sig: Vec<u8>,
    pub kyber_prekey_id: u32,
    pub kyber_prekey: Vec<u8>,
    pub kyber_prekey_sig: Vec<u8>,
    pub one_time_prekeys: Vec<OneTimePreKey>,
}

/// Clés publiques du partenaire, telles que renvoyées par `claim_partner_bundle`.
#[derive(Clone, Debug)]
pub struct PartnerBundle {
    pub registration_id: u32,
    pub device_id: u32,
    pub identity_key: Vec<u8>,
    pub signed_prekey_id: u32,
    pub signed_prekey: Vec<u8>,
    pub signed_prekey_sig: Vec<u8>,
    pub kyber_prekey_id: u32,
    pub kyber_prekey: Vec<u8>,
    pub kyber_prekey_sig: Vec<u8>,
    pub one_time_prekey: Option<OneTimePreKey>,
}

/// Message chiffré prêt à être déposé dans la table `envelopes`.
#[derive(Clone, Debug)]
pub struct Envelope {
    /// 3 = premier message (PreKeySignalMessage), 2 = message suivant (SignalMessage).
    pub kind: u8,
    pub body: Vec<u8>,
}

pub struct Device {
    pub(crate) store: Store,
}

fn addr(partner: &str) -> ProtocolAddress {
    ProtocolAddress::new(partner.to_owned(), DeviceId::new(DEVICE_ID as u8).expect("1 est valide"))
}

/// Empreinte de la clé d'identité, intégrée au QR code d'invitation.
pub fn identity_fingerprint(identity_key: &[u8]) -> [u8; 32] {
    let mut h = Sha256::new();
    h.update(b"FouLov-ID-v1");
    h.update(identity_key);
    h.finalize().into()
}

impl Device {
    /// Ouvre la base chiffrée du téléphone ; crée l'identité à la première ouverture.
    pub fn open(path: &Path, db_key: &[u8; 32]) -> R<Self> {
        let store = Store::open(path, db_key)?;
        if !store.has_identity()? {
            let mut rng = OsRng.unwrap_err();
            let identity = IdentityKeyPair::generate(&mut rng);
            let registration_id = rng.random_range(1..=16380);
            store.initialize_identity(&identity, registration_id)?;
        }
        Ok(Device { store })
    }

    pub fn identity_key(&self) -> R<Vec<u8>> {
        let id = self.store.identity.get_identity_key_pair().now_or_never().expect("synchrone")?;
        Ok(id.identity_key().serialize().to_vec())
    }

    pub fn fingerprint(&self) -> R<[u8; 32]> {
        Ok(identity_fingerprint(&self.identity_key()?))
    }

    /// Génère et conserve de nouvelles clés (pré-clé signée, pré-clé ML-KEM de dernier recours et
    /// `one_time` pré-clés à usage unique), puis renvoie leur partie publique à publier.
    pub fn generate_bundle(&mut self, one_time: u32) -> R<LocalBundle> {
        async {
            let mut rng = OsRng.unwrap_err();
            let id = self.store.identity.get_identity_key_pair().await?;
            let reg = self.store.identity.get_local_registration_id().await?;
            let now = Timestamp::from_epoch_millis(SystemTime::now().duration_since(SystemTime::UNIX_EPOCH).unwrap().as_millis() as u64);

            let signed_id = self.store.next_counter("next_signed_prekey_id", 1)?;
            let signed = KeyPair::generate(&mut rng);
            let signed_sig = id.private_key().calculate_signature(&signed.public_key.serialize(), &mut rng).map_err(sig_err)?;
            self.store
                .signed_prekeys
                .save_signed_pre_key(signed_id.into(), &SignedPreKeyRecord::new(signed_id.into(), now, &signed, &signed_sig))
                .await?;

            let kyber_id = self.store.next_counter("next_kyber_prekey_id", 1)?;
            let kyber = kem::KeyPair::generate(kem::KeyType::Kyber1024, &mut rng);
            let kyber_sig = id.private_key().calculate_signature(&kyber.public_key.serialize(), &mut rng).map_err(sig_err)?;
            self.store
                .kyber_prekeys
                .save_with_kind(kyber_id.into(), &KyberPreKeyRecord::new(kyber_id.into(), now, &kyber, &kyber_sig), true)?;

            let first = self.store.next_counter("next_prekey_id", one_time)?;
            let mut one_time_prekeys = Vec::with_capacity(one_time as usize);
            for pid in first..first + one_time {
                let kp = KeyPair::generate(&mut rng);
                self.store.prekeys.save_pre_key(pid.into(), &PreKeyRecord::new(pid.into(), &kp)).await?;
                one_time_prekeys.push(OneTimePreKey { id: pid, public_key: kp.public_key.serialize().to_vec() });
            }

            Ok(LocalBundle {
                registration_id: reg,
                device_id: DEVICE_ID,
                identity_key: id.identity_key().serialize().to_vec(),
                signed_prekey_id: signed_id,
                signed_prekey: signed.public_key.serialize().to_vec(),
                signed_prekey_sig: signed_sig.to_vec(),
                kyber_prekey_id: kyber_id,
                kyber_prekey: kyber.public_key.serialize().to_vec(),
                kyber_prekey_sig: kyber_sig.to_vec(),
                one_time_prekeys,
            })
        }
        .now_or_never()
        .expect("magasins synchrones")
    }

    /// Ouvre la session avec le partenaire à partir de ses clés publiques.
    /// libsignal vérifie les signatures : une clé substituée sans la clé privée d'identité est refusée.
    pub fn start_session(&mut self, partner: &str, b: &PartnerBundle) -> R<()> {
        let bundle = PreKeyBundle::new(
            b.registration_id,
            DeviceId::new(b.device_id as u8).map_err(|_| DeviceError::BadBundle)?,
            match &b.one_time_prekey {
                Some(k) => Some((k.id.into(), PublicKey::deserialize(&k.public_key).map_err(bad)?)),
                None => None,
            },
            b.signed_prekey_id.into(),
            PublicKey::deserialize(&b.signed_prekey).map_err(bad)?,
            b.signed_prekey_sig.clone(),
            b.kyber_prekey_id.into(),
            kem::PublicKey::deserialize(&b.kyber_prekey).map_err(bad)?,
            b.kyber_prekey_sig.clone(),
            IdentityKey::decode(&b.identity_key).map_err(bad)?,
        )?;
        let mut rng = OsRng.unwrap_err();
        initiate_session(
            &addr(partner),
            &addr("moi"),
            &mut self.store.sessions,
            &mut self.store.identity,
            &bundle,
            SystemTime::now(),
            &mut rng,
        )
        .now_or_never()
        .expect("synchrone")?;
        Ok(())
    }

    pub fn has_session(&self, partner: &str) -> R<bool> {
        use libsignal_protocol::SessionStore;
        Ok(self.store.sessions.load_session(&addr(partner)).now_or_never().expect("synchrone")?.is_some())
    }

    pub fn encrypt(&mut self, partner: &str, plaintext: &[u8]) -> R<Envelope> {
        let mut rng = OsRng.unwrap_err();
        let me = addr("moi");
        let c = message_encrypt(plaintext, &addr(partner), &me, &mut self.store.sessions, &mut self.store.identity, SystemTime::now(), &mut rng)
            .now_or_never()
            .expect("synchrone")?;
        let kind = match c.message_type() {
            CiphertextMessageType::PreKey => 3,
            CiphertextMessageType::Whisper => 2,
            _ => return Err(DeviceError::Protocol("type de message inattendu".into())),
        };
        Ok(Envelope { kind, body: c.serialize().to_vec() })
    }

    pub fn decrypt(&mut self, partner: &str, env: &Envelope) -> R<Vec<u8>> {
        let msg = match env.kind {
            3 => CiphertextMessage::PreKeySignalMessage(PreKeySignalMessage::try_from(env.body.as_slice()).map_err(|_| DeviceError::BadMessage)?),
            2 => CiphertextMessage::SignalMessage(SignalMessage::try_from(env.body.as_slice()).map_err(|_| DeviceError::BadMessage)?),
            _ => return Err(DeviceError::BadMessage),
        };
        let mut rng = OsRng.unwrap_err();
        let me = addr("moi");
        let s = &mut self.store;
        Ok(message_decrypt(
            &msg,
            &addr(partner),
            &me,
            &mut s.sessions,
            &mut s.identity,
            &mut s.prekeys,
            &s.signed_prekeys,
            &mut s.kyber_prekeys,
            &mut rng,
        )
        .now_or_never()
        .expect("synchrone")?)
    }

    /// Les 7 symboles à comparer avec le partenaire.
    pub fn sas_with(&self, partner_identity: &[u8]) -> R<[Symbol; sas::SAS_LEN]> {
        Ok(sas::sas_symbols(&self.identity_key()?, partner_identity))
    }

    pub fn mark_verified(&self, partner: &str) -> R<()> {
        Ok(self.store.mark_verified(&addr(partner))?)
    }

    pub fn is_verified(&self, partner: &str) -> R<bool> {
        Ok(self.store.is_verified(&addr(partner))?)
    }

    /// Clé d'identité du partenaire en laquelle ce téléphone a confiance (la première vue, ou celle acceptée
    /// après une nouvelle vérification). Si le serveur en publie une autre, le partenaire a changé de téléphone.
    pub fn trusted_identity(&self, partner: &str) -> R<Option<Vec<u8>>> {
        let k = self.store.identity.get_identity(&addr(partner)).now_or_never().expect("synchrone")?;
        Ok(k.map(|k| k.serialize().to_vec()))
    }

    /// Accepte une nouvelle clé du partenaire après une nouvelle vérification des symboles.
    pub fn accept_partner_key(&self, partner: &str, identity_key: &[u8]) -> R<()> {
        let k = IdentityKey::decode(identity_key).map_err(|_| DeviceError::BadBundle)?;
        Ok(self.store.accept_identity_change(&addr(partner), &k)?)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn partner_view(b: &LocalBundle, take_one_time: bool) -> PartnerBundle {
        PartnerBundle {
            registration_id: b.registration_id,
            device_id: b.device_id,
            identity_key: b.identity_key.clone(),
            signed_prekey_id: b.signed_prekey_id,
            signed_prekey: b.signed_prekey.clone(),
            signed_prekey_sig: b.signed_prekey_sig.clone(),
            kyber_prekey_id: b.kyber_prekey_id,
            kyber_prekey: b.kyber_prekey.clone(),
            kyber_prekey_sig: b.kyber_prekey_sig.clone(),
            one_time_prekey: take_one_time.then(|| b.one_time_prekeys[0].clone()),
        }
    }

    #[test]
    fn appairage_complet_et_messages() {
        let dir = tempfile::tempdir().unwrap();
        let mut ines = Device::open(&dir.path().join("i.db"), &[1; 32]).unwrap();
        let mut malik = Device::open(&dir.path().join("m.db"), &[2; 32]).unwrap();
        let ib = ines.generate_bundle(5).unwrap();
        let _mb = malik.generate_bundle(5).unwrap();
        assert_eq!(ib.one_time_prekeys.len(), 5);
        assert_eq!(ib.kyber_prekey.len(), 1569, "ML-KEM-1024 sérialisé");
        assert_eq!(ib.identity_key.len(), 33);

        // Malik a rejoint : il récupère les clés d'Inès sur le serveur et ouvre la session.
        malik.start_session("ines", &partner_view(&ib, true)).unwrap();
        let e = malik.encrypt("ines", "On a planté notre jardin 🌱".as_bytes()).unwrap();
        assert_eq!(e.kind, 3);
        assert_eq!(ines.decrypt("malik", &e).unwrap(), "On a planté notre jardin 🌱".as_bytes());
        let r = ines.encrypt("malik", b"Je t'aime").unwrap();
        assert_eq!(r.kind, 2);
        assert_eq!(malik.decrypt("ines", &r).unwrap(), b"Je t'aime");

        // Mêmes symboles des deux côtés.
        let a = ines.sas_with(&malik.identity_key().unwrap()).unwrap();
        let b = malik.sas_with(&ines.identity_key().unwrap()).unwrap();
        assert_eq!(a, b);
        assert!(!ines.is_verified("malik").unwrap());
        ines.mark_verified("malik").unwrap();
        assert!(ines.is_verified("malik").unwrap());
    }

    #[test]
    fn des_cles_publiques_falsifiees_sont_refusees() {
        let dir = tempfile::tempdir().unwrap();
        let mut ines = Device::open(&dir.path().join("i.db"), &[1; 32]).unwrap();
        let mut malik = Device::open(&dir.path().join("m.db"), &[2; 32]).unwrap();
        let mut forged = partner_view(&ines.generate_bundle(1).unwrap(), false);
        // Le serveur remplace la pré-clé signée d'Inès par la sienne, sans pouvoir la signer.
        let mut rng = OsRng.unwrap_err();
        forged.signed_prekey = KeyPair::generate(&mut rng).public_key.serialize().to_vec();
        assert!(matches!(malik.start_session("ines", &forged), Err(DeviceError::BadBundle)));
    }

    #[test]
    fn identite_conservee_et_identifiants_croissants() {
        let dir = tempfile::tempdir().unwrap();
        let p = dir.path().join("i.db");
        let mut d = Device::open(&p, &[1; 32]).unwrap();
        let k1 = d.identity_key().unwrap();
        let b1 = d.generate_bundle(3).unwrap();
        drop(d);
        let mut d = Device::open(&p, &[1; 32]).unwrap();
        assert_eq!(d.identity_key().unwrap(), k1, "l'identité ne doit jamais changer d'elle-même");
        let b2 = d.generate_bundle(3).unwrap();
        assert!(b2.one_time_prekeys[0].id > b1.one_time_prekeys[2].id);
        assert!(b2.signed_prekey_id > b1.signed_prekey_id);
        assert_eq!(identity_fingerprint(&k1), d.fingerprint().unwrap());
    }
}
