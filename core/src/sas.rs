//! Vérification de l'appairage par 7 symboles (SAS, « short authentication string »).
//!
//! Les deux téléphones calculent la même suite de 7 symboles à partir des deux clés d'identité publiques.
//! Si un intermédiaire (y compris notre serveur) a substitué une clé, les suites diffèrent.
//!
//! - Entrée : les deux clés d'identité sérialisées, triées pour que l'ordre n'importe pas.
//! - Empreinte : SHA-256 avec séparation de domaine `FouLov-SAS-v1`.
//! - Sortie : les 42 premiers bits, découpés en 7 index de 6 bits dans une liste de 64 symboles.
//!
//! La liste reprend les 64 emojis standardisés par la spécification Matrix (choisis pour être faciles à
//! distinguer et à nommer à voix haute), avec des noms français.
//! Voir `docs/SECURITY.md` §5.

use sha2::{Digest, Sha256};

/// Domaine : à changer (v2, v3…) si le calcul évolue un jour, pour ne jamais confondre deux versions.
const DOMAIN: &[u8] = b"FouLov-SAS-v1";

/// Nombre de symboles affichés : 7 × 6 bits = 42 bits.
pub const SAS_LEN: usize = 7;

/// Un symbole de vérification.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Symbol {
    pub emoji: &'static str,
    pub name_fr: &'static str,
}

/// Les 64 symboles, dans l'ordre de la spécification Matrix (index 0 à 63).
pub const SYMBOLS: [Symbol; 64] = [
    Symbol { emoji: "🐶", name_fr: "Chien" },
    Symbol { emoji: "🐱", name_fr: "Chat" },
    Symbol { emoji: "🦁", name_fr: "Lion" },
    Symbol { emoji: "🐎", name_fr: "Cheval" },
    Symbol { emoji: "🦄", name_fr: "Licorne" },
    Symbol { emoji: "🐷", name_fr: "Cochon" },
    Symbol { emoji: "🐘", name_fr: "Éléphant" },
    Symbol { emoji: "🐰", name_fr: "Lapin" },
    Symbol { emoji: "🐼", name_fr: "Panda" },
    Symbol { emoji: "🐓", name_fr: "Coq" },
    Symbol { emoji: "🐧", name_fr: "Manchot" },
    Symbol { emoji: "🐢", name_fr: "Tortue" },
    Symbol { emoji: "🐟", name_fr: "Poisson" },
    Symbol { emoji: "🐙", name_fr: "Pieuvre" },
    Symbol { emoji: "🦋", name_fr: "Papillon" },
    Symbol { emoji: "🌷", name_fr: "Fleur" },
    Symbol { emoji: "🌳", name_fr: "Arbre" },
    Symbol { emoji: "🌵", name_fr: "Cactus" },
    Symbol { emoji: "🍄", name_fr: "Champignon" },
    Symbol { emoji: "🌏", name_fr: "Globe" },
    Symbol { emoji: "🌙", name_fr: "Lune" },
    Symbol { emoji: "☁️", name_fr: "Nuage" },
    Symbol { emoji: "🔥", name_fr: "Feu" },
    Symbol { emoji: "🍌", name_fr: "Banane" },
    Symbol { emoji: "🍎", name_fr: "Pomme" },
    Symbol { emoji: "🍓", name_fr: "Fraise" },
    Symbol { emoji: "🌽", name_fr: "Maïs" },
    Symbol { emoji: "🍕", name_fr: "Pizza" },
    Symbol { emoji: "🎂", name_fr: "Gâteau" },
    Symbol { emoji: "❤️", name_fr: "Cœur" },
    Symbol { emoji: "😀", name_fr: "Sourire" },
    Symbol { emoji: "🤖", name_fr: "Robot" },
    Symbol { emoji: "🎩", name_fr: "Chapeau" },
    Symbol { emoji: "👓", name_fr: "Lunettes" },
    Symbol { emoji: "🔧", name_fr: "Clé à molette" },
    Symbol { emoji: "🎅", name_fr: "Père Noël" },
    Symbol { emoji: "👍", name_fr: "Pouce" },
    Symbol { emoji: "☂️", name_fr: "Parapluie" },
    Symbol { emoji: "⌛", name_fr: "Sablier" },
    Symbol { emoji: "⏰", name_fr: "Réveil" },
    Symbol { emoji: "🎁", name_fr: "Cadeau" },
    Symbol { emoji: "💡", name_fr: "Ampoule" },
    Symbol { emoji: "📕", name_fr: "Livre" },
    Symbol { emoji: "✏️", name_fr: "Crayon" },
    Symbol { emoji: "📎", name_fr: "Trombone" },
    Symbol { emoji: "✂️", name_fr: "Ciseaux" },
    Symbol { emoji: "🔒", name_fr: "Cadenas" },
    Symbol { emoji: "🔑", name_fr: "Clé" },
    Symbol { emoji: "🔨", name_fr: "Marteau" },
    Symbol { emoji: "☎️", name_fr: "Téléphone" },
    Symbol { emoji: "🏁", name_fr: "Drapeau" },
    Symbol { emoji: "🚂", name_fr: "Train" },
    Symbol { emoji: "🚲", name_fr: "Vélo" },
    Symbol { emoji: "✈️", name_fr: "Avion" },
    Symbol { emoji: "🚀", name_fr: "Fusée" },
    Symbol { emoji: "🏆", name_fr: "Trophée" },
    Symbol { emoji: "⚽", name_fr: "Ballon" },
    Symbol { emoji: "🎸", name_fr: "Guitare" },
    Symbol { emoji: "🎺", name_fr: "Trompette" },
    Symbol { emoji: "🔔", name_fr: "Cloche" },
    Symbol { emoji: "⚓", name_fr: "Ancre" },
    Symbol { emoji: "🎧", name_fr: "Casque" },
    Symbol { emoji: "📁", name_fr: "Dossier" },
    Symbol { emoji: "📌", name_fr: "Punaise" },
];

