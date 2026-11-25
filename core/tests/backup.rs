//! Sauvegarde chiffrée : tout revient sur un téléphone neuf, rien sans la bonne phrase.

use std::fs;

use foulov_core::backup::{new_phrase, phrase_to_secret};
use foulov_core::chat::Received;
use foulov_core::chat_media::NewMedia;
use foulov_core::dates::DateEntry;
use foulov_core::device::{Device, LocalBundle, PartnerBundle};

const INES: &str = "ines";
const MALIK: &str = "malik";
const KEY: &str = "c/0f2c1a6e-1111-4222-8333-444455556666/0123456789abcdef0123456789abcdef";

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

#[test]
fn sauvegarde_puis_restauration_sur_un_telephone_neuf() {
    let dir = tempfile::tempdir().unwrap();
    let mut ines = Device::open(&dir.path().join("i.db"), &[1; 32]).unwrap();
    let mut malik = Device::open(&dir.path().join("m.db"), &[2; 32]).unwrap();
    let ib = ines.generate_bundle(3).unwrap();
    malik.generate_bundle(3).unwrap();
    malik.start_session(INES, &view(&ib)).unwrap();

    // Un peu d'histoire chez Inès : messages reçus et envoyés, une photo, un prénom, une date.
    let (_, o) = malik.send_text(INES, "Premier mot doux", None).unwrap();
    ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap();
    let (mine, _) = ines.send_text(MALIK, "Réponse d'Inès", None).unwrap();
    let (photo, _) = malik
        .create_media(
            &dir.path().join("m"),
            &[3u8; 3000],
            NewMedia { kind: 1, mime: "image/jpeg", width: 10, height: 10, duration_ms: 0, thumb: b"mini", caption: "nous", reply_to: None },
        )
        .unwrap();
    let o = malik.media_uploaded(INES, &photo.id, KEY).unwrap().unwrap();
    let Received::Message(p) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    let o = malik.set_my_name(INES, "Malik").unwrap();
    ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap();
    ines.set_partner_nickname("Mon cœur").unwrap();
    ines.save_date(MALIK, DateEntry { id: String::new(), title: "Rencontre".into(), date: "2022-03-12".into(), yearly: true, remind_days: Some(1), updated_at: 0 }).unwrap();

    let (phrase, secret) = new_phrase();
    let blob = ines.export_backup(&secret).unwrap();
    assert_eq!(&blob[..4], b"FLB1");
    for needle in ["Premier mot doux", "Rencontre", "Mon cœur", "Malik"] {
        assert!(!blob.windows(needle.len()).any(|w| w == needle.as_bytes()), "« {needle} » jamais en clair");
    }

    // Téléphone neuf : nouvelle identité, et la sauvegarde avec la phrase tapée à la main.
    let mut fresh = Device::open(&dir.path().join("new.db"), &[9; 32]).unwrap();
    assert_ne!(fresh.identity_key().unwrap(), ines.identity_key().unwrap(), "nouvelle identité, pas de clés Signal restaurées");
    let typed = phrase_to_secret(&phrase.to_uppercase()).unwrap();
    let sum = fresh.import_backup(&typed, &blob).unwrap();
    assert_eq!((sum.messages, sum.media, sum.dates), (3, 1, 1));
    assert_eq!(fresh.messages(None, 10).unwrap().len(), 3);
    assert_eq!(fresh.message(&mine.id).unwrap().unwrap().body, "Réponse d'Inès");
    let restored = fresh.message(&p.id).unwrap().unwrap();
    assert_eq!(restored.media.as_ref().unwrap().state, 2, "photo à retélécharger depuis R2");
    assert_eq!(fresh.pending_downloads().unwrap()[0].object_key, KEY);
    let prof = fresh.profile().unwrap();
    assert_eq!((prof.partner_name.as_deref(), prof.partner_nickname.as_deref()), (Some("Malik"), Some("Mon cœur")));
    assert_eq!(fresh.dates().unwrap()[0].title, "Rencontre");
    assert!(!fresh.has_session(MALIK).unwrap(), "aucune session restaurée : il faudra en rouvrir une");

    // Une seconde restauration n'ajoute aucun doublon.
    assert_eq!(fresh.import_backup(&typed, &blob).unwrap().messages, 0);
}

