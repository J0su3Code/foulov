//! Notre espace : réglages, photos du couple, instants, albums, lettres et capsules, chiffres, sauvegarde.

use std::fs;
use std::path::Path;

use foulov_core::chat::Received;
use foulov_core::chat_media::{KIND_PHOTO, NewMedia};
use foulov_core::device::{Device, LocalBundle, PartnerBundle};

const INES: &str = "ines";
const MALIK: &str = "malik";
const KEY1: &str = "c/0f2c1a6e-1111-4222-8333-444455556666/0123456789abcdef0123456789abcdef";
const KEY2: &str = "c/0f2c1a6e-1111-4222-8333-444455556666/fedcba9876543210fedcba9876543210";

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

/// Inès et Malik, session ouverte dans les deux sens.
fn couple(dir: &Path) -> (Device, Device) {
    let mut ines = Device::open(&dir.join("ines.db"), &[1; 32]).unwrap();
    let mut malik = Device::open(&dir.join("malik.db"), &[2; 32]).unwrap();
    let ib = ines.generate_bundle(5).unwrap();
    malik.generate_bundle(5).unwrap();
    malik.start_session(INES, &view(&ib)).unwrap();
    let (_, o) = malik.send_text(INES, "coucou", None).unwrap();
    ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap();
    (ines, malik)
}

fn deliver(from: &mut Device, to: &mut Device, from_name: &str, o: &foulov_core::chat::Outgoing) -> Received {
    from.outbox_sent(&o.envelope_id).unwrap();
    to.receive(from_name, &o.envelope_id, &o.envelope).unwrap()
}

fn photo() -> NewMedia<'static> {
    NewMedia { kind: KIND_PHOTO, mime: "image/jpeg", width: 1200, height: 800, duration_ms: 0, thumb: b"mini", caption: "", reply_to: None }
}

fn get(d: &Device, k: &str) -> Option<String> {
    d.settings().unwrap().into_iter().find(|s| s.key == k).map(|s| s.value)
}

#[test]
fn reglages_partages_et_personnels() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());

    let o = ines.set_setting(MALIK, "bio", "  Deux cœurs, une seule bulle. ", false).unwrap();
    assert!(!o.urgent, "un réglage ne réveille pas le téléphone");
    assert_eq!(deliver(&mut ines, &mut malik, INES, &o), Received::Profile);
    assert_eq!(get(&malik, "s.bio").as_deref(), Some("Deux cœurs, une seule bulle."));
    assert_eq!(get(&ines, "s.bio").as_deref(), Some("Deux cœurs, une seule bulle."));

    // Personnel : son anniversaire est « p. » chez lui, « me. » chez elle.
    let o = ines.set_setting(MALIK, "birthday", "04-12", true).unwrap();
    deliver(&mut ines, &mut malik, INES, &o);
    assert_eq!(get(&ines, "me.birthday").as_deref(), Some("04-12"));
    assert_eq!(get(&malik, "p.birthday").as_deref(), Some("04-12"));
    assert_eq!(get(&malik, "me.birthday"), None);

    // Valeur invalide refusée à l'envoi ; vide = retirée chez les deux.
    assert!(ines.set_setting(MALIK, "birthday", "31-31", true).is_err());
    assert!(ines.set_setting(MALIK, "bio", "x", true).is_err(), "la bio n'est pas personnelle");
    let o = malik.set_setting(INES, "bio", "", false).unwrap();
    deliver(&mut malik, &mut ines, MALIK, &o);
    assert_eq!(get(&ines, "s.bio"), None);

    // Une ancienne modification arrivée en retard ne l'emporte pas.
    let old = ines.set_setting(MALIK, "story", "Version 1", false).unwrap();
    std::thread::sleep(std::time::Duration::from_millis(3));
    let new = ines.set_setting(MALIK, "story", "Version 2", false).unwrap();
    deliver(&mut ines, &mut malik, INES, &new);
    deliver(&mut ines, &mut malik, INES, &old);
    assert_eq!(get(&malik, "s.story").as_deref(), Some("Version 2"));
}

