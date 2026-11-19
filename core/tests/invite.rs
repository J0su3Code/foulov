//! Invitation à distance : la preuve tirée du secret de l'invitation vérifie la clé de celui qui rejoint.

use foulov_core::chat::Received;
use foulov_core::device::{Device, LocalBundle, PartnerBundle};

fn view(b: &LocalBundle) -> PartnerBundle {
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
        one_time_prekey: b.one_time_prekeys.first().cloned(),
    }
}

fn pair(dir: &std::path::Path, secret_used: &[u8]) -> (Device, Device) {
    let mut ines = Device::open(&dir.join("i.db"), &[1; 32]).unwrap();
    let mut malik = Device::open(&dir.join("m.db"), &[2; 32]).unwrap();
    let ib = ines.generate_bundle(3).unwrap();
    malik.generate_bundle(3).unwrap();
    malik.start_session("ines", &view(&ib)).unwrap();
    let hello = malik.join_hello("ines", secret_used).unwrap();
    let env = malik.encrypt("ines", &hello).unwrap();
    assert_eq!(ines.receive("malik", "e1", &env).unwrap(), Received::Nothing, "le bonjour n'est pas un message");
    (ines, malik)
}

#[test]
fn bon_secret_cle_verifiee_une_seule_fois() {
    let dir = tempfile::tempdir().unwrap();
    let secret = [7u8; 16];
    let (ines, _) = pair(dir.path(), &secret);
    assert!(!ines.is_verified("malik").unwrap());
    assert!(ines.verify_join_proof("malik", &secret).unwrap());
    assert!(ines.is_verified("malik").unwrap(), "vérifiée sans symboles");
    assert!(!ines.verify_join_proof("malik", &secret).unwrap(), "la preuve ne sert qu'une fois");
}

#[test]
fn sans_le_secret_pas_de_verification() {
    let dir = tempfile::tempdir().unwrap();
    // Quelqu'un qui n'a pas reçu l'invitation (le serveur, par exemple) ne connaît pas le secret.
    let (ines, _) = pair(dir.path(), &[9u8; 16]);
    assert!(!ines.verify_join_proof("malik", &[7u8; 16]).unwrap());
    assert!(!ines.is_verified("malik").unwrap(), "il faudra comparer les symboles");
}
