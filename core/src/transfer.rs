//! Récupérer notre historique depuis le téléphone de l'autre (nouveau téléphone sans phrase de récupération).
//!
//! 1. Le nouveau téléphone demande (`request_history`) : message chiffré par la session Signal.
//! 2. L'autre téléphone l'affiche ; s'il accepte (`offer_history`), il emballe son historique (messages, clés des
//!    photos et vidéos, dates, albums, lettres), **vu depuis l'autre côté** (« moi » et « toi » inversés), le chiffre avec
//!    une clé aléatoire (STREAM AES-256-GCM, comme les photos) et le dépose sur R2. La clé et l'empreinte partent dans un
//!    message chiffré (`HistoryOffer`).
//! 3. Le nouveau téléphone télécharge, vérifie l'empreinte SHA-256, importe (`import_history`), et retire l'archive
//!    de R2. Les photos et vidéos se retéléchargent ensuite, comme après une restauration.
//!
//! Seule une demande émise par ce téléphone est acceptée en retour (identifiant aléatoire) ; l'app ne propose
//! d'accepter que si la clé de l'autre est vérifiée.

use std::path::Path;

use prost::Message as _;
use rusqlite::{OptionalExtension, params};

use crate::backup::{RestoreSummary, bpb};
use crate::chat::{Outgoing, R, Received, db, hex, id_from_wire, kv_get, kv_set, now_ms, pb, random16, unhex};
use crate::chat_media::{FOR_TRANSFER, KIND_ARCHIVE, NewMedia, PendingUpload, drop_file, file_ref, insert_remote, valid_file};
use crate::device::{Device, DeviceError};

fn del(c: &rusqlite::Connection, k: &str) -> R<()> {
    c.execute("DELETE FROM kv WHERE k = ?1", params![k]).map_err(db)?;
    Ok(())
}

pub(crate) fn apply_request(c: &rusqlite::Connection, x: pb::Ref) -> R<Received> {
    let id = id_from_wire(&x.id).ok_or(DeviceError::BadMessage)?;
    kv_set(c, "history_asked", Some(&id), now_ms() as u64)?;
    Ok(Received::HistoryRequested)
}

pub(crate) fn apply_offer(c: &rusqlite::Connection, x: pb::HistoryOffer) -> R<Received> {
    let req = id_from_wire(&x.request).ok_or(DeviceError::BadMessage)?;
    // Seulement en réponse à une demande de ce téléphone.
    if kv_get(c, "history_wanted")?.as_deref() != Some(req.as_str()) {
        return Ok(Received::Nothing);
    }
    let Some(f) = x.file.filter(|f| valid_file(f, &[KIND_ARCHIVE])) else { return Err(DeviceError::BadMessage) };
    let id = hex(&random16());
    insert_remote(c, &id, &f, FOR_TRANSFER)?;
    kv_set(c, "history_incoming", Some(&id), now_ms() as u64)?;
    del(c, "history_wanted")?;
    Ok(Received::HistoryOffered)
}

/// L'historique vu depuis l'autre téléphone : « moi » devient « toi », réactions échangées.
fn mirror(mut b: bpb::Backup) -> bpb::Backup {
    for m in &mut b.messages {
        m.from_me = !m.from_me;
        std::mem::swap(&mut m.my_reaction, &mut m.their_reaction);
        // Devenu « mien » : distribué, ou lu s'il l'avait lu. Devenu « sien » : lu (il était chez moi).
        m.status = if m.from_me { m.status.clamp(2, 3) } else { 3 };
    }
    for l in &mut b.letters {
        l.from_me = !l.from_me;
        l.starred = false;
    }
    // Les photos de notre profil et les petites valeurs reviennent par le renvoi de notre espace (`resync`).
    b.media.retain(|m| m.purpose == 0);
    b.pictures.clear();
    b.kv.clear();
    b
}

/// État du transfert vu par ce téléphone.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct HistoryState {
    /// Son nouveau téléphone demande notre historique.
    pub asked: bool,
    /// Ce téléphone a demandé l'historique et attend.
    pub waiting: bool,
    /// L'historique est arrivé : téléchargement en cours (`ready` faux) ou prêt à importer.
    pub incoming: bool,
    pub ready: bool,
}

