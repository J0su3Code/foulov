//! Tests de la messagerie : deux téléphones (Inès et Malik) avec leurs vraies bases SQLCipher,
//! un « serveur » simulé qui transporte les enveloppes, et les cas difficiles du réseau réel :
//! doublons, désordre, coupure entre chiffrement et dépôt, redémarrage de l'app, enveloppe altérée.

use std::collections::VecDeque;
use std::path::Path;

use foulov_core::chat::{ChatMessage, Outgoing, Received, STATUS_DELIVERED, STATUS_PENDING, STATUS_READ, STATUS_SENT};
use foulov_core::device::{Device, Envelope, LocalBundle, PartnerBundle};

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

/// Inès crée l'espace, Malik rejoint : session ouverte des deux côtés, comme dans l'app.
fn couple(dir: &Path) -> (Device, Device) {
    let mut ines = Device::open(&dir.join("ines.db"), &[1; 32]).unwrap();
    let mut malik = Device::open(&dir.join("malik.db"), &[2; 32]).unwrap();
    let ib = ines.generate_bundle(5).unwrap();
    malik.generate_bundle(5).unwrap();
    malik.start_session(INES, &view(&ib)).unwrap();
    (ines, malik)
}

/// Dépose l'enveloppe sur le « serveur » puis confirme l'envoi, comme le fait l'app.
fn deliver(from: &mut Device, out: Outgoing, server: &mut VecDeque<Outgoing>) {
    from.outbox_sent(&out.envelope_id).unwrap();
    server.push_back(out);
}

fn recv(to: &mut Device, partner: &str, o: &Outgoing) -> Received {
    to.receive(partner, &o.envelope_id, &o.envelope).unwrap()
}

fn get(d: &Device, id: &str) -> ChatMessage {
    d.message(id).unwrap().unwrap()
}

#[test]
fn conversation_complete_avec_accuses_et_reactions() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let mut server = VecDeque::new();

    // Malik écrit le premier : son message s'affiche tout de suite chez lui, « en attente ».
    let (m1, o1) = malik.send_text(INES, "  Bonjour mon cœur 🌱  ", None).unwrap();
    assert_eq!(m1.body, "Bonjour mon cœur 🌱", "espaces en trop retirés");
    assert_eq!(get(&malik, &m1.id).status, STATUS_PENDING);
    assert_eq!(malik.outbox().unwrap().len(), 1);
    deliver(&mut malik, o1, &mut server);
    assert_eq!(get(&malik, &m1.id).status, STATUS_SENT);
    assert!(malik.outbox().unwrap().is_empty());

    // Inès reçoit, renvoie « distribué » puis « lu ».
    let Received::Message(r1) = recv(&mut ines, MALIK, &server.pop_front().unwrap()) else { panic!("message attendu") };
    assert_eq!((r1.id.as_str(), r1.body.as_str(), r1.from_me), (m1.id.as_str(), "Bonjour mon cœur 🌱", false));
    assert_eq!(ines.unread().unwrap(), vec![m1.id.clone()]);
    let d = ines.send_receipt(MALIK, &[m1.id.clone()], STATUS_DELIVERED).unwrap().unwrap();
    deliver(&mut ines, d, &mut server);
    assert_eq!(recv(&mut malik, INES, &server.pop_front().unwrap()), Received::Updated(vec![m1.id.clone()]));
    assert_eq!(get(&malik, &m1.id).status, STATUS_DELIVERED);

    let r = ines.send_receipt(MALIK, &[m1.id.clone()], STATUS_READ).unwrap().unwrap();
    assert!(ines.unread().unwrap().is_empty(), "lu chez Inès dès l'envoi de l'accusé");
    deliver(&mut ines, r, &mut server);
    recv(&mut malik, INES, &server.pop_front().unwrap());
    assert_eq!(get(&malik, &m1.id).status, STATUS_READ);

    // Un « distribué » arrivé en retard ne fait jamais reculer le statut.
    let late = ines.send_receipt(MALIK, &[m1.id.clone()], STATUS_DELIVERED).unwrap().unwrap();
    assert_eq!(recv(&mut malik, INES, &late), Received::Updated(vec![]));
    assert_eq!(get(&malik, &m1.id).status, STATUS_READ);

    // Réponse citée et réaction.
    let (m2, o2) = ines.send_text(MALIK, "Coucou toi", Some(&m1.id)).unwrap();
    deliver(&mut ines, o2, &mut server);
    let Received::Message(r2) = recv(&mut malik, INES, &server.pop_front().unwrap()) else { panic!() };
    assert_eq!(r2.reply_to.as_deref(), Some(m1.id.as_str()));

    let re = malik.send_reaction(INES, &m2.id, "❤️").unwrap();
    assert_eq!(get(&malik, &m2.id).my_reaction.as_deref(), Some("❤️"));
    assert_eq!(recv(&mut ines, MALIK, &re), Received::Updated(vec![m2.id.clone()]));
    assert_eq!(get(&ines, &m2.id).their_reaction.as_deref(), Some("❤️"));
    let un = malik.send_reaction(INES, &m2.id, "").unwrap();
    recv(&mut ines, MALIK, &un);
    assert_eq!(get(&ines, &m2.id).their_reaction, None, "réaction retirée");

    // Historique par pages, du plus récent au plus ancien, identique des deux côtés.
    let page = ines.messages(None, 1).unwrap();
    assert_eq!(page[0].id, m2.id);
    let next = ines.messages(Some((page[0].sent_at, page[0].id.clone())), 10).unwrap();
    assert_eq!(next.iter().map(|m| m.id.clone()).collect::<Vec<_>>(), vec![m1.id.clone()]);
    assert_eq!(malik.messages(None, 10).unwrap().len(), 2);
}

