//! Phrase de récupération et sauvegarde chiffrée, exposées à Flutter (logique dans `foulov_core::backup`).

use foulov_core::backup as core;

use crate::api::device::with_device;

pub struct NewPhrase {
    /// 24 mots séparés par des espaces.
    pub phrase: String,
    /// Secret de 256 bits, à garder dans le coffre du système.
    pub secret: Vec<u8>,
}

#[flutter_rust_bridge::frb(sync)]
pub fn backup_new_phrase() -> NewPhrase {
    let (phrase, secret) = core::new_phrase();
    NewPhrase { phrase, secret: secret.to_vec() }
}

/// Phrase tapée → secret (erreur si mot inconnu, nombre de mots ou contrôle faux).
pub fn backup_phrase_to_secret(phrase: String) -> anyhow::Result<Vec<u8>> {
    Ok(core::phrase_to_secret(&phrase)?.to_vec())
}

pub fn backup_secret_to_phrase(secret: Vec<u8>) -> anyhow::Result<String> {
    let s: [u8; 32] = secret.try_into().map_err(|_| anyhow::anyhow!("secret invalide"))?;
    Ok(core::secret_to_phrase(&s))
}

fn key(secret: Vec<u8>) -> anyhow::Result<[u8; 32]> {
    secret.try_into().map_err(|_| anyhow::anyhow!("secret invalide"))
}

/// Sauvegarde chiffrée, prête à déposer.
pub fn backup_export(secret: Vec<u8>) -> anyhow::Result<Vec<u8>> {
    let k = key(secret)?;
    with_device(|d| Ok(d.export_backup(&k)?))
}

pub struct RestoreSummary {
    pub messages: u32,
    pub media: u32,
    pub dates: u32,
}

pub fn backup_import(secret: Vec<u8>, data: Vec<u8>) -> anyhow::Result<RestoreSummary> {
    let k = key(secret)?;
    with_device(|d| {
        let s = d.import_backup(&k, &data)?;
        Ok(RestoreSummary { messages: s.messages, media: s.media, dates: s.dates })
    })
}

/// Mot sans accents ni majuscules : pour comparer un mot recopié, quelle que soit la façon de taper les accents.
#[flutter_rust_bridge::frb(sync)]
pub fn backup_plain_word(word: String) -> String {
    core::plain_word(&word)
}
