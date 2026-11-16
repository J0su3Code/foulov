//! Chiffrement des photos, vidéos et fichiers (`docs/SECURITY.md` §6).
//!
//! - Une clé aléatoire de 256 bits par fichier, transmise uniquement à l'intérieur d'un message Signal.
//! - Construction STREAM (Hoang, Reyhanitabar, Rogaway, Vizár, 2015) via `aead::stream` de RustCrypto,
//!   avec AES-256-GCM : blocs de 64 Kio, nonce = préfixe aléatoire ‖ compteur ‖ drapeau « dernier bloc ».
//!   On ne peut ni réordonner, ni tronquer, ni dupliquer, ni modifier un bloc sans échec du déchiffrement.
//! - L'en-tête (format, préfixe de nonce, tailles) est authentifié comme donnée associée de chaque bloc.
//! - Remplissage Padmé (Nikitin et al., « Reducing Metadata Leakage from Encrypted Files and
//!   Communication with PURBs », PETS 2019) : la taille chiffrée ne révèle que O(log log n) bits de la
//!   taille réelle, pour au plus 12 % de surcoût. Le remplissage est à l'intérieur du chiffré.
//!
//! Format : `MAGIC (4) ‖ préfixe de nonce (7) ‖ blocs chiffrés`.
//! Le dernier bloc commence en clair par la longueur réelle du contenu (u64, grand-boutiste) une fois
//! déchiffré ; on la lit après vérification de toute l'authenticité.

use aes_gcm::aead::stream::{DecryptorBE32, EncryptorBE32};
use aes_gcm::aead::{KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Key};
use rand::TryRngCore as _;
use rand::rngs::OsRng;
use sha2::{Digest, Sha256};

/// Identifie le format (version 1). À incrémenter si le format évolue.
pub const MAGIC: &[u8; 4] = b"FLM1";
/// Taille des blocs en clair.
pub const CHUNK: usize = 64 * 1024;
/// Taille du tag d'authentification AES-GCM.
const TAG: usize = 16;
const NONCE_PREFIX: usize = 7;
const HEADER: usize = MAGIC.len() + NONCE_PREFIX;
const LEN_FIELD: usize = 8;

#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum MediaError {
    #[error("format de fichier chiffré inconnu")]
    BadFormat,
    #[error("fichier chiffré altéré, tronqué ou mauvaise clé")]
    Corrupted,
    #[error("générateur aléatoire du système indisponible")]
    Rng,
}

/// Résultat du chiffrement d'un fichier.
pub struct EncryptedMedia {
    /// Clé du fichier : à placer dans le message Signal, jamais ailleurs.
    pub key: [u8; 32],
    /// Octets à téléverser sur R2.
    pub ciphertext: Vec<u8>,
    /// Empreinte SHA-256 du chiffré : permet de vérifier le téléchargement avant de le déchiffrer.
    pub sha256: [u8; 32],
}

/// Taille après remplissage Padmé (au moins `len`, surcoût ≤ 12 %).
pub fn padme(len: u64) -> u64 {
    if len < 2 {
        return len;
    }
    let e = 63 - len.leading_zeros() as u64; // ⌊log2 L⌋
    let s = 64 - e.leading_zeros() as u64; // ⌊log2 E⌋ + 1
    let z = e - s;
    let mask = (1u64 << z) - 1;
    (len + mask) & !mask
}

/// Taille totale du chiffré pour un contenu de `len` octets.
pub fn ciphertext_len(len: u64) -> u64 {
    let padded = padme(len + LEN_FIELD as u64);
    let chunks = padded.div_ceil(CHUNK as u64).max(1);
    HEADER as u64 + padded + chunks * TAG as u64
}