#[test]
fn une_enveloppe_livree_deux_fois_ne_compte_qu_une_fois() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let (_, o) = malik.send_text(INES, "Une seule fois", None).unwrap();
    assert!(matches!(recv(&mut ines, MALIK, &o), Received::Message(_)));
    assert_eq!(recv(&mut ines, MALIK, &o), Received::Nothing);
    assert_eq!(ines.messages(None, 10).unwrap().len(), 1);
}

#[test]
fn messages_dans_le_desordre() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    // Session confirmée dans les deux sens, puis trois messages qui arrivent à l'envers.
    let (_, o) = malik.send_text(INES, "un", None).unwrap();
    recv(&mut ines, MALIK, &o);
    let (_, o) = ines.send_text(MALIK, "reçu", None).unwrap();
    recv(&mut malik, INES, &o);
    let outs: Vec<_> = ["a", "b", "c"].iter().map(|t| malik.send_text(INES, t, None).unwrap().1).collect();
    for o in outs.iter().rev() {
        assert!(matches!(recv(&mut ines, MALIK, o), Received::Message(_)));
    }
    let bodies: Vec<_> = ines.messages(None, 10).unwrap().into_iter().filter(|m| !m.from_me).map(|m| m.body).collect();
    assert_eq!(bodies, ["c", "b", "a", "un"], "ordre d'envoi rétabli à l'affichage");
}

#[test]
fn coupure_reseau_puis_redemarrage_la_boite_d_envoi_survit() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let (m, _lost) = malik.send_text(INES, "Envoyé dans le métro", None).unwrap();
    drop(malik); // l'app est tuée avant le dépôt sur le serveur

    let mut malik = Device::open(&dir.path().join("malik.db"), &[2; 32]).unwrap();
    let pending = malik.outbox().unwrap();
    assert_eq!(pending.len(), 1, "l'enveloppe chiffrée attend toujours");
    assert_eq!(get(&malik, &m.id).status, STATUS_PENDING);
    // Renvoyée telle quelle (même identifiant) : lisible, et un éventuel doublon serait ignoré.
    let Received::Message(r) = recv(&mut ines, MALIK, &pending[0]) else { panic!() };
    assert_eq!(r.body, "Envoyé dans le métro");
    assert_eq!(recv(&mut ines, MALIK, &pending[0]), Received::Nothing);
    malik.outbox_sent(&pending[0].envelope_id).unwrap();
    assert_eq!(get(&malik, &m.id).status, STATUS_SENT);
}

#[test]
fn une_enveloppe_alteree_est_ecartee_sans_bloquer_la_suite() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let (_, o) = malik.send_text(INES, "premier", None).unwrap();
    recv(&mut ines, MALIK, &o);
    let (_, o) = ines.send_text(MALIK, "réponse", None).unwrap();
    recv(&mut malik, INES, &o);
    // Session confirmée : messages « courants » (type 2), entièrement authentifiés.
    let (_, good) = malik.send_text(INES, "altéré", None).unwrap();
    assert_eq!(good.envelope.kind, 2);
    for pos in [good.envelope.body.len() / 2, good.envelope.body.len() - 3] {
        let mut bad = good.clone();
        bad.envelope_id = format!("00000000-0000-4000-8000-{pos:012}");
        bad.envelope.body[pos] ^= 1; // un bit change en route : l'authentification échoue
        assert_eq!(recv(&mut ines, MALIK, &bad), Received::Rejected, "octet {pos}");
        assert_eq!(recv(&mut ines, MALIK, &bad), Received::Nothing, "écartée une fois pour toutes");
    }
    // L'original, lui, passe toujours.
    assert!(matches!(recv(&mut ines, MALIK, &good), Received::Message(_)));
    let (_, o) = malik.send_text(INES, "suivant", None).unwrap();
    let Received::Message(r) = recv(&mut ines, MALIK, &o) else { panic!("la suite doit passer") };
    assert_eq!(r.body, "suivant");
    let junk = Outgoing { envelope_id: "00000000-0000-4000-8000-000000000000".into(), envelope: Envelope { kind: 2, body: vec![1, 2, 3] } };
    assert_eq!(recv(&mut ines, MALIK, &junk), Received::Rejected);
}

