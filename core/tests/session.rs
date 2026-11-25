//! Test d'intégration : deux téléphones établissent une session Signal post-quantique (PQXDH,
//! ML-KEM-1024) puis échangent des messages dans les deux sens, comme Inès et Malik.

use std::time::SystemTime;

use foulov_core::libsignal_protocol::*;
use futures_util::FutureExt;
use rand::TryRngCore as _;
use rand::rngs::OsRng;

const KYBER_AWARE_MESSAGE_VERSION: u32 = 4;

fn new_store() -> InMemSignalProtocolStore {
    let mut rng = OsRng.unwrap_err();
    let identity = IdentityKeyPair::generate(&mut rng);
    InMemSignalProtocolStore::new(identity, 1).expect("store")
}

/// Publie les clés publiques d'un téléphone (ce qui part sur le serveur) et garde les privées localement.
fn publish_bundle(store: &mut InMemSignalProtocolStore, device: DeviceId) -> PreKeyBundle {
    let mut rng = OsRng.unwrap_err();
    let identity = store.get_identity_key_pair().now_or_never().unwrap().unwrap();
    let pre = KeyPair::generate(&mut rng);
    let signed = KeyPair::generate(&mut rng);
    let kyber = kem::KeyPair::generate(kem::KeyType::Kyber1024, &mut rng);
    let signed_sig = identity.private_key().calculate_signature(&signed.public_key.serialize(), &mut rng).unwrap();
    let kyber_sig = identity.private_key().calculate_signature(&kyber.public_key.serialize(), &mut rng).unwrap();

    store.save_pre_key(1.into(), &PreKeyRecord::new(1.into(), &pre)).now_or_never().unwrap().unwrap();
    store
        .save_signed_pre_key(1.into(), &SignedPreKeyRecord::new(1.into(), Timestamp::from_epoch_millis(1), &signed, &signed_sig))
        .now_or_never()
        .unwrap()
        .unwrap();
    store
        .save_kyber_pre_key(1.into(), &KyberPreKeyRecord::new(1.into(), Timestamp::from_epoch_millis(1), &kyber, &kyber_sig))
        .now_or_never()
        .unwrap()
        .unwrap();

    PreKeyBundle::new(
        1,
        device,
        Some((1.into(), pre.public_key)),
        1.into(),
        signed.public_key,
        signed_sig.to_vec(),
        1.into(),
        kyber.public_key.clone(),
        kyber_sig.to_vec(),
        *identity.identity_key(),
    )
    .unwrap()
}

async fn encrypt(store: &mut InMemSignalProtocolStore, to: &ProtocolAddress, from: &ProtocolAddress, msg: &[u8]) -> CiphertextMessage {
    let mut rng = OsRng.unwrap_err();
    message_encrypt(msg, to, from, &mut store.session_store, &mut store.identity_store, SystemTime::now(), &mut rng)
        .await
        .unwrap()
}

async fn decrypt(store: &mut InMemSignalProtocolStore, from: &ProtocolAddress, to: &ProtocolAddress, msg: &CiphertextMessage) -> Vec<u8> {
    let mut rng = OsRng.unwrap_err();
    message_decrypt(
        msg,
        from,
        to,
        &mut store.session_store,
        &mut store.identity_store,
        &mut store.pre_key_store,
        &store.signed_pre_key_store,
        &mut store.kyber_pre_key_store,
        &mut rng,
    )
    .await
    .unwrap()
}

#[test]
fn ines_et_malik_echangent_en_post_quantique() {
    async {
        let device = DeviceId::new(1).unwrap();
        let ines = ProtocolAddress::new("ines".into(), device);
        let malik = ProtocolAddress::new("malik".into(), device);
        let mut ines_store = new_store();
        let mut malik_store = new_store();

        // Malik publie ses clés publiques ; Inès les récupère depuis le serveur et ouvre la session.
        let bundle = publish_bundle(&mut malik_store, device);
        let mut rng = OsRng.unwrap_err();
        initiate_session(&malik, &ines, &mut ines_store.session_store, &mut ines_store.identity_store, &bundle, SystemTime::now(), &mut rng)
            .await
            .unwrap();
        let v = ines_store.load_session(&malik).await.unwrap().unwrap().session_version().unwrap();
        assert_eq!(v, KYBER_AWARE_MESSAGE_VERSION, "la session doit être post-quantique (PQXDH)");

        // Premier message : Inès → Malik.
        let first = encrypt(&mut ines_store, &malik, &ines, "Elles ont fleuri sur le balcon !!".as_bytes()).await;
        assert_eq!(first.message_type(), CiphertextMessageType::PreKey);
        let wire = first.serialize().to_vec();
        assert!(!wire.windows(7).any(|w| w == b"fleuri "), "le texte ne doit jamais apparaître en clair");
        let received = CiphertextMessage::PreKeySignalMessage(PreKeySignalMessage::try_from(wire.as_slice()).unwrap());
        assert_eq!(decrypt(&mut malik_store, &ines, &malik, &received).await, "Elles ont fleuri sur le balcon !!".as_bytes());

        // Réponses en alternance : le ratchet avance à chaque échange.
        for i in 0..20 {
            let text = format!("message {i}");
            let (s, r, from, to) = if i % 2 == 0 {
                (&mut malik_store, &mut ines_store, &malik, &ines)
            } else {
                (&mut ines_store, &mut malik_store, &ines, &malik)
            };
            let c = encrypt(s, to, from, text.as_bytes()).await;
            assert_eq!(c.message_type(), CiphertextMessageType::Whisper);
            let parsed = CiphertextMessage::SignalMessage(SignalMessage::try_from(c.serialize()).unwrap());
            assert_eq!(decrypt(r, from, to, &parsed).await, text.as_bytes());
        }

    }
    .now_or_never()
    .expect("les magasins en mémoire sont synchrones");
}

#[test]
fn un_message_modifie_est_rejete() {
    async {
        let device = DeviceId::new(1).unwrap();
        let ines = ProtocolAddress::new("ines".into(), device);
        let malik = ProtocolAddress::new("malik".into(), device);
        let mut ines_store = new_store();
        let mut malik_store = new_store();
        let bundle = publish_bundle(&mut malik_store, device);
        let mut rng = OsRng.unwrap_err();
        initiate_session(&malik, &ines, &mut ines_store.session_store, &mut ines_store.identity_store, &bundle, SystemTime::now(), &mut rng)
            .await
            .unwrap();
        let c = encrypt(&mut ines_store, &malik, &ines, b"coucou").await;
        let mut wire = c.serialize().to_vec();
        let n = wire.len();
        wire[n - 12] ^= 0x01; // un seul bit modifié par un intermédiaire
        let tampered = PreKeySignalMessage::try_from(wire.as_slice()).map(CiphertextMessage::PreKeySignalMessage);
        if let Ok(msg) = tampered {
            let mut rng = OsRng.unwrap_err();
            let res = message_decrypt(
                &msg,
                &ines,
                &malik,
                &mut malik_store.session_store,
                &mut malik_store.identity_store,
                &mut malik_store.pre_key_store,
                &malik_store.signed_pre_key_store,
                &mut malik_store.kyber_pre_key_store,
                &mut rng,
            )
            .await;
            assert!(res.is_err(), "un message altéré ne doit jamais être déchiffré");
        }
    }
    .now_or_never()
    .expect("synchrone");
}
