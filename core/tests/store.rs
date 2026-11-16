//! Tests du stockage local chiffré (SQLCipher) avec de vraies sessions Signal.

use std::time::SystemTime;

use foulov_core::libsignal_protocol::*;
use foulov_core::store::{Store, StoreError};
use futures_util::FutureExt;
use rand::TryRngCore as _;
use rand::rngs::OsRng;

const DB_KEY: [u8; 32] = [7u8; 32];

fn device() -> DeviceId {
    DeviceId::new(1).unwrap()
}

fn new_store(path: &std::path::Path) -> Store {
    let s = Store::open(path, &DB_KEY).unwrap();
    let mut rng = OsRng.unwrap_err();
    s.initialize_identity(&IdentityKeyPair::generate(&mut rng), 1234).unwrap();
    s
}

/// Ce que le téléphone publie sur le serveur (clés publiques), les clés privées restant dans la base chiffrée.
fn publish(store: &mut Store) -> PreKeyBundle {
    async {
        let mut rng = OsRng.unwrap_err();
        let id = store.identity.get_identity_key_pair().await.unwrap();
        let pre = KeyPair::generate(&mut rng);
        let signed = KeyPair::generate(&mut rng);
        let kyber = kem::KeyPair::generate(kem::KeyType::Kyber1024, &mut rng);
        let ssig = id.private_key().calculate_signature(&signed.public_key.serialize(), &mut rng).unwrap();
        let ksig = id.private_key().calculate_signature(&kyber.public_key.serialize(), &mut rng).unwrap();
        store.prekeys.save_pre_key(1.into(), &PreKeyRecord::new(1.into(), &pre)).await.unwrap();
        store
            .signed_prekeys
            .save_signed_pre_key(1.into(), &SignedPreKeyRecord::new(1.into(), Timestamp::from_epoch_millis(1), &signed, &ssig))
            .await
            .unwrap();
        store
            .kyber_prekeys
            .save_kyber_pre_key(1.into(), &KyberPreKeyRecord::new(1.into(), Timestamp::from_epoch_millis(1), &kyber, &ksig))
            .await
            .unwrap();
        PreKeyBundle::new(
            store.identity.get_local_registration_id().await.unwrap(),
            device(),
            Some((1.into(), pre.public_key)),
            1.into(),
            signed.public_key,
            ssig.to_vec(),
            1.into(),
            kyber.public_key.clone(),
            ksig.to_vec(),
            *id.identity_key(),
        )
        .unwrap()
    }
    .now_or_never()
    .unwrap()
}

fn send(s: &mut Store, to: &ProtocolAddress, from: &ProtocolAddress, text: &str) -> CiphertextMessage {
    let mut rng = OsRng.unwrap_err();
    message_encrypt(text.as_bytes(), to, from, &mut s.sessions, &mut s.identity, SystemTime::now(), &mut rng)
        .now_or_never()
        .unwrap()
        .unwrap()
}

fn recv(s: &mut Store, from: &ProtocolAddress, to: &ProtocolAddress, wire: &[u8], kind: CiphertextMessageType) -> Result<String, SignalProtocolError> {
    let msg = match kind {
        CiphertextMessageType::PreKey => CiphertextMessage::PreKeySignalMessage(PreKeySignalMessage::try_from(wire).unwrap()),
        _ => CiphertextMessage::SignalMessage(SignalMessage::try_from(wire).unwrap()),
    };
    let mut rng = OsRng.unwrap_err();
    message_decrypt(
        &msg,
        from,
        to,
        &mut s.sessions,
        &mut s.identity,
        &mut s.prekeys,
        &s.signed_prekeys,
        &mut s.kyber_prekeys,
        &mut rng,
    )
    .now_or_never()
    .unwrap()
    .map(|b| String::from_utf8(b).unwrap())
}

fn start(ines: &mut Store, malik_bundle: &PreKeyBundle, ines_a: &ProtocolAddress, malik_a: &ProtocolAddress) {
    let mut rng = OsRng.unwrap_err();
    initiate_session(malik_a, ines_a, &mut ines.sessions, &mut ines.identity, malik_bundle, SystemTime::now(), &mut rng)
        .now_or_never()
        .unwrap()
        .unwrap();
}