#[test]
fn la_taille_chiffree_ne_trahit_pas_la_longueur_du_message() {
    let dir = tempfile::tempdir().unwrap();
    let (mut ines, mut malik) = couple(dir.path());
    let (_, o) = malik.send_text(INES, "x", None).unwrap();
    recv(&mut ines, MALIK, &o);
    let (_, o) = ines.send_text(MALIK, "ok", None).unwrap();
    recv(&mut malik, INES, &o);
    let a = malik.send_text(INES, "oui", None).unwrap().1.envelope.body.len();
    let b = malik.send_text(INES, "Je t'aime plus que tout au monde, tu le sais ?", None).unwrap().1.envelope.body.len();
    let r = malik.send_receipt(INES, &[malik.messages(None, 1).unwrap()[0].id.clone()], STATUS_READ);
    assert!(r.is_ok());
    assert_eq!(a, b, "même taille chiffrée pour 3 et 47 caractères");
}

#[test]
fn messages_invalides_refuses_a_l_envoi() {
    let dir = tempfile::tempdir().unwrap();
    let (_, mut malik) = couple(dir.path());
    assert!(malik.send_text(INES, "   ", None).is_err());
    assert!(malik.send_text(INES, &"a".repeat(16 * 1024 + 1), None).is_err());
    assert!(malik.send_text(INES, "ok", Some("pas-un-identifiant")).is_err());
    assert!(malik.outbox().unwrap().is_empty(), "rien n'est chiffré ni mis en file en cas de refus");
    assert!(malik.messages(None, 10).unwrap().is_empty());
}

/// Analyse : pour chaque octet d'une enveloppe, on modifie un bit et on regarde ce que le destinataire en fait.
/// Propriété exigée : jamais un contenu différent de l'original.
#[test]
#[ignore = "analyse longue, lancée à la demande"]
fn analyse_alteration_octet_par_octet() {
    // 3 : premier message ; 30 : message PreKey suivant (session déjà ouverte chez Inès) ; 2 : message courant.
    for case in [3u8, 30, 2] {
        let kind = if case == 2 { 2 } else { 3 };
        let dir = tempfile::tempdir().unwrap();
        let (mut ines, mut malik) = couple(dir.path());
        if case == 30 {
            let (_, o) = malik.send_text(INES, "x", None).unwrap();
            recv(&mut ines, MALIK, &o);
        }
        if case == 2 {
            let (_, o) = malik.send_text(INES, "x", None).unwrap();
            recv(&mut ines, MALIK, &o);
            let (_, o) = ines.send_text(MALIK, "y", None).unwrap();
            recv(&mut malik, INES, &o);
        }
        let (_, o) = malik.send_text(INES, "original", None).unwrap();
        assert_eq!(o.envelope.kind, kind);
        let snapshot = dir.path().join("ines.db");
        let mut accepted = Vec::new();
        for i in 0..o.envelope.body.len() {
            let copy = dir.path().join(format!("c{i}.db"));
            std::fs::copy(&snapshot, &copy).unwrap();
            let _ = std::fs::copy(dir.path().join("ines.db-wal"), dir.path().join(format!("c{i}.db-wal")));
            let mut d = Device::open(&copy, &[1; 32]).unwrap();
            let mut bad = o.clone();
            bad.envelope.body[i] ^= 1;
            if let Ok(Received::Message(m)) = d.receive(MALIK, &bad.envelope_id, &bad.envelope) {
                assert_eq!(m.body, "original", "octet {i} : contenu modifié accepté !");
                accepted.push(i);
            }
        }
        // Plages contiguës, pour un rapport lisible.
        let mut ranges: Vec<(usize, usize)> = Vec::new();
        for &i in &accepted {
            match ranges.last_mut() {
                Some((_, e)) if *e + 1 == i => *e = i,
                _ => ranges.push((i, i)),
            }
        }
        // Attendu : seuls des champs d'acheminement non authentifiés par conception (version, identifiants de
        // pré-clés) et, quand la session existe déjà, le chiffré ML-KEM devenu inutile. Le contenu, lui, est intact.
        println!("cas {case} : {} octets, altérations sans effet sur le contenu : {ranges:?}", o.envelope.body.len());
    }
}
