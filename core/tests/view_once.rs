//! Vue unique : une photo ou vidéo qui ne s'ouvre qu'une fois, puis disparaît des deux téléphones et de R2.
//! L'expéditeur ne peut pas la revoir ; elle n'entre jamais dans la sauvegarde ni dans la galerie.

use std::fs;
use std::path::Path;

use foulov_core::chat::Received;
use foulov_core::chat_media::{KIND_PHOTO, NewMedia};
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

fn couple(dir: &Path) -> (Device, Device) {
    let mut ines = Device::open(&dir.join("ines.db"), &[1; 32]).unwrap();
    let mut malik = Device::open(&dir.join("malik.db"), &[2; 32]).unwrap();
    let ib = ines.generate_bundle(5).unwrap();
    malik.generate_bundle(5).unwrap();
    malik.start_session(INES, &view(&ib)).unwrap();
    (ines, malik)
}

fn photo() -> NewMedia<'static> {
    NewMedia {
        kind: KIND_PHOTO,
        mime: "image/jpeg",
        width: 800,
        height: 600,
        duration_ms: 0,
        thumb: b"miniature-qui-ne-doit-jamais-partir",
        caption: "",
        reply_to: None,
    }
}

#[test]
fn vue_unique_ouverte_une_fois_puis_detruite_partout() {
    let dir = tempfile::tempdir().unwrap();
    let d = dir.path();
    let (mut ines, mut malik) = couple(d);
    let plain: Vec<u8> = (0..50_000u32).map(|i| (i * 13 % 251) as u8).collect();

    // Malik envoie une vue unique : pas de miniature, et il ne peut plus la revoir une fois partie.
    let (msg, up) = malik.create_view_once(&d.join("m"), &plain, photo()).unwrap();
    let mm = msg.media.as_ref().unwrap();
    assert_eq!(mm.view_once, 1);
    assert!(mm.thumb.is_empty(), "aucune miniature chez l'expéditeur");
    let r2 = d.join("r2.bin");
    fs::copy(&up.path, &r2).unwrap();
    let o = malik.media_uploaded(INES, &msg.id, KEY).unwrap().unwrap();
    assert!(o.urgent);
    assert!(!Path::new(&up.path).exists(), "le chiffré local de l'expéditeur est effacé");
    assert!(malik.open_media(&msg.id).is_err(), "l'expéditeur ne peut pas la revoir");
    assert!(malik.media_gallery(None, 50, None).unwrap().is_empty(), "jamais dans la galerie");

    // Inès la reçoit : pas de miniature, illisible tant qu'elle ne l'ouvre pas.
    let Received::Message(r) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    let rm = r.media.clone().unwrap();
    assert_eq!(rm.view_once, 1);
    assert!(rm.thumb.is_empty(), "la miniature n'est ni envoyée ni gardée");
    let dl = d.join("dl.part");
    fs::copy(&r2, &dl).unwrap();
    assert!(ines.media_downloaded(&r.id, &dl, &d.join("i")).unwrap());
    assert!(ines.open_media(&r.id).is_err(), "pas lisible avant l'ouverture");
    assert!(ines.media_gallery(None, 50, None).unwrap().is_empty(), "jamais dans la galerie");
    let backup = ines.export_backup(&[9; 32]).unwrap();
    let mut fresh = Device::open(&d.join("fresh.db"), &[3; 32]).unwrap();
    let sum = fresh.import_backup(&[9; 32], &backup).unwrap();
    assert_eq!((sum.messages, sum.media), (0, 0), "jamais dans la sauvegarde");

    // Elle l'ouvre : lisible le temps de l'affichage, puis détruite, et Malik est prévenu.
    ines.view_once_begin(&r.id).unwrap();
    assert_eq!(ines.open_media(&r.id).unwrap(), plain);
    let receipt = ines.view_once_done(MALIK, &r.id).unwrap().unwrap();
    assert!(!receipt.urgent, "l'accusé ne réveille pas le téléphone");
    let after = ines.message(&r.id).unwrap().unwrap().media.unwrap();
    assert_eq!((after.view_once, after.state), (2, 4), "ouverte, contenu détruit");
    assert!(ines.open_media(&r.id).is_err(), "une seule fois");
    assert!(ines.view_once_begin(&r.id).is_err(), "impossible de la rouvrir");
    assert!(ines.view_once_done(MALIK, &r.id).unwrap().is_none());
    assert!(ines.r2_trash().unwrap().contains(&KEY.to_owned()), "l'objet R2 part à la corbeille");
    assert!(fs::read_dir(d.join("i")).unwrap().next().is_none(), "plus aucun fichier chez Inès");

    assert_eq!(malik.receive(INES, &receipt.envelope_id, &receipt.envelope).unwrap(), Received::Updated(vec![msg.id.clone()]));
    assert_eq!(malik.message(&msg.id).unwrap().unwrap().media.unwrap().view_once, 2, "Malik voit « Ouverte »");
}

#[test]
fn vue_unique_restee_ouverte_pendant_un_plantage_est_consommee() {
    let dir = tempfile::tempdir().unwrap();
    let d = dir.path();
    let (mut ines, mut malik) = couple(d);
    let (msg, up) = malik.create_view_once(&d.join("m"), &[7u8; 3000], photo()).unwrap();
    let r2 = d.join("r2.bin");
    fs::copy(&up.path, &r2).unwrap();
    let o = malik.media_uploaded(INES, &msg.id, KEY).unwrap().unwrap();
    let Received::Message(r) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    fs::copy(&r2, d.join("dl.part")).unwrap();
    ines.media_downloaded(&r.id, &d.join("dl.part"), &d.join("i")).unwrap();
    ines.view_once_begin(&r.id).unwrap();
    // L'app s'arrête ici ; au redémarrage :
    let out = ines.view_once_finish_pending(MALIK).unwrap();
    assert_eq!(out.len(), 1);
    assert!(ines.open_media(&r.id).is_err());
}

#[test]
fn ma_propre_vue_unique_ne_s_ouvre_pas_chez_moi() {
    let dir = tempfile::tempdir().unwrap();
    let (_, mut malik) = couple(dir.path());
    let (msg, _) = malik.create_view_once(&dir.path().join("m"), &[1u8; 500], photo()).unwrap();
    assert!(malik.view_once_begin(&msg.id).is_err());
}

#[test]
fn une_vue_unique_jamais_ouverte_expire() {
    let dir = tempfile::tempdir().unwrap();
    let d = dir.path();
    let (mut ines, mut malik) = couple(d);
    let (msg, _) = malik.create_view_once(&d.join("m"), &[2u8; 800], photo()).unwrap();
    let o = malik.media_uploaded(INES, &msg.id, KEY).unwrap().unwrap();
    let Received::Message(_) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    assert_eq!(ines.purge_view_once().unwrap(), 0, "pas encore expirée");
}
