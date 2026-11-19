//! Code FouLove : empreinte Argon2id et vérification (`foulov_core::pin`).

/// Empreinte à ranger dans le coffre du système ; `None` si le code n'a pas 6 chiffres.
pub fn lock_pin_hash(pin: String) -> Option<String> {
    foulov_core::pin::pin_hash(&pin)
}

pub fn lock_pin_verify(pin: String, stored: String) -> bool {
    foulov_core::pin::pin_verify(&pin, &stored)
}
