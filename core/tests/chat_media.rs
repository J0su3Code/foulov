//! Photos dans la conversation : deux téléphones, un « R2 » simulé (un dossier), et les cas difficiles :
//! fichier altéré sur le serveur, app arrêtée avant l'envoi, nom d'objet suspect.

use std::fs;
use std::path::Path;

use foulov_core::chat::{Received, STATUS_PENDING, STATUS_SENT};
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

fn photo(caption: &str) -> NewMedia<'_> {
    NewMedia {
        kind: KIND_PHOTO,
        mime: "image/jpeg",
        width: 1600,
        height: 1200,
        duration_ms: 0,
        thumb: b"miniature-jpeg",
        caption,
        reply_to: None,
    }
}

#[test]
fn photo_envoyee_recue_verifiee_et_ouverte() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let plain: Vec<u8> = (0..300_000u32).map(|i| (i * 7 % 251) as u8).collect();

    // Malik : la photo est chiffrée et apparaît tout de suite, « en attente ».
    let (msg, up) = malik.create_media(&dir.path().join("m-media"), &plain, photo("  Les tulipes 🌷 ")).unwrap();
    assert_eq!(msg.body, "Les tulipes 🌷");
    assert_eq!(msg.status, STATUS_PENDING);
    assert_eq!(msg.media.as_ref().unwrap().state, 0);
    let on_disk = fs::read(&up.path).unwrap();
    assert_eq!(on_disk.len() as u64, up.size);
    assert!(!on_disk.windows(64).any(|w| w == &plain[1000..1064]), "jamais en clair sur le téléphone");
    assert_eq!(malik.open_media(&msg.id).unwrap(), plain, "Malik revoit sa photo avant même l'envoi");

    // Dépôt sur « R2 », puis message chiffré au partenaire.
    let r2 = dir.path().join("r2.bin");
    fs::copy(&up.path, &r2).unwrap();
    let o = malik.media_uploaded(INES, &msg.id, KEY).unwrap();
    assert!(o.urgent, "une photo mérite une notification");
    malik.outbox_sent(&o.envelope_id).unwrap();
    assert_eq!(malik.message(&msg.id).unwrap().unwrap().status, STATUS_SENT);
    assert!(malik.pending_uploads().unwrap().is_empty());

    // Inès : la miniature tout de suite, puis le téléchargement vérifié et l'ouverture en mémoire.
    let Received::Message(r) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    let m = r.media.unwrap();
    assert_eq!((m.state, m.width, m.thumb.as_slice()), (2, 1600, b"miniature-jpeg".as_slice()));
    let todo = ines.pending_downloads().unwrap();
    assert_eq!(todo.len(), 1);
    assert_eq!(todo[0].object_key, KEY);
    let dl = dir.path().join("dl.part");
    fs::copy(&r2, &dl).unwrap();
    assert!(ines.media_downloaded(&r.id, &dl, &dir.path().join("i-media")).unwrap());
    assert!(ines.pending_downloads().unwrap().is_empty());
    assert_eq!(ines.open_media(&r.id).unwrap(), plain);
    assert_eq!(ines.message(&r.id).unwrap().unwrap().media.unwrap().state, 1);
}

#[test]
fn un_fichier_altere_sur_le_serveur_est_refuse() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let (msg, up) = malik.create_media(&dir.path().join("m"), &[42u8; 5000], photo("")).unwrap();
    let o = malik.media_uploaded(INES, &msg.id, KEY).unwrap();
    let Received::Message(r) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    let mut bad = fs::read(&up.path).unwrap();
    bad[100] ^= 1;
    let dl = dir.path().join("dl.part");
    fs::write(&dl, &bad).unwrap();
    assert!(!ines.media_downloaded(&r.id, &dl, &dir.path().join("i")).unwrap());
    assert!(!dl.exists(), "fichier suspect effacé");
    assert_eq!(ines.message(&r.id).unwrap().unwrap().media.unwrap().state, 3, "marqué illisible");
    assert!(ines.open_media(&r.id).is_err());
}

#[test]
fn app_arretee_avant_l_envoi_puis_reprise() {
    let dir = tempfile::tempdir().unwrap();
    let (_, mut malik) = couple(dir.path());
    let (msg, up) = malik.create_media(&dir.path().join("m"), &[7u8; 2000], photo("métro")).unwrap();
    drop(malik);
    let mut malik = Device::open(&dir.path().join("malik.db"), &[2; 32]).unwrap();
    assert_eq!(malik.pending_uploads().unwrap(), vec![up.clone()]);
    malik.media_uploaded(INES, &msg.id, KEY).unwrap();
    assert!(malik.pending_uploads().unwrap().is_empty());
    assert!(malik.media_uploaded(INES, &msg.id, KEY).is_err(), "jamais envoyé deux fois");
}

#[test]
fn contenus_suspects_refuses() {
    let dir = tempfile::tempdir().unwrap();
    let (_, mut malik) = couple(dir.path());
    let m = dir.path().join("m");
    assert!(malik.create_media(&m, &[], photo("")).is_err(), "fichier vide");
    let mut p = photo("");
    p.mime = "application/x-sh";
    assert!(malik.create_media(&m, &[1], p).is_err(), "type non autorisé");
    let mut p = photo("");
    p.mime = "video/mp4";
    assert!(malik.create_media(&m, &[1], p).is_err(), "photo déclarée en vidéo");
    let big = vec![0u8; 70 * 1024];
    let mut p = photo("");
    p.thumb = &big;
    assert!(malik.create_media(&m, &[1], p).is_err(), "miniature trop lourde");
    let (msg, _) = malik.create_media(&m, &[1, 2, 3], photo("")).unwrap();
    assert!(malik.media_uploaded(INES, &msg.id, "c/../../secret").is_err(), "nom d'objet suspect");
}