impl Device {
    pub fn history_state(&self) -> R<HistoryState> {
        let c = self.store.conn.lock();
        let incoming = kv_get(&c, "history_incoming")?;
        let ready = match &incoming {
            Some(id) => c
                .query_row("SELECT state FROM media WHERE message_id = ?1", params![id], |r| r.get::<_, i64>(0))
                .optional()
                .map_err(db)?
                == Some(1),
            None => false,
        };
        Ok(HistoryState {
            asked: kv_get(&c, "history_asked")?.is_some(),
            waiting: kv_get(&c, "history_wanted")?.is_some(),
            incoming: incoming.is_some(),
            ready,
        })
    }

    /// Nouveau téléphone : demande notre historique à l'autre.
    pub fn request_history(&mut self, partner: &str) -> R<Outgoing> {
        let id = random16();
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            kv_set(&self.store.conn.lock(), "history_wanted", Some(&hex(&id)), now_ms() as u64)?;
            self.enqueue(partner, pb::Body::HistoryRequest(pb::Ref { id: id.to_vec() }), None)
        })
    }

    /// Refuser la demande (ou l'oublier).
    pub fn decline_history(&self) -> R<()> {
        del(&self.store.conn.lock(), "history_asked")
    }

    /// Accepter : prépare l'archive chiffrée dans `dir` ; elle partira une fois déposée sur R2 (`media_uploaded`).
    pub fn offer_history(&mut self, dir: &Path) -> R<PendingUpload> {
        let req = kv_get(&self.store.conn.lock(), "history_asked")?.ok_or_else(|| DeviceError::Protocol("aucune demande".into()))?;
        let plain = mirror(self.snapshot()?).encode_to_vec();
        let id = hex(&random16());
        let m = NewMedia { kind: KIND_ARCHIVE, mime: "application/octet-stream", width: 0, height: 0, duration_ms: 0, thumb: &[], caption: "", reply_to: None };
        let up = self.create_file(dir, &id, Some(&plain), None, &m, FOR_TRANSFER)?;
        let c = self.store.conn.lock();
        kv_set(&c, "history_offer", Some(&format!("{id}|{req}")), now_ms() as u64)?;
        del(&c, "history_asked")?;
        Ok(up)
    }

    pub(crate) fn history_uploaded(&mut self, partner: &str, id: &str, object_key: &str) -> R<Option<Outgoing>> {
        let tx = self.store.conn.clone();
        tx.atomically(|| {
            let body = {
                let c = self.store.conn.lock();
                c.execute("UPDATE media SET object_key = ?2, state = 1 WHERE message_id = ?1 AND state = 0", params![id, object_key])
                    .map_err(db)?;
                let offer = kv_get(&c, "history_offer")?;
                let Some((mid, req)) = offer.as_deref().and_then(|o| o.split_once('|')) else {
                    drop_file(&c, id, true)?;
                    return Ok(None);
                };
                if mid != id {
                    drop_file(&c, id, true)?;
                    return Ok(None);
                }
                let f = file_ref(&c, id)?;
                let req = unhex(req).ok_or(DeviceError::BadMessage)?;
                // Le chiffré local ne sert plus ; l'objet R2 reste, l'autre téléphone le retirera après l'import.
                drop_file(&c, id, false)?;
                del(&c, "history_offer")?;
                pb::HistoryOffer { request: req, file: f }
            };
            self.enqueue(partner, pb::Body::HistoryOffer(body), None).map(Some)
        })
    }

    /// L'archive est téléchargée et vérifiée : on l'importe, puis on la retire (ici et de R2).
    /// `None` : rien à importer (pas encore téléchargée, ou aucun transfert).
    pub fn import_history(&mut self) -> R<Option<RestoreSummary>> {
        let st = self.history_state()?;
        if !st.ready {
            return Ok(None);
        }
        let id = kv_get(&self.store.conn.lock(), "history_incoming")?.unwrap_or_default();
        let plain = self.open_media(&id)?;
        let b = bpb::Backup::decode(plain.as_slice()).map_err(|_| DeviceError::BadMessage)?;
        let sum = self.import_snapshot(&b)?;
        let c = self.store.conn.lock();
        drop_file(&c, &id, true)?;
        del(&c, "history_incoming")?;
        Ok(Some(sum))
    }
}
