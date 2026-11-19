//! Récupérer l'historique depuis le téléphone de l'autre : demande, accord, archive chiffrée, import inversé.

use std::fs;

use foulov_core::chat::Received;
use foulov_core::chat_media::{KIND_PHOTO, NewMedia};
use foulov_core::device::{Device, LocalBundle, PartnerBundle};

const KEY_PHOTO: &str = "c/0f2c1a6e-1111-4222-8333-444455556666/0123456789abcdef0123456789abcdef";
const KEY_ARCHIVE: &str = "c/0f2c1a6e-1111-4222-8333-444455556666/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";

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
fn nouveau_telephone_recupere_l_historique_de_l_autre() {
    let dir = tempfile::tempdir().unwrap();
    let d = dir.path();
    let mut ines = Device::open(&d.join("i.db"), &[1; 32]).unwrap();
    let mut malik = Device::open(&d.join("m.db"), &[2; 32]).unwrap();
    let ib = ines.generate_bundle(5).unwrap();
    malik.generate_bundle(5).unwrap();
    malik.start_session("ines", &view(&ib)).unwrap();

    // Leur histoire : un message de chaque, une photo de Malik, une lettre d'Inès.
    let (_, o) = malik.send_text("ines", "Bonjour toi", None).unwrap();
    ines.receive("malik", &o.envelope_id, &o.envelope).unwrap();
    let (_, o) = ines.send_text("malik", "Bonjour mon cœur", None).unwrap();
    malik.receive("ines", &o.envelope_id, &o.envelope).unwrap();
    let photo = NewMedia { kind: KIND_PHOTO, mime: "image/jpeg", width: 4, height: 4, duration_ms: 0, thumb: b"t", caption: "nous", reply_to: None };
    let (pm, _) = malik.create_media(&d.join("m"), &[5u8; 400], photo).unwrap();
    let o = malik.media_uploaded("ines", &pm.id, KEY_PHOTO).unwrap().unwrap();
    ines.receive("malik", &o.envelope_id, &o.envelope).unwrap();
    let (_, o) = ines.send_letter("malik", "Pour toi", "Je t'aime.", None).unwrap();
    malik.receive("ines", &o.envelope_id, &o.envelope).unwrap();

    // Malik perd son téléphone, sans phrase : nouveau téléphone, nouvelle session, clé acceptée par Inès.
    let mut malik2 = Device::open(&d.join("m2.db"), &[3; 32]).unwrap();
    malik2.generate_bundle(5).unwrap();
    let ib2 = ines.generate_bundle(5).unwrap();
    malik2.start_session("ines", &view(&ib2)).unwrap();
    let ask = malik2.request_history("ines").unwrap();
    assert!(ask.urgent, "la demande réveille son téléphone");
    assert!(malik2.history_state().unwrap().waiting);
    assert!(ines.receive("malik", &ask.envelope_id, &ask.envelope).is_err(), "nouvelle clé à vérifier d'abord");
    ines.accept_partner_key("malik", &malik2.identity_key().unwrap()).unwrap();
    assert_eq!(ines.receive("malik", &ask.envelope_id, &ask.envelope).unwrap(), Received::HistoryRequested);
    assert!(ines.history_state().unwrap().asked);

    // Inès accepte : archive chiffrée, déposée sur « R2 », puis l'offre part chiffrée.
    let up = ines.offer_history(&d.join("i")).unwrap();
    let r2 = d.join("r2-archive");
    fs::copy(&up.path, &r2).unwrap();
    assert!(!fs::read(&r2).unwrap().windows(11).any(|w| w == b"Bonjour toi"), "jamais en clair");
    let offer = ines.media_uploaded("malik", &up.message_id, KEY_ARCHIVE).unwrap().unwrap();
    assert!(!ines.history_state().unwrap().asked);
    assert_eq!(malik2.receive("ines", &offer.envelope_id, &offer.envelope).unwrap(), Received::HistoryOffered);

    // Malik télécharge, l'empreinte est vérifiée, puis l'import inverse « moi » et « toi ».
    let st = malik2.history_state().unwrap();
    assert!(st.incoming && !st.ready && !st.waiting);
    assert!(malik2.import_history().unwrap().is_none(), "pas avant le téléchargement");
    let dl = malik2.pending_downloads().unwrap();
    assert_eq!(dl[0].object_key, KEY_ARCHIVE);
    let part = d.join("dl.part");
    fs::copy(&r2, &part).unwrap();
    assert!(malik2.media_downloaded(&dl[0].message_id, &part, &d.join("m2")).unwrap());
    let sum = malik2.import_history().unwrap().unwrap();
    assert_eq!((sum.messages, sum.letters), (3, 1));
    let msgs = malik2.messages(None, 50).unwrap();
    let mine: Vec<_> = msgs.iter().filter(|m| m.from_me).map(|m| m.body.as_str()).collect();
    let theirs: Vec<_> = msgs.iter().filter(|m| !m.from_me).map(|m| m.body.as_str()).collect();
    assert!(mine.contains(&"Bonjour toi") && mine.contains(&"nous"), "{mine:?}");
    assert_eq!(theirs, vec!["Bonjour mon cœur"]);
    let l = &malik2.letters().unwrap()[0];
    assert!(!l.from_me && l.title == "Pour toi", "la lettre d'Inès reste la sienne");
    // La photo revient avec sa clé : à retélécharger depuis R2 ; l'archive, elle, part à la corbeille.
    assert!(malik2.pending_downloads().unwrap().iter().any(|p| p.object_key == KEY_PHOTO));
    assert_eq!(malik2.r2_trash().unwrap(), vec![KEY_ARCHIVE.to_owned()]);
    assert!(!malik2.history_state().unwrap().incoming);
}

#[test]
fn une_offre_non_demandee_est_ignoree() {
    let dir = tempfile::tempdir().unwrap();
    let d = dir.path();
    let mut ines = Device::open(&d.join("i.db"), &[1; 32]).unwrap();
    let mut malik = Device::open(&d.join("m.db"), &[2; 32]).unwrap();
    let ib = ines.generate_bundle(5).unwrap();
    malik.generate_bundle(5).unwrap();
    malik.start_session("ines", &view(&ib)).unwrap();
    // Malik n'a rien demandé ; Inès ne peut même pas préparer d'archive sans demande.
    assert!(ines.offer_history(&d.join("i")).is_err());
    let (_, o) = malik.send_text("ines", "salut", None).unwrap();
    ines.receive("malik", &o.envelope_id, &o.envelope).unwrap();
    assert!(!malik.history_state().unwrap().incoming);
}