#[test]
fn la_conversation_survit_a_la_fermeture_de_l_app() {
    let dir = tempfile::tempdir().unwrap();
    let (ia, ma) = (ProtocolAddress::new("ines".into(), device()), ProtocolAddress::new("malik".into(), device()));
    let mut ines = new_store(&dir.path().join("ines.db"));
    let malik_path = dir.path().join("malik.db");
    let mut malik = new_store(&malik_path);
    let bundle = publish(&mut malik);
    start(&mut ines, &bundle, &ia, &ma);

    let c = send(&mut ines, &ma, &ia, "Elles ont fleuri sur le balcon !!");
    assert_eq!(recv(&mut malik, &ia, &ma, &c.serialize(), c.message_type()).unwrap(), "Elles ont fleuri sur le balcon !!");

    // Malik ferme l'app, puis la rouvre : la session est relue depuis la base chiffrée.
    drop(malik);
    let mut malik = Store::open(&malik_path, &DB_KEY).unwrap();
    assert!(malik.has_identity().unwrap());
    let r = send(&mut malik, &ia, &ma, "Je viens de la voir");
    assert_eq!(recv(&mut ines, &ma, &ia, &r.serialize(), r.message_type()).unwrap(), "Je viens de la voir");
    for i in 0..10 {
        let c = send(&mut ines, &ma, &ia, &format!("m{i}"));
        assert_eq!(recv(&mut malik, &ia, &ma, &c.serialize(), c.message_type()).unwrap(), format!("m{i}"));
    }
}

#[test]
fn mauvaise_cle_de_base_refusee() {
    let dir = tempfile::tempdir().unwrap();
    let p = dir.path().join("x.db");
    drop(new_store(&p));
    let mut wrong = DB_KEY;
    wrong[31] ^= 1;
    assert!(matches!(Store::open(&p, &wrong), Err(StoreError::WrongKeyOrCorrupted)));
    assert!(Store::open(&p, &DB_KEY).is_ok());
}

#[test]
fn le_fichier_sur_disque_est_illisible() {
    let dir = tempfile::tempdir().unwrap();
    let p = dir.path().join("x.db");
    let mut s = new_store(&p);
    let _ = publish(&mut s);
    drop(s);
    let mut bytes = std::fs::read(&p).unwrap();
    if let Ok(wal) = std::fs::read(dir.path().join("x.db-wal")) {
        bytes.extend(wal);
    }
    assert!(!bytes.starts_with(b"SQLite format 3"), "l'en-tête SQLite ne doit pas apparaître");
    for needle in [&b"sessions"[..], b"identities", b"kyber_prekeys", b"CREATE TABLE"] {
        assert!(!bytes.windows(needle.len()).any(|w| w == needle), "{:?} visible en clair", String::from_utf8_lossy(needle));
    }
}

#[test]
fn une_cle_de_partenaire_qui_change_est_bloquee_jusqu_a_acceptation() {
    let dir = tempfile::tempdir().unwrap();
    let (ia, ma) = (ProtocolAddress::new("ines".into(), device()), ProtocolAddress::new("malik".into(), device()));
    let mut ines = new_store(&dir.path().join("ines.db"));
    let mut malik = new_store(&dir.path().join("malik.db"));
    let b = publish(&mut malik);
    start(&mut ines, &b, &ia, &ma);
    let c = send(&mut ines, &ma, &ia, "coucou");
    recv(&mut malik, &ia, &ma, &c.serialize(), c.message_type()).unwrap();
    ines.mark_verified(&ma).unwrap();
    assert!(ines.is_verified(&ma).unwrap());

    // Malik change de téléphone : nouvelle identité. Inès ne doit pas pouvoir lui écrire sans le savoir.
    let mut malik2 = new_store(&dir.path().join("malik2.db"));
    let b2 = publish(&mut malik2);
    let mut rng = OsRng.unwrap_err();
    let res = initiate_session(&ma, &ia, &mut ines.sessions, &mut ines.identity, &b2, SystemTime::now(), &mut rng).now_or_never().unwrap();
    assert!(matches!(res, Err(SignalProtocolError::UntrustedIdentity(_))), "changement de clé non signalé : {res:?}");

    // Inès accepte le changement (après avoir revérifié les symboles) : la clé repart « non vérifiée ».
    ines.accept_identity_change(&ma, b2.identity_key().unwrap()).unwrap();
    assert!(!ines.is_verified(&ma).unwrap());
    start(&mut ines, &b2, &ia, &ma);
    let c = send(&mut ines, &ma, &ia, "c'est bien toi ?");
    assert_eq!(recv(&mut malik2, &ia, &ma, &c.serialize(), c.message_type()).unwrap(), "c'est bien toi ?");
}

#[test]
fn un_premier_message_rejoue_est_refuse() {
    let dir = tempfile::tempdir().unwrap();
    let (ia, ma) = (ProtocolAddress::new("ines".into(), device()), ProtocolAddress::new("malik".into(), device()));
    let mut ines = new_store(&dir.path().join("ines.db"));
    let mut malik = new_store(&dir.path().join("malik.db"));
    let b = publish(&mut malik);
    start(&mut ines, &b, &ia, &ma);
    let c = send(&mut ines, &ma, &ia, "une seule fois");
    let wire = c.serialize().to_vec();
    assert!(recv(&mut malik, &ia, &ma, &wire, c.message_type()).is_ok());
    // Un intermédiaire renvoie exactement le même message.
    assert!(recv(&mut malik, &ia, &ma, &wire, c.message_type()).is_err(), "un message rejoué ne doit pas être accepté");
}