/// Chiffre un fichier en mémoire.
pub fn encrypt(plaintext: &[u8]) -> Result<EncryptedMedia, MediaError> {
    let mut key = [0u8; 32];
    let mut prefix = [0u8; NONCE_PREFIX];
    OsRng.try_fill_bytes(&mut key).map_err(|_| MediaError::Rng)?;
    OsRng.try_fill_bytes(&mut prefix).map_err(|_| MediaError::Rng)?;
    let ciphertext = encrypt_with(&key, &prefix, plaintext);
    let sha256 = Sha256::digest(&ciphertext).into();
    Ok(EncryptedMedia { key, ciphertext, sha256 })
}

fn header(prefix: &[u8; NONCE_PREFIX]) -> [u8; HEADER] {
    let mut h = [0u8; HEADER];
    h[..4].copy_from_slice(MAGIC);
    h[4..].copy_from_slice(prefix);
    h
}

fn encrypt_with(key: &[u8; 32], prefix: &[u8; NONCE_PREFIX], plaintext: &[u8]) -> Vec<u8> {
    // Contenu = longueur réelle ‖ données ‖ zéros jusqu'à la taille Padmé.
    let mut body = Vec::with_capacity(padme(plaintext.len() as u64 + LEN_FIELD as u64) as usize);
    body.extend_from_slice(&(plaintext.len() as u64).to_be_bytes());
    body.extend_from_slice(plaintext);
    body.resize(padme(body.len() as u64) as usize, 0);

    let head = header(prefix);
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let mut enc = EncryptorBE32::from_aead(cipher, prefix.into());
    let mut out = Vec::with_capacity(ciphertext_len(plaintext.len() as u64) as usize);
    out.extend_from_slice(&head);

    let mut chunks = body.chunks(CHUNK).peekable();
    loop {
        let chunk = chunks.next().unwrap_or(&[]);
        let payload = Payload { msg: chunk, aad: &head };
        if chunks.peek().is_none() {
            out.extend_from_slice(&enc.encrypt_last(payload).expect("taille de bloc valide"));
            break;
        }
        out.extend_from_slice(&enc.encrypt_next(payload).expect("taille de bloc valide"));
    }
    out
}

/// Déchiffre et vérifie un fichier. Échoue au moindre octet modifié, ajouté ou retiré.
pub fn decrypt(key: &[u8; 32], data: &[u8]) -> Result<Vec<u8>, MediaError> {
    if data.len() < HEADER + TAG || &data[..4] != MAGIC {
        return Err(MediaError::BadFormat);
    }
    let head: [u8; HEADER] = data[..HEADER].try_into().expect("longueur vérifiée");
    let prefix: [u8; NONCE_PREFIX] = head[4..].try_into().expect("longueur vérifiée");
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let mut dec = DecryptorBE32::from_aead(cipher, (&prefix).into());

    let mut body = Vec::with_capacity(data.len());
    let mut chunks = data[HEADER..].chunks(CHUNK + TAG).peekable();
    loop {
        let chunk = chunks.next().ok_or(MediaError::Corrupted)?;
        let payload = Payload { msg: chunk, aad: &head };
        if chunks.peek().is_none() {
            body.extend_from_slice(&dec.decrypt_last(payload).map_err(|_| MediaError::Corrupted)?);
            break;
        }
        body.extend_from_slice(&dec.decrypt_next(payload).map_err(|_| MediaError::Corrupted)?);
    }
    // Authenticité vérifiée : on peut lire la longueur réelle.
    if body.len() < LEN_FIELD {
        return Err(MediaError::Corrupted);
    }
    let len = u64::from_be_bytes(body[..LEN_FIELD].try_into().expect("8 octets")) as usize;
    if len > body.len() - LEN_FIELD {
        return Err(MediaError::Corrupted);
    }
    body.drain(..LEN_FIELD);
    body.truncate(len);
    Ok(body)
}

