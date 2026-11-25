//! API exposée à Flutter. Volontairement minimale : chaque fonction délègue au cœur `foulov_core`.

use foulov_core::media;

/// Version du cœur cryptographique (affichée dans « À propos » et utile aux rapports de bug).
#[flutter_rust_bridge::frb(sync)]
pub fn core_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Fichier chiffré prêt à être téléversé.
pub struct EncryptedMedia {
    /// Clé du fichier : à placer dans le message Signal, jamais ailleurs.
    pub key: Vec<u8>,
    pub ciphertext: Vec<u8>,
    pub sha256: Vec<u8>,
}

/// Chiffre un fichier (exécuté hors du fil de l'interface).
pub fn encrypt_media(plaintext: Vec<u8>) -> anyhow::Result<EncryptedMedia> {
    let e = media::encrypt(&plaintext)?;
    Ok(EncryptedMedia { key: e.key.to_vec(), ciphertext: e.ciphertext, sha256: e.sha256.to_vec() })
}

/// Vérifie l'empreinte puis déchiffre un fichier téléchargé.
pub fn decrypt_media(key: Vec<u8>, ciphertext: Vec<u8>, sha256: Vec<u8>) -> anyhow::Result<Vec<u8>> {
    let key: [u8; 32] = key.try_into().map_err(|_| anyhow::anyhow!("clé de fichier invalide"))?;
    let expected: [u8; 32] = sha256.try_into().map_err(|_| anyhow::anyhow!("empreinte invalide"))?;
    if !media::verify_sha256(&ciphertext, &expected) {
        anyhow::bail!("le fichier téléchargé ne correspond pas à son empreinte");
    }
    Ok(media::decrypt(&key, &ciphertext)?)
}

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}
