//! Stickers (envoi, réception, bibliothèque, favoris) et modification d'un message après l'envoi.

use std::fs;
use std::path::Path;

use foulov_core::chat::Received;
use foulov_core::chat_media::{KIND_STICKER, KIND_VOICE, NewMedia};
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

#[test]
fn sticker_envoye_recu_puis_enregistre_en_favori() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let webp: Vec<u8> = b"RIFF....WEBPVP8L".iter().copied().chain((0..9000u32).map(|i| (i % 253) as u8)).collect();
    let m = NewMedia {
        kind: KIND_STICKER,
        mime: "image/webp",
        width: 512,
        height: 512,
        duration_ms: 0,
        thumb: &webp[..4000],
        caption: "",
        reply_to: None,
    };
    let (msg, up) = malik.create_media(&dir.path().join("m"), &webp, m).unwrap();
    assert_eq!(msg.media.as_ref().unwrap().kind, KIND_STICKER);
    let r2 = dir.path().join("r2.bin");
    fs::copy(&up.path, &r2).unwrap();
    let o = malik.media_uploaded(INES, &msg.id, KEY).unwrap().unwrap();
    assert!(o.urgent, "un sticker mérite une notification");

    let Received::Message(r) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    assert_eq!(r.media.as_ref().unwrap().kind, KIND_STICKER);
    let dl = dir.path().join("dl.part");
    fs::copy(&r2, &dl).unwrap();
    assert!(ines.media_downloaded(&r.id, &dl, &dir.path().join("i")).unwrap());
    let bytes = ines.open_media(&r.id).unwrap();
    assert_eq!(bytes, webp);
    assert!(ines.media_gallery(None, 50, None).unwrap().is_empty(), "un sticker n'est pas un souvenir");

    // Inès l'enregistre, puis le met en favori ; l'enregistrer de nouveau ne crée pas de doublon.
    assert!(ines.sticker_find(&bytes).unwrap().is_none());
    let (id, new) = ines.sticker_add(&bytes, "image/webp", 512, 512).unwrap();
    assert!(new);
    assert_eq!(ines.sticker_add(&bytes, "image/webp", 512, 512).unwrap(), (id.clone(), false));
    ines.sticker_set_favorite(&id, true).unwrap();
    assert_eq!(ines.sticker_find(&bytes).unwrap(), Some((id.clone(), true)));
    let all = ines.stickers().unwrap();
    assert_eq!(all.len(), 1);
    assert!(all[0].favorite);
    assert_eq!(all[0].used_at, 0);
    ines.sticker_used(&id).unwrap();
    assert!(ines.stickers().unwrap()[0].used_at > 0);
    assert_eq!(ines.sticker_data(&id).unwrap().unwrap(), bytes);
    ines.sticker_delete(&id).unwrap();
    assert!(ines.stickers().unwrap().is_empty());
    assert!(ines.sticker_add(b"pas une image", "text/plain", 1, 1).is_err());
}

#[test]
fn message_modifie_par_son_auteur_seulement() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());

    let (m, o) = malik.send_text(INES, "Je t'aime fort", None).unwrap();
    malik.outbox_sent(&o.envelope_id).unwrap();
    let Received::Message(_) = ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap() else { panic!() };
    // Ines répond pour ouvrir la session dans les deux sens.
    let (mine, o2) = ines.send_text(MALIK, "Moi aussi", None).unwrap();
    ines.outbox_sent(&o2.envelope_id).unwrap();
    malik.receive(INES, &o2.envelope_id, &o2.envelope).unwrap();

    let (edited, e) = malik.edit_message(INES, &m.id, "  Je t'aime très fort ❤️ ").unwrap();
    assert_eq!(edited.body, "Je t'aime très fort ❤️");
    assert!(edited.edited_at.is_some());
    assert!(!e.urgent, "une modification ne réveille pas le téléphone");
    assert_eq!(ines.receive(MALIK, &e.envelope_id, &e.envelope).unwrap(), Received::Updated(vec![m.id.clone()]));
    let seen = ines.message(&m.id).unwrap().unwrap();
    assert_eq!(seen.body, "Je t'aime très fort ❤️");
    assert!(seen.edited_at.is_some());

    // Une modification plus ancienne, arrivée en retard, ne remplace pas la plus récente.
    let (_, e1) = malik.edit_message(INES, &m.id, "v1").unwrap();
    std::thread::sleep(std::time::Duration::from_millis(5));
    let (_, e2) = malik.edit_message(INES, &m.id, "v2").unwrap();
    ines.receive(MALIK, &e2.envelope_id, &e2.envelope).unwrap();
    assert_eq!(ines.receive(MALIK, &e1.envelope_id, &e1.envelope).unwrap(), Received::Nothing);
    assert_eq!(ines.message(&m.id).unwrap().unwrap().body, "v2");

    // On ne modifie pas le message de l'autre, ni un texte vidé.
    assert!(malik.edit_message(INES, &mine.id, "piraté").is_err());
    assert!(malik.edit_message(INES, &m.id, "   ").is_err());

    // Un vocal ne se modifie pas.
    let wav = dir.path().join("v.m4a");
    fs::write(&wav, vec![7u8; 5000]).unwrap();
    let voice = NewMedia { kind: KIND_VOICE, mime: "audio/mp4", width: 0, height: 0, duration_ms: 3000, thumb: &[1, 2, 3], caption: "", reply_to: None };
    let (v, _) = malik.create_media_file(&dir.path().join("m"), &wav, voice).unwrap();
    assert!(malik.edit_message(INES, &v.id, "texte").is_err());
}

#[test]
fn une_modification_qui_ment_sur_l_heure_est_refusee() {
    use foulov_core::chat::{Outgoing, pad, pb};
    use prost::Message as _;
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let (m, o) = malik.send_text(INES, "Bonjour", None).unwrap();
    ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap();
    let sent_at = ines.message(&m.id).unwrap().unwrap().sent_at as u64;
    let target = (0..16).map(|i| u8::from_str_radix(&m.id[i * 2..i * 2 + 2], 16).unwrap()).collect::<Vec<_>>();

    // Un téléphone trafiqué fabrique lui-même des modifications avec une heure choisie.
    let mut forged = |n: u8, edited_at: u64| {
        let mut v = vec![1u8];
        pb::Content { body: Some(pb::Body::Edit(pb::Edit { target: target.clone(), body: "réécrit".into(), edited_at })) }
            .encode(&mut v)
            .unwrap();
        let env = malik.encrypt(INES, &pad(v)).unwrap();
        Outgoing { envelope_id: format!("11111111-1111-4111-8111-11111111111{n}"), envelope: env, urgent: false }
    };
    for (n, at) in [(1, 0), (2, sent_at - 1), (3, u64::MAX), (4, sent_at + 16 * 60_000 + 3 * 60_000)] {
        let o = forged(n, at);
        assert_eq!(ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap(), Received::Nothing, "heure {at} refusée");
    }
    assert_eq!(ines.message(&m.id).unwrap().unwrap().body, "Bonjour", "le message n'a pas bougé");
    // Une heure plausible (dans les 15 minutes) passe.
    let o = forged(5, sent_at + 1000);
    assert_eq!(ines.receive(MALIK, &o.envelope_id, &o.envelope).unwrap(), Received::Updated(vec![m.id.clone()]));
}