/// Vérifie l'empreinte d'un téléchargement avant de le déchiffrer.
pub fn verify_sha256(data: &[u8], expected: &[u8; 32]) -> bool {
    let got: [u8; 32] = Sha256::digest(data).into();
    // Comparaison sans fuite de durée (l'empreinte n'est pas secrète, mais restons rigoureux).
    got.iter().zip(expected).fold(0u8, |acc, (a, b)| acc | (a ^ b)) == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample(n: usize) -> Vec<u8> {
        (0..n).map(|i| (i * 31 + 7) as u8).collect()
    }

    #[test]
    fn aller_retour_toutes_tailles() {
        for n in [0, 1, 7, 8, 100, CHUNK - 9, CHUNK - 8, CHUNK, CHUNK + 1, 3 * CHUNK + 5, 1_000_000] {
            let p = sample(n);
            let e = encrypt(&p).unwrap();
            assert_eq!(e.ciphertext.len() as u64, ciphertext_len(n as u64), "taille annoncée, n={n}");
            assert!(verify_sha256(&e.ciphertext, &e.sha256));
            assert_eq!(decrypt(&e.key, &e.ciphertext).unwrap(), p, "n={n}");
        }
    }

    #[test]
    fn le_contenu_n_apparait_jamais_en_clair() {
        let p = b"Elles ont fleuri sur le balcon".repeat(100);
        let e = encrypt(&p).unwrap();
        assert!(!e.ciphertext.windows(12).any(|w| w == b"ont fleuri s"));
    }

    #[test]
    fn padme_surcout_maximal_12_pourcent() {
        let mut n = 2u64;
        while n < 1 << 40 {
            for m in [n, n + 1, n + n / 3] {
                let p = padme(m);
                assert!(p >= m);
                assert!((p - m) as f64 / m as f64 <= 0.12 + 1e-9, "m={m} p={p}");
            }
            n = n * 3 / 2 + 1;
        }
    }

    #[test]
    fn padme_masque_les_petites_differences() {
        // Deux photos de tailles proches donnent la même taille chiffrée.
        assert_eq!(ciphertext_len(2_000_000), ciphertext_len(2_010_000));
    }

    #[test]
    fn un_bit_modifie_est_detecte() {
        let e = encrypt(&sample(200_000)).unwrap();
        for pos in [0, 5, HEADER, HEADER + 100, e.ciphertext.len() / 2, e.ciphertext.len() - 1] {
            let mut c = e.ciphertext.clone();
            c[pos] ^= 0x01;
            assert!(decrypt(&e.key, &c).is_err(), "pos={pos}");
        }
    }

    #[test]
    fn troncature_et_reordonnancement_detectes() {
        let e = encrypt(&sample(3 * CHUNK + 10)).unwrap();
        let block = CHUNK + TAG;
        // Retirer le dernier bloc : l'avant-dernier n'est pas marqué « dernier ».
        let trunc = &e.ciphertext[..HEADER + 3 * block];
        assert_eq!(decrypt(&e.key, trunc), Err(MediaError::Corrupted));
        // Échanger deux blocs.
        let mut swapped = e.ciphertext.clone();
        let (a, b) = (HEADER, HEADER + block);
        let first = swapped[a..a + block].to_vec();
        let second = swapped[b..b + block].to_vec();
        swapped[a..a + block].copy_from_slice(&second);
        swapped[b..b + block].copy_from_slice(&first);
        assert_eq!(decrypt(&e.key, &swapped), Err(MediaError::Corrupted));
        // Ajouter des octets à la fin.
        let mut longer = e.ciphertext.clone();
        longer.extend_from_slice(&[0u8; 20]);
        assert!(decrypt(&e.key, &longer).is_err());
    }

    #[test]
    fn mauvaise_cle_refusee() {
        let e = encrypt(&sample(1000)).unwrap();
        let mut k = e.key;
        k[0] ^= 1;
        assert_eq!(decrypt(&k, &e.ciphertext), Err(MediaError::Corrupted));
    }

    #[test]
    fn deux_chiffrements_du_meme_fichier_different() {
        let p = sample(5000);
        let a = encrypt(&p).unwrap();
        let b = encrypt(&p).unwrap();
        assert_ne!(a.key, b.key);
        assert_ne!(a.ciphertext, b.ciphertext);
    }
}
