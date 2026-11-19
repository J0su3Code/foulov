//! Code FouLove (6 chiffres), indépendant du verrouillage du téléphone (`docs/SECURITY.md` §7).
//!
//! - Seule une empreinte Argon2id est gardée (sel aléatoire de 128 bits, 46 Mio, 1 passe : un réglage
//!   recommandé par l'OWASP). Elle est rangée par l'app dans le coffre du système (Keystore / Keychain).
//! - Six chiffres ne font que 10⁶ possibilités : la force du verrou vient de l'empreinte enfermée dans le coffre
//!   et des délais imposés par l'app après plusieurs erreurs, pas du code seul. C'est un verrou d'accès à
//!   l'interface, comme le verrou du téléphone : la base locale reste chiffrée par sa propre clé.

use argon2::{Algorithm, Argon2, Params, Version};
use rand::TryRngCore as _;
use rand::rngs::OsRng;

const M_KIB: u32 = 46 * 1024;
const T: u32 = 1;
const P: u32 = 1;

fn derive(pin: &str, salt: &[u8], m: u32, t: u32, p: u32) -> Option<[u8; 32]> {
    let params = Params::new(m, t, p, Some(32)).ok()?;
    let mut out = [0u8; 32];
    Argon2::new(Algorithm::Argon2id, Version::V0x13, params).hash_password_into(pin.as_bytes(), salt, &mut out).ok()?;
    Some(out)
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02x}")).collect()
}

fn unhex(s: &str) -> Option<Vec<u8>> {
    (s.len() % 2 == 0).then(|| (0..s.len()).step_by(2).map(|i| u8::from_str_radix(&s[i..i + 2], 16).ok()).collect())?
}

/// Code valide : exactement 6 chiffres.
pub fn valid_pin(pin: &str) -> bool {
    pin.len() == 6 && pin.bytes().all(|b| b.is_ascii_digit())
}

/// Empreinte à conserver : « argon2id$v19$m$t$p$sel$empreinte » (paramètres inclus, pour pouvoir les renforcer).
pub fn pin_hash(pin: &str) -> Option<String> {
    if !valid_pin(pin) {
        return None;
    }
    let mut salt = [0u8; 16];
    OsRng.try_fill_bytes(&mut salt).expect("générateur du système");
    let h = derive(pin, &salt, M_KIB, T, P)?;
    Some(format!("argon2id$v19${M_KIB}${T}${P}${}${}", hex(&salt), hex(&h)))
}

/// Vérifie un code contre son empreinte (comparaison en temps constant).
pub fn pin_verify(pin: &str, stored: &str) -> bool {
    let parts: Vec<&str> = stored.split('$').collect();
    let [alg, "v19", m, t, p, salt, h] = parts.as_slice() else { return false };
    if *alg != "argon2id" || !valid_pin(pin) {
        return false;
    }
    let (Ok(m), Ok(t), Ok(p), Some(salt), Some(h)) = (m.parse(), t.parse(), p.parse(), unhex(salt), unhex(h)) else {
        return false;
    };
    let Some(got) = derive(pin, &salt, m, t, p) else { return false };
    h.len() == 32 && got.iter().zip(&h).fold(0u8, |a, (x, y)| a | (x ^ y)) == 0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn code_juste_faux_et_mal_forme() {
        let h = pin_hash("041298").unwrap();
        assert!(h.starts_with("argon2id$v19$47104$1$1$"));
        assert!(pin_verify("041298", &h));
        assert!(!pin_verify("041299", &h));
        assert!(!pin_verify("04129", &h));
        assert!(!pin_verify("041298", "n'importe quoi"));
        assert_ne!(pin_hash("041298").unwrap(), h, "sel différent à chaque fois");
        assert!(pin_hash("12345a").is_none() && pin_hash("1234567").is_none());
    }
}
