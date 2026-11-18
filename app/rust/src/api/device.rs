//! Clés et sessions de ce téléphone, exposées à Flutter. Un seul « Device » ouvert à la fois,
//! protégé par un verrou ; toute la cryptographie est dans `foulov_core::device`.

use std::path::PathBuf;
use std::sync::Mutex;

use foulov_core::device::{self as core, Device};

static DEVICE: Mutex<Option<Device>> = Mutex::new(None);

pub(crate) fn with_device<T>(f: impl FnOnce(&mut Device) -> anyhow::Result<T>) -> anyhow::Result<T> {
    let mut g = DEVICE.lock().unwrap_or_else(|e| e.into_inner());
    let d = g.as_mut().ok_or_else(|| anyhow::anyhow!("base locale non ouverte"))?;
    f(d)
}

/// Ouvre la base chiffrée du téléphone (crée l'identité à la première ouverture).
/// `db_key` : 32 octets aléatoires conservés dans le Keystore / Keychain par l'app.
pub fn device_open(path: String, db_key: Vec<u8>) -> anyhow::Result<()> {
    let key: [u8; 32] = db_key.try_into().map_err(|_| anyhow::anyhow!("clé de base invalide"))?;
    let d = Device::open(&PathBuf::from(path), &key)?;
    *DEVICE.lock().unwrap_or_else(|e| e.into_inner()) = Some(d);
    Ok(())
}

pub fn device_identity_key() -> anyhow::Result<Vec<u8>> {
    with_device(|d| Ok(d.identity_key()?))
}

/// Empreinte de la clé d'identité, placée dans le QR code d'invitation.
pub fn device_fingerprint() -> anyhow::Result<Vec<u8>> {
    with_device(|d| Ok(d.fingerprint()?.to_vec()))
}

/// Empreinte d'une clé d'identité reçue du serveur, à comparer avec celle du QR code.
#[flutter_rust_bridge::frb(sync)]
pub fn fingerprint_of(identity_key: Vec<u8>) -> Vec<u8> {
    core::identity_fingerprint(&identity_key).to_vec()
}

pub struct OneTimePreKey {
    pub id: u32,
    pub public_key: Vec<u8>,
}

pub struct KeyBundle {
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

/// Génère de nouvelles clés et renvoie la partie publique à publier sur le serveur.
pub fn device_generate_bundle(one_time: u32) -> anyhow::Result<KeyBundle> {
    with_device(|d| {
        let b = d.generate_bundle(one_time)?;
        Ok(KeyBundle {
            registration_id: b.registration_id,
            device_id: b.device_id,
            identity_key: b.identity_key,
            signed_prekey_id: b.signed_prekey_id,
            signed_prekey: b.signed_prekey,
            signed_prekey_sig: b.signed_prekey_sig,
            kyber_prekey_id: b.kyber_prekey_id,
            kyber_prekey: b.kyber_prekey,
            kyber_prekey_sig: b.kyber_prekey_sig,
            one_time_prekeys: b.one_time_prekeys.into_iter().map(|k| OneTimePreKey { id: k.id, public_key: k.public_key }).collect(),
        })
    })
}

/// Ouvre la session à partir des clés du partenaire (`one_time_prekeys` : zéro ou une pré-clé).
pub fn device_start_session(partner: String, bundle: KeyBundle) -> anyhow::Result<()> {
    with_device(|d| {
        Ok(d.start_session(
            &partner,
            &core::PartnerBundle {
                registration_id: bundle.registration_id,
                device_id: bundle.device_id,
                identity_key: bundle.identity_key,
                signed_prekey_id: bundle.signed_prekey_id,
                signed_prekey: bundle.signed_prekey,
                signed_prekey_sig: bundle.signed_prekey_sig,
                kyber_prekey_id: bundle.kyber_prekey_id,
                kyber_prekey: bundle.kyber_prekey,
                kyber_prekey_sig: bundle.kyber_prekey_sig,
                one_time_prekey: bundle.one_time_prekeys.into_iter().next().map(|k| core::OneTimePreKey { id: k.id, public_key: k.public_key }),
            },
        )?)
    })
}

pub fn device_has_session(partner: String) -> anyhow::Result<bool> {
    with_device(|d| Ok(d.has_session(&partner)?))
}

pub struct Envelope {
    pub kind: u8,
    pub body: Vec<u8>,
}

pub fn device_encrypt(partner: String, plaintext: Vec<u8>) -> anyhow::Result<Envelope> {
    with_device(|d| {
        let e = d.encrypt(&partner, &plaintext)?;
        Ok(Envelope { kind: e.kind, body: e.body })
    })
}

pub fn device_decrypt(partner: String, envelope: Envelope) -> anyhow::Result<Vec<u8>> {
    with_device(|d| Ok(d.decrypt(&partner, &core::Envelope { kind: envelope.kind, body: envelope.body })?))
}

/// Les 7 symboles à comparer avec le partenaire.
pub fn device_sas_with(partner_identity: Vec<u8>) -> anyhow::Result<Vec<crate::api::crypto::SasSymbol>> {
    with_device(|d| {
        Ok(d.sas_with(&partner_identity)?
            .iter()
            .map(|s| crate::api::crypto::SasSymbol { emoji: s.emoji.to_string(), name: s.name_fr.to_string() })
            .collect())
    })
}

pub fn device_mark_verified(partner: String) -> anyhow::Result<()> {
    with_device(|d| Ok(d.mark_verified(&partner)?))
}

pub fn device_is_verified(partner: String) -> anyhow::Result<bool> {
    with_device(|d| Ok(d.is_verified(&partner)?))
}

/// Clé du partenaire en laquelle ce téléphone a confiance (`None` : jamais vue).
pub fn device_trusted_identity(partner: String) -> anyhow::Result<Option<Vec<u8>>> {
    with_device(|d| Ok(d.trusted_identity(&partner)?))
}

/// Accepte la nouvelle clé du partenaire (nouveau téléphone), après comparaison des 7 symboles.
pub fn device_accept_partner_key(partner: String, identity_key: Vec<u8>) -> anyhow::Result<()> {
    with_device(|d| Ok(d.accept_partner_key(&partner, &identity_key)?))
}
