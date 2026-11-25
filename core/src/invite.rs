//! Invitation à distance, vérifiée sans symboles (`docs/SECURITY.md` §5).
//!
//! L'invitation que l'un envoie à l'autre (par une autre messagerie, un SMS…) contient, en plus du code :
//! - l'**empreinte** de la clé d'identité de celui qui invite : celui qui rejoint vérifie ainsi la clé publiée par le
//!   serveur, comme avec le QR code ;
//! - un **secret** de 128 bits que le serveur ne voit jamais. Celui qui rejoint prouve qu'il l'a reçu en joignant au
//!   premier message chiffré une preuve `HMAC-SHA256(secret, « FouLove-join-v1 » ‖ sa clé ‖ clé de l'autre)` :
//!   celui qui a invité sait alors que cette clé est bien celle de la personne qui a reçu son invitation.
//!
//! Un serveur malveillant ne peut donc pas se glisser entre vous sans connaître le contenu de l'invitation. Il reste
//! un risque si la même personne contrôle à la fois notre serveur et la messagerie qui a transporté l'invitation :
//! pour l'écarter tout à fait, la comparaison des 7 symboles reste possible.

use hmac::{Hmac, KeyInit, Mac};
use rusqlite::OptionalExtension;
use sha2::Sha256;

use crate::chat::{R, db, hex, kv_set, now_ms, unhex};
use crate::device::Device;

/// Début du premier message chiffré d'un appairage par invitation (suivi de la preuve, en hexadécimal).
pub(crate) const HELLO_V2: &[u8] = b"FOULOVE:BONJOUR:2:";

fn proof(secret: &[u8], joiner_identity: &[u8], creator_identity: &[u8]) -> [u8; 32] {
    let mut m = <Hmac<Sha256> as KeyInit>::new_from_slice(secret).expect("HMAC accepte toute longueur de clé");
    m.update(b"FouLove-join-v1");
    for k in [joiner_identity, creator_identity] {
        m.update(&(k.len() as u32).to_be_bytes());
        m.update(k);
    }
    m.finalize().into_bytes().into()
}

/// Message d'appairage reçu : on garde la preuve pour la vérifier avec le secret de l'invitation.
pub(crate) fn store_proof(c: &rusqlite::Connection, plain: &[u8]) -> R<()> {
    let p = std::str::from_utf8(&plain[HELLO_V2.len()..]).unwrap_or("");
    if p.len() == 64 && unhex(p).is_some() {
        kv_set(c, "join_proof", Some(p), now_ms() as u64)?;
    }
    Ok(())
}

impl Device {
    /// Premier message de celui qui rejoint (la session vers l'autre est déjà ouverte) : « bonjour » et la preuve.
    pub fn join_hello(&self, partner: &str, secret: &[u8]) -> R<Vec<u8>> {
        let theirs = self.trusted_identity(partner)?.ok_or_else(|| crate::device::DeviceError::Protocol("pas de session".into()))?;
        let mut out = HELLO_V2.to_vec();
        out.extend_from_slice(hex(&proof(secret, &self.identity_key()?, &theirs)).as_bytes());
        Ok(out)
    }

    /// Chez celui qui a invité : la preuve reçue correspond-elle au secret de son invitation et à la clé de l'autre ?
    /// Si oui, la clé de l'autre est marquée vérifiée. La preuve n'est utilisable qu'une fois.
    pub fn verify_join_proof(&self, partner: &str, secret: &[u8]) -> R<bool> {
        let got: Option<String> = {
            let c = self.store.conn.lock();
            let v = c
                .query_row("SELECT v FROM kv WHERE k = 'join_proof'", [], |r| r.get::<_, Option<String>>(0))
                .optional()
                .map_err(db)?
                .flatten();
            c.execute("DELETE FROM kv WHERE k = 'join_proof'", []).map_err(db)?;
            v
        };
        let (Some(got), Some(theirs)) = (got.and_then(|g| unhex(&g)), self.trusted_identity(partner)?) else {
            return Ok(false);
        };
        let want = proof(secret, &theirs, &self.identity_key()?);
        let ok = got.len() == 32 && got.iter().zip(want.iter()).fold(0u8, |a, (x, y)| a | (x ^ y)) == 0;
        if ok {
            self.mark_verified(partner, &theirs)?;
        }
        Ok(ok)
    }
}