#[test]
fn photo_du_couple_remplacee_et_retiree() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let plain = vec![42u8; 50_000];

    let up = ines.set_picture(&dir.path().join("i"), "avatar", &plain, "image/jpeg", 800, 800, b"mini").unwrap();
    let p = ines.pictures().unwrap();
    assert_eq!((p.len(), p[0].slot.as_str(), p[0].media.state), (1, "avatar", 0), "visible tout de suite chez elle");
    assert_eq!(ines.open_media(&p[0].media_id).unwrap(), plain);
    fs::copy(&up.path, dir.path().join("r2-1")).unwrap();
    let o = ines.media_uploaded(MALIK, &up.message_id, KEY1).unwrap().unwrap();
    assert_eq!(deliver(&mut ines, &mut malik, INES, &o), Received::Profile);

    let mp = malik.pictures().unwrap();
    assert_eq!((mp.len(), mp[0].from_me, mp[0].media.state), (1, false, 2));
    let todo = malik.pending_downloads().unwrap();
    assert_eq!(todo[0].object_key, KEY1);
    let dl = dir.path().join("dl");
    fs::copy(dir.path().join("r2-1"), &dl).unwrap();
    assert!(malik.media_downloaded(&todo[0].message_id, &dl, &dir.path().join("m")).unwrap());
    assert_eq!(malik.open_media(&mp[0].media_id).unwrap(), plain);
    assert!(malik.media_gallery(None, 50, None).unwrap().is_empty(), "pas dans les souvenirs de la conversation");

    // Malik la remplace : l'ancienne disparaît chez les deux, et Inès retire son fichier de R2.
    let up2 = malik.set_picture(&dir.path().join("m"), "avatar", &[7u8; 1000], "image/jpeg", 10, 10, b"m2").unwrap();
    let o = malik.media_uploaded(INES, &up2.message_id, KEY2).unwrap().unwrap();
    deliver(&mut malik, &mut ines, MALIK, &o);
    let ip = ines.pictures().unwrap();
    assert_eq!((ip.len(), ip[0].from_me, ip[0].media.thumb.as_slice()), (1, false, b"m2".as_slice()));
    assert_eq!(ines.r2_trash().unwrap(), vec![KEY1.to_owned()]);
    ines.r2_trash_done(KEY1).unwrap();
    assert!(ines.r2_trash().unwrap().is_empty());
    assert!(!Path::new(&up.path).exists(), "l'ancien chiffré local est effacé");

    // Photo remplacée pendant son dépôt : rien n'est envoyé, le fichier va à la corbeille.
    let a = ines.set_picture(&dir.path().join("i"), "cover", &[1u8; 100], "image/jpeg", 10, 10, b"a").unwrap();
    let b = ines.set_picture(&dir.path().join("i"), "cover", &[2u8; 100], "image/jpeg", 10, 10, b"b").unwrap();
    assert!(ines.media_uploaded(MALIK, &a.message_id, KEY1).unwrap().is_none());
    assert_eq!(ines.r2_trash().unwrap(), vec![KEY1.to_owned()]);
    let o = ines.media_uploaded(MALIK, &b.message_id, KEY2).unwrap().unwrap();
    deliver(&mut ines, &mut malik, INES, &o);

    // Retirée : chez les deux.
    let o = malik.remove_picture(INES, "cover").unwrap();
    deliver(&mut malik, &mut ines, MALIK, &o);
    assert!(ines.pictures().unwrap().iter().all(|p| p.slot != "cover"));
    assert!(malik.pictures().unwrap().iter().all(|p| p.slot != "cover"));
    assert!(ines.set_picture(&dir.path().join("i"), "inconnu", &[1], "image/jpeg", 1, 1, b"").is_err());
}

