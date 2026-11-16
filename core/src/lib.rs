//! Cœur cryptographique de FouLov.
//!
//! Règle d'or : aucun algorithme n'est inventé ici. Ce crate assemble des briques éprouvées
//! (libsignal, RustCrypto) et expose une API minimale à l'app Flutter.
//! Conception complète : `docs/SECURITY.md`.

pub mod media;
pub mod sas;

pub use libsignal_protocol;