/// Calcule les 7 index de symboles à partir des deux clés d'identité publiques sérialisées.
/// Le résultat est identique quel que soit l'ordre des deux clés.
pub fn sas_indices(identity_a: &[u8], identity_b: &[u8]) -> [u8; SAS_LEN] {
    let (first, second) = if identity_a <= identity_b { (identity_a, identity_b) } else { (identity_b, identity_a) };
    let mut h = Sha256::new();
    h.update(DOMAIN);
    // Longueurs préfixées : aucune ambiguïté possible entre (a, b) et une autre découpe des mêmes octets.
    for k in [first, second] {
        h.update((k.len() as u32).to_be_bytes());
        h.update(k);
    }
    let digest = h.finalize();
    // 42 premiers bits → 7 × 6 bits.
    let mut bits: u64 = 0;
    for &byte in &digest[..6] {
        bits = (bits << 8) | byte as u64;
    }
    let mut out = [0u8; SAS_LEN];
    for (i, slot) in out.iter_mut().enumerate() {
        *slot = ((bits >> (48 - 6 * (i + 1))) & 0x3f) as u8;
    }
    out
}

/// Les 7 symboles à afficher.
pub fn sas_symbols(identity_a: &[u8], identity_b: &[u8]) -> [Symbol; SAS_LEN] {
    sas_indices(identity_a, identity_b).map(|i| SYMBOLS[i as usize])
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn symboles_tous_distincts() {
        for i in 0..64 {
            for j in (i + 1)..64 {
                assert_ne!(SYMBOLS[i].emoji, SYMBOLS[j].emoji);
                assert_ne!(SYMBOLS[i].name_fr, SYMBOLS[j].name_fr);
            }
        }
    }

    #[test]
    fn ordre_des_cles_indifferent() {
        let a = [1u8; 33];
        let b = [2u8; 33];
        assert_eq!(sas_indices(&a, &b), sas_indices(&b, &a));
    }

    #[test]
    fn une_cle_differente_change_les_symboles() {
        let a = [1u8; 33];
        let b = [2u8; 33];
        let mut b2 = b;
        b2[32] ^= 1;
        assert_ne!(sas_indices(&a, &b), sas_indices(&a, &b2));
    }

    #[test]
    fn vecteur_de_reference() {
        // Vecteur figé : si ce test casse, le calcul a changé et les anciennes versions de l'app
        // n'afficheraient plus les mêmes symboles. Changer DOMAIN dans ce cas.
        let got = sas_indices(&[0x05; 33], &[0x06; 33]);
        // Valeur recalculée indépendamment en Python (hashlib) : [31, 18, 4, 44, 36, 6, 58].
        assert_eq!(got, [31, 18, 4, 44, 36, 6, 58]);
    }
}
