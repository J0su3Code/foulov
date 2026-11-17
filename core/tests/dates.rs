//! Dates importantes : partagées chiffrées, la plus récente l'emporte, suppression qui ne revient pas.

use foulov_core::chat::Received;
use foulov_core::dates::DateEntry;
use foulov_core::device::{Device, LocalBundle, PartnerBundle};

const INES: &str = "ines";
const MALIK: &str = "malik";

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

fn new(title: &str, date: &str) -> DateEntry {
    DateEntry { id: String::new(), title: title.into(), date: date.into(), yearly: true, remind_days: Some(1), updated_at: 0 }
}

#[test]
fn dates_partagees_modifiees_et_supprimees() {
    let dir = tempfile::tempdir().unwrap();
    let mut ines = Device::open(&dir.path().join("i.db"), &[1; 32]).unwrap();
    let mut malik = Device::open(&dir.path().join("m.db"), &[2; 32]).unwrap();
    let ib = ines.generate_bundle(3).unwrap();
    malik.generate_bundle(3).unwrap();
    malik.start_session(INES, &view(&ib)).unwrap();

    let (d, o) = malik.save_date(INES, new("  Anniversaire d'Inès 🎂 ", "1998-04-12")).unwrap();
    assert_eq!(d.title, "Anniversaire d'Inès 🎂");
    assert!(!o.urgent, "une date ne réveille pas le téléphone");
    assert_eq!(ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap(), Received::Dates);
    assert_eq!(ines.dates().unwrap(), vec![d.clone()]);

    // Inès la modifie : Malik reçoit la nouvelle version ; une ancienne version arrivée en retard est ignorée.
    let (_, o) = ines.send_text(MALIK, "réponse", None).unwrap();
    malik.receive(INES, &o.envelope_id, &o.envelope).unwrap();
    std::thread::sleep(std::time::Duration::from_millis(3));
    let mut edit = d.clone();
    edit.remind_days = Some(7);
    let (e2, o2) = ines.save_date(MALIK, edit).unwrap();
    malik.receive(INES, &o2.envelope_id, &o2.envelope).unwrap();
    assert_eq!(malik.dates().unwrap()[0].remind_days, Some(7));

    // Suppression : disparaît chez les deux et ne revient pas avec une version plus ancienne.
    std::thread::sleep(std::time::Duration::from_millis(3));
    let del = malik.delete_date(INES, &e2.id).unwrap();
    ines.receive(MALIK, &del.envelope_id, &del.envelope).unwrap();
    assert!(ines.dates().unwrap().is_empty());
    assert!(malik.dates().unwrap().is_empty());
    let stale = ines.save_date(MALIK, DateEntry { updated_at: 0, ..e2.clone() });
    // (ré-enregistrer plus tard est un vrai choix : autorisé, plus récent que la suppression)
    assert!(stale.is_ok());

    assert!(malik.save_date(INES, new("", "2020-01-01")).is_err(), "titre vide");
    assert!(malik.save_date(INES, new("x", "2020-02-30")).is_err(), "jour impossible");
    let mut far = new("x", "2020-01-01");
    far.remind_days = Some(61);
    assert!(malik.save_date(INES, far).is_err(), "rappel trop lointain");
}