#[test]
fn instants_vus_retires_et_cites() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());

    // Texte : part aussitôt et réveille le téléphone.
    let (m, o) = malik.post_text_moment(INES, "  Le même ciel que toi ☀️ ", 3).unwrap();
    assert!(o.urgent);
    assert_eq!(deliver(&mut malik, &mut ines, MALIK, &o), Received::Moments);
    let im = ines.moments().unwrap();
    assert_eq!((im.len(), im[0].text.as_str(), im[0].style, im[0].seen, im[0].from_me), (1, "Le même ciel que toi ☀️", 3, false, false));

    // Vu : Malik le sait, une seule fois.
    let o = ines.see_moment(MALIK, &m.id).unwrap().unwrap();
    assert!(ines.see_moment(MALIK, &m.id).unwrap().is_none());
    assert_eq!(deliver(&mut ines, &mut malik, INES, &o), Received::Moments);
    assert!(malik.moments().unwrap()[0].seen);

    // Réponse : un message qui cite l'instant, chez les deux.
    let (r, o) = ines.reply_to_moment(MALIK, &m.id, "Trop beau 😍").unwrap();
    assert_eq!(r.quote.as_ref().unwrap().text, "Le même ciel que toi ☀️");
    let Received::Message(got) = deliver(&mut ines, &mut malik, INES, &o) else { panic!() };
    assert_eq!(got.quote.unwrap().text, "Le même ciel que toi ☀️");

    // Photo : envoyée une fois déposée.
    let (pm, up) = ines.post_media_moment(&dir.path().join("i"), Some(&[9u8; 5000]), None, photo(), "vivement ce soir").unwrap();
    assert_eq!(pm.media.as_ref().unwrap().state, 0);
    let o = ines.media_uploaded(MALIK, &up.message_id, KEY1).unwrap().unwrap();
    deliver(&mut ines, &mut malik, INES, &o);
    let mm = malik.moments().unwrap();
    assert_eq!(mm.len(), 2);
    assert_eq!(mm[1].media.as_ref().unwrap().state, 2);
    assert!(malik.media_gallery(None, 50, None).unwrap().is_empty(), "un instant n'est pas un souvenir");

    // Retiré par Inès : disparaît chez Malik, et son fichier part de R2.
    let o = ines.delete_moment(MALIK, &pm.id).unwrap().unwrap();
    assert!(malik.delete_moment(INES, &pm.id).unwrap().is_none(), "on ne retire que les siens");
    deliver(&mut ines, &mut malik, INES, &o);
    assert_eq!(malik.moments().unwrap().len(), 1);
    assert!(malik.pending_downloads().unwrap().is_empty());
    assert_eq!(ines.r2_trash().unwrap(), vec![KEY1.to_owned()]);
    assert_eq!(ines.purge_moments().unwrap(), 0, "rien d'expiré");
}

#[test]
fn albums_partages() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let (p1, up) = malik.create_media(&dir.path().join("m"), &[1u8; 300], photo()).unwrap();
    let o = malik.media_uploaded(INES, &p1.id, KEY1).unwrap().unwrap();
    deliver(&mut malik, &mut ines, MALIK, &o);
    let _ = up;

    let (a, o) = ines.save_album(MALIK, None, " Lisbonne 2025 ", &[p1.id.clone()]).unwrap();
    assert_eq!(a.title, "Lisbonne 2025");
    assert_eq!(deliver(&mut ines, &mut malik, INES, &o), Received::Albums);
    assert_eq!(malik.albums().unwrap(), vec![a.clone()]);

    let (_, o) = malik.save_album(INES, Some(&a.id), "Lisbonne ❤️", &[]).unwrap();
    deliver(&mut malik, &mut ines, MALIK, &o);
    let got = ines.albums().unwrap();
    assert_eq!((got[0].title.as_str(), got[0].items.len()), ("Lisbonne ❤️", 0));

    let o = ines.delete_album(MALIK, &a.id).unwrap();
    deliver(&mut ines, &mut malik, INES, &o);
    assert!(malik.albums().unwrap().is_empty());
    assert!(ines.save_album(MALIK, None, "  ", &[]).is_err());
}