#[test]
fn video_chiffree_depuis_un_fichier_puis_lue_par_morceaux() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let plain: Vec<u8> = (0..1_000_000u32).map(|i| (i % 249) as u8).collect();
    let src = dir.path().join("video.mp4");
    fs::write(&src, &plain).unwrap();
    let mut v = photo("Notre balade");
    v.kind = foulov_core::chat_media::KIND_VIDEO;
    v.mime = "video/mp4";
    v.duration_ms = 12_000;
    let (msg, up) = malik.create_media_file(&dir.path().join("m"), &src, v).unwrap();
    assert_eq!(malik.media_len(&msg.id).unwrap(), plain.len() as u64);
    let o = malik.media_uploaded(INES, &msg.id, KEY).unwrap();

    let Received::Message(r) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    assert_eq!(r.media.as_ref().unwrap().duration_ms, 12_000);
    let dl = dir.path().join("dl.part");
    fs::copy(&up.path, &dl).unwrap();
    assert!(ines.media_downloaded(&r.id, &dl, &dir.path().join("i")).unwrap());
    // Lecture à la manière d'un lecteur vidéo : des plages successives et des sauts.
    assert_eq!(ines.media_read(&r.id, 0, 4096).unwrap(), &plain[..4096]);
    assert_eq!(ines.media_read(&r.id, 700_000, 300_000).unwrap(), &plain[700_000..]);
    assert_eq!(ines.media_read(&r.id, 123_457, 65_536).unwrap(), &plain[123_457..123_457 + 65_536]);
    assert!(ines.media_read(&r.id, 2_000_000, 10).unwrap().is_empty());
}

#[test]
fn galerie_des_saisons_par_pages_et_par_type() {
    let dir = tempfile::tempdir().unwrap();
    let (_, mut malik) = couple(dir.path());
    let m = dir.path().join("m");
    let mut ids = Vec::new();
    for i in 0..5u8 {
        let mut p = photo("");
        if i % 2 == 1 {
            p.kind = foulov_core::chat_media::KIND_VIDEO;
            p.mime = "video/mp4";
        }
        ids.push(malik.create_media(&m, &[i + 1; 100], p).unwrap().0.id);
    }
    malik.send_text(INES, "un mot, pas un média", None).unwrap();
    let all = malik.media_gallery(None, 10, None).unwrap();
    assert_eq!(all.iter().map(|x| x.id.clone()).collect::<Vec<_>>(), ids.iter().rev().cloned().collect::<Vec<_>>());
    assert_eq!(malik.media_gallery(None, 10, Some(2)).unwrap().len(), 2, "vidéos seulement");
    assert_eq!(malik.media_gallery(None, 10, Some(1)).unwrap().len(), 3, "photos seulement");
    let first = malik.media_gallery(None, 2, None).unwrap();
    let next = malik.media_gallery(Some((first[1].sent_at, first[1].id.clone())), 10, None).unwrap();
    assert_eq!(next.len(), 3, "page suivante sans doublon");
}

#[test]
fn supprimer_pour_nous_deux_et_pour_moi() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    // Une photo de Malik, reçue et téléchargée par Inès.
    let (msg, up) = malik.create_media(&dir.path().join("m"), &[5u8; 4000], photo("oups")).unwrap();
    let o = malik.media_uploaded(INES, &msg.id, KEY).unwrap();
    let Received::Message(r) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    let dl = dir.path().join("dl.part");
    fs::copy(&up.path, &dl).unwrap();
    ines.media_downloaded(&r.id, &dl, &dir.path().join("i")).unwrap();
    let ines_file = dir.path().join("i").join(format!("{}.flm", r.id));
    assert!(ines_file.exists());

    // Inès ne peut pas supprimer pour les deux un message de Malik.
    assert!(ines.delete_for_both(MALIK, &r.id).is_err());

    // Malik supprime pour les deux : son fichier local disparaît, l'objet R2 à effacer est indiqué.
    let (del, key) = malik.delete_for_both(INES, &msg.id).unwrap();
    assert_eq!(key.as_deref(), Some(KEY));
    assert!(!del.urgent, "une suppression ne réveille pas le téléphone");
    assert!(!Path::new(&up.path).exists());
    let gone = malik.message(&msg.id).unwrap().unwrap();
    assert!(gone.deleted && gone.body.is_empty() && gone.media.is_none());

    // Chez Inès : texte, photo et fichier chiffré local effacés, trace « supprimé ».
    assert_eq!(ines.receive(MALIK, &del.envelope_id, &del.envelope).unwrap(), Received::Updated(vec![r.id.clone()]));
    let m = ines.message(&r.id).unwrap().unwrap();
    assert!(m.deleted && m.body.is_empty() && m.media.is_none());
    assert!(!ines_file.exists(), "fichier local effacé");
    assert!(ines.media_gallery(None, 10, None).unwrap().is_empty(), "plus dans les Saisons");
    assert!(ines.open_media(&r.id).is_err());

    // « Pour moi » : un message du partenaire, effacé seulement ici.
    let (t, o) = malik.send_text(INES, "à garder chez Malik", None).unwrap();
    ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap();
    assert!(ines.delete_for_me(&t.id).unwrap());
    assert!(ines.message(&t.id).unwrap().unwrap().deleted);
    assert!(!malik.message(&t.id).unwrap().unwrap().deleted);
    // Un envoi pas encore parti est annulé par « pour moi ».
    let (t2, _) = malik.send_text(INES, "finalement non", None).unwrap();
    let before = malik.outbox().unwrap().len();
    malik.delete_for_me(&t2.id).unwrap();
    assert_eq!(malik.outbox().unwrap().len(), before - 1);
}