#[test]
fn mauvaise_phrase_ou_sauvegarde_alteree() {
    let dir = tempfile::tempdir().unwrap();
    let d = Device::open(&dir.path().join("a.db"), &[1; 32]).unwrap();
    d.set_partner_nickname("x").unwrap();
    let (_, secret) = new_phrase();
    let blob = d.export_backup(&secret).unwrap();
    let (_, other) = new_phrase();
    let mut fresh = Device::open(&dir.path().join("b.db"), &[2; 32]).unwrap();
    assert!(fresh.import_backup(&other, &blob).is_err(), "autre phrase");
    let mut bad = blob.clone();
    let n = bad.len();
    bad[n / 2] ^= 1;
    assert!(fresh.import_backup(&secret, &bad).is_err(), "un bit modifié");
    assert!(fresh.import_backup(&secret, &blob[..blob.len() - 10]).is_err(), "tronquée");
    let p = dir.path().join("x");
    fs::write(&p, b"FLB1").unwrap();
    assert!(fresh.import_backup(&secret, &fs::read(&p).unwrap()).is_err());
    assert!(fresh.import_backup(&secret, &blob).is_ok());
}

#[test]
fn changement_de_telephone_refuse_puis_accepte_apres_verification() {
    let dir = tempfile::tempdir().unwrap();
    let mut ines = Device::open(&dir.path().join("i.db"), &[1; 32]).unwrap();
    let mut malik = Device::open(&dir.path().join("m.db"), &[2; 32]).unwrap();
    let ib = ines.generate_bundle(5).unwrap();
    malik.generate_bundle(5).unwrap();
    malik.start_session(INES, &view(&ib)).unwrap();
    let (_, o) = malik.send_text(INES, "avant", None).unwrap();
    ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap();
    let old = ines.trusted_identity(MALIK).unwrap().unwrap();
    assert_eq!(old, malik.identity_key().unwrap());

    // Malik change de téléphone : nouvelle identité, nouvelle session.
    let mut malik2 = Device::open(&dir.path().join("m2.db"), &[3; 32]).unwrap();
    malik2.generate_bundle(5).unwrap();
    let ib2 = ines.generate_bundle(5).unwrap();
    malik2.start_session(INES, &view(&ib2)).unwrap();
    let (_, o) = malik2.send_text(INES, "nouveau téléphone", None).unwrap();
    let new_key = malik2.identity_key().unwrap();
    assert_ne!(new_key, old);

    // Chez Inès : refusé tant que la nouvelle clé n'est pas acceptée, et l'enveloppe reste à relire.
    assert!(matches!(
        ines.receive(MALIK, &o.envelope_id, &o.envelope),
        Err(foulov_core::device::DeviceError::PartnerKeyChanged)
    ));
    assert_eq!(ines.trusted_identity(MALIK).unwrap().unwrap(), old, "l'ancienne clé reste la clé de confiance");
    // Après contrôle par lien : acceptée (non vérifiée), puis marquée vérifiée.
    ines.accept_partner_key(MALIK, &new_key).unwrap();
    assert!(!ines.is_verified(MALIK).unwrap());
    assert!(ines.mark_verified(MALIK, &old).is_err(), "on ne vérifie jamais une autre clé que celle enregistrée");
    assert!(!ines.is_verified(MALIK).unwrap());
    ines.mark_verified(MALIK, &new_key).unwrap();
    let Received::Message(m) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!("message attendu") };
    assert_eq!(m.body, "nouveau téléphone");
    assert_eq!(ines.trusted_identity(MALIK).unwrap().unwrap(), new_key);
}