#[test]
fn lettres_et_capsules() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());

    let (l, o) = malik.send_letter(INES, "Pour nos 1 000 jours", "Mon cœur,\n\nMille jours.  \n", None).unwrap();
    assert!(o.urgent);
    assert_eq!(deliver(&mut malik, &mut ines, MALIK, &o), Received::Letters);
    let got = &ines.letters().unwrap()[0];
    assert_eq!((got.title.as_str(), got.body.as_str(), got.sealed), ("Pour nos 1 000 jours", "Mon cœur,\n\nMille jours.", false));

    let o = ines.read_letter(MALIK, &l.id).unwrap().unwrap();
    assert!(ines.read_letter(MALIK, &l.id).unwrap().is_none(), "lue une seule fois");
    deliver(&mut ines, &mut malik, INES, &o);
    assert!(malik.letters().unwrap()[0].read_at.is_some());

    // Capsule : arrive tout de suite, mais reste scellée chez les deux jusqu'à la date.
    let later = foulov_now() + 116 * 86_400_000;
    let (c, o) = ines.send_letter(MALIK, "Pour nos 4 ans", "Ouvre-moi le 12 mars.", Some(later)).unwrap();
    assert!(c.sealed && c.body.is_empty());
    deliver(&mut ines, &mut malik, INES, &o);
    let cap = malik.letters().unwrap().into_iter().find(|x| x.id == c.id).unwrap();
    assert!(cap.sealed && cap.body.is_empty() && cap.open_at == Some(later));
    assert!(malik.read_letter(INES, &c.id).unwrap().is_none(), "pas avant la date");
    assert!(ines.letters().unwrap().iter().find(|x| x.id == c.id).unwrap().sealed, "scellée pour elle aussi");

    assert!(ines.send_letter(MALIK, "", "x", None).is_err());
    assert!(ines.send_letter(MALIK, "t", "x", Some(foulov_now() - 1)).is_err(), "pas d'ouverture dans le passé");
    ines.star_letter(&l.id, true).unwrap();
    assert!(ines.letters().unwrap().iter().find(|x| x.id == l.id).unwrap().starred);
}

#[test]
fn chiffres_et_sauvegarde() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let (_, o) = ines.send_text(MALIK, "moi aussi", None).unwrap();
    deliver(&mut ines, &mut malik, INES, &o);
    let s = ines.space_stats(60).unwrap();
    assert_eq!((s.messages, s.flame_days, s.flame_today), (2, 1, true), "écrit tous les deux aujourd'hui");

    let (_, o) = ines.send_letter(MALIK, "Merci", "Pour tout.", None).unwrap();
    deliver(&mut ines, &mut malik, INES, &o);
    let o = ines.set_setting(MALIK, "bio", "Nous", false).unwrap();
    deliver(&mut ines, &mut malik, INES, &o);
    let up = ines.set_picture(&dir.path().join("i"), "avatar", &[3u8; 100], "image/jpeg", 10, 10, b"a").unwrap();
    ines.media_uploaded(MALIK, &up.message_id, KEY1).unwrap().unwrap();
    let (_, _) = ines.post_text_moment(MALIK, "éphémère", 0).unwrap();

    let secret = [5u8; 32];
    let data = ines.export_backup(&secret).unwrap();
    let mut fresh = Device::open(&dir.path().join("neuf.db"), &[9; 32]).unwrap();
    fresh.generate_bundle(2).unwrap();
    let sum = fresh.import_backup(&secret, &data).unwrap();
    assert_eq!(sum.letters, 1);
    assert_eq!(fresh.letters().unwrap()[0].title, "Merci");
    assert_eq!(get(&fresh, "s.bio").as_deref(), Some("Nous"));
    let p = fresh.pictures().unwrap();
    assert_eq!((p.len(), p[0].media.state), (1, 2), "la photo du couple revient, à retélécharger");
    assert!(fresh.moments().unwrap().is_empty(), "les instants ne sont jamais sauvegardés");
}

fn foulov_now() -> i64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).unwrap().as_millis() as i64
}
