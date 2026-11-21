import React from "react";
import {
  AbsoluteFill, Audio, Easing, Img, interpolate, OffthreadVideo, Sequence, spring, staticFile, useCurrentFrame,
  useVideoConfig,
} from "remotion";
import dialogue from "./dialogue-1.json";
import { Telephone } from "./Telephone";

// « Mille kilomètres » : Inès et Sami racontent leur bulle. Tout le minutage vient de la voix (dialogue-1.json).
const S = dialogue.segments; // S[0] = réplique 1, etc.
const t = (n: number) => S[n - 1].debut;
const FIN_VOIX = S[S.length - 1].fin;
export const DUREE = FIN_VOIX + 2.6;
const MUSIQUE_DECALAGE = 2.68; // le groove de la musique démarre à 9 s : il tombe ainsi sur « FouLove »

const C = { creme: "#fff8f5", encre: "#2b1a22", framboise: "#d6336c", rose: "#ff8fab", or: "#f5c26b", prune: "#140c14" };
const serif = "'Fraunces FouLove', Georgia, serif";
const sans = "Atkinson, system-ui, sans-serif";

// Opacité bornée et arrondie : une valeur de ressort à peine au-dessus de 1 (1.0018…) rendait le texte invisible.
const op = (x: number) => Math.max(0, Math.min(1, Math.round(x * 1000) / 1000));

const useMise = () => {
  const { width, height } = useVideoConfig();
  const vertical = height > width;
  return { vertical, w: width, h: height, u: Math.min(width, height) / 1080 };
};

// Entrée « ressort » à partir d'une image donnée.
const useRessort = (depart = 0, raideur = 140) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  return spring({ frame: f - depart, fps, config: { damping: 14, stiffness: raideur, mass: 0.7 } });
};

// --------------------------------------------------------------------------------------------- sous-titres

type Mot = { mot: string; debut: number };
const MOTS: Mot[] = (() => {
  const out: Mot[] = [];
  const ch = dialogue.chars ?? [];
  const de = dialogue.debuts ?? [];
  let cur = "", d0 = 0, dansTag = false;
  for (let i = 0; i < ch.length; i++) {
    const c = ch[i];
    if (c === "[") { dansTag = true; continue; }
    if (c === "]") { dansTag = false; continue; }
    if (dansTag) continue;
    if (/\s/.test(c)) { if (cur) out.push({ mot: cur, debut: d0 }); cur = ""; continue; }
    // une nouvelle réplique commence : le mot en cours s'arrête (les répliques ne sont pas séparées par un espace)
    if (cur && S.some((x) => x.debut > d0 + 0.01 && de[i] >= x.debut - 0.001)) { out.push({ mot: cur, debut: d0 }); cur = ""; }
    if (!cur) d0 = de[i];
    cur += c;
  }
  if (cur) out.push({ mot: cur, debut: d0 });
  return out;
})();

const SousTitres: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { vertical, u, w } = useMise();
  const s = f / fps;
  const seg = S.find((x) => s >= x.debut - 0.05 && s < x.fin + 0.25);
  if (!seg) return null;
  const mots = MOTS.filter((m) => m.debut >= seg.debut - 0.02 && m.debut < seg.fin);
  if (mots.length === 0) return null;
  const elle = seg.voix === "elle";
  return (
    <div
      style={{
        position: "absolute", left: 0, right: 0, bottom: vertical ? 110 * u : 60 * u, display: "flex",
        justifyContent: vertical ? "center" : "flex-end", paddingRight: vertical ? 0 : w * 0.06, pointerEvents: "none",
      }}
    >
      <div
        style={{
          maxWidth: vertical ? 900 * u : 820 * u, display: "flex", flexWrap: "wrap", justifyContent: "center", gap: `${6 * u}px ${12 * u}px`,
          padding: `${18 * u}px ${30 * u}px`, borderRadius: 26 * u, background: "rgba(20,12,20,.62)", backdropFilter: "blur(12px)",
          fontFamily: sans, fontWeight: 700, fontSize: (vertical ? 44 : 38) * u, lineHeight: 1.25,
          borderLeft: `${6 * u}px solid ${elle ? C.rose : C.or}`,
        }}
      >
        {mots.map((m, i) => {
          const dit = s >= m.debut;
          return (
            <span key={i} style={{ color: dit ? "#fff" : "rgba(255,255,255,.38)", transform: `translateY(${dit ? 0 : 4 * u}px)`, transition: "none" }}>
              {m.mot}
            </span>
          );
        })}
      </div>
    </div>
  );
};

// --------------------------------------------------------------------------------------------- éléments communs

const Fond: React.FC<{ nuit?: boolean }> = ({ nuit }) => {
  const f = useCurrentFrame();
  const a = f / 30;
  return (
    <AbsoluteFill
      style={{
        background: nuit
          ? `radial-gradient(60% 40% at ${50 + 10 * Math.sin(a / 3)}% 30%, #3a1830 0, transparent 70%), radial-gradient(50% 40% at 30% 80%, #2a0f24, transparent 70%), ${C.prune}`
          : `radial-gradient(60% 40% at ${70 + 8 * Math.sin(a / 2.5)}% 12%, #ffd3e0 0, transparent 70%), radial-gradient(55% 40% at ${20 + 6 * Math.cos(a / 3)}% 85%, #fde3c2 0, transparent 70%), ${C.creme}`,
      }}
    />
  );
};

// Petits cœurs qui montent (gerbe), autour d'un point.
const Coeurs: React.FC<{ n?: number; x?: number; y?: number; couleur?: string; depart?: number }> = ({ n = 14, x = 0.5, y = 0.5, couleur = C.framboise, depart = 0 }) => {
  const f = useCurrentFrame() - depart;
  const { w, h, u } = useMise();
  if (f < 0) return null;
  return (
    <AbsoluteFill style={{ pointerEvents: "none" }}>
      {Array.from({ length: n }).map((_, i) => {
        const ang = (i / n) * Math.PI * 2 + i;
        const v = 6 + (i % 5) * 2.2;
        const px = w * x + Math.cos(ang) * f * v * u;
        const py = h * y + Math.sin(ang) * f * v * 0.6 * u - f * f * 0.12 * u * (i % 3 === 0 ? -1 : 1);
        const op = interpolate(f, [0, 6, 34], [0, 1, 0], { extrapolateRight: "clamp" });
        const sz = (22 + (i % 4) * 10) * u;
        return (
          <svg key={i} width={sz} height={sz} viewBox="0 0 24 24" style={{ position: "absolute", left: px, top: py, opacity: op, transform: `rotate(${(i % 7) * 12 - 36}deg)` }}>
            <path d="M12 21s-7.5-4.4-7.5-10.2A4.3 4.3 0 0 1 12 8.2a4.3 4.3 0 0 1 7.5 2.6C19.5 16.6 12 21 12 21z" fill={i % 3 === 0 ? C.or : couleur} />
          </svg>
        );
      })}
    </AbsoluteFill>
  );
};

// Gros titre animé (mots qui montent un par un).
const Titre: React.FC<{ mots: string[]; couleurs?: (string | undefined)[]; taille?: number; nuit?: boolean; italique?: number[]; y?: number; pas?: number }> = ({
  mots, couleurs = [], taille = 104, nuit, italique = [], y, pas = 4,
}) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { vertical, u, w, h } = useMise();
  return (
    <div
      style={{
        position: "absolute", left: vertical ? 70 * u : w * 0.5, right: vertical ? 70 * u : w * 0.06, top: y ?? (vertical ? 190 * u : h * 0.3),
        bottom: vertical ? undefined : undefined, display: "flex", flexWrap: "wrap", gap: `0 ${0.26 * taille * u}px`,
        justifyContent: vertical ? "center" : "flex-start", fontFamily: serif, fontWeight: 600, fontSize: taille * u,
        lineHeight: 1.02, letterSpacing: "-0.025em", color: nuit ? "#fbeff4" : C.encre, textAlign: vertical ? "center" : "left",
      }}
    >
      {mots.map((m, i) => {
        const p = spring({ frame: f - i * pas, fps, config: { damping: 13, stiffness: 160, mass: 0.6 } });
        return (
          <span key={i} style={{ display: "inline-block", transform: `translateY(${(1 - p) * 60 * u}px)`, opacity: op(p), color: couleurs[i], fontStyle: italique.includes(i) ? "italic" : "normal" }}>
            {m}
          </span>
        );
      })}
    </div>
  );
};

const TitreCentre: React.FC<{ mots: string[]; couleurs?: (string | undefined)[]; taille: number; nuit?: boolean; italique?: number[]; y: number }> = ({ mots, couleurs = [], taille, nuit, italique = [], y }) => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { u } = useMise();
  return (
    <div style={{ position: "absolute", left: 60 * u, right: 60 * u, top: y, display: "flex", flexWrap: "wrap", justifyContent: "center", gap: `0 ${0.26 * taille * u}px`, fontFamily: serif, fontWeight: 600, fontSize: taille * u, lineHeight: 1.04, letterSpacing: "-0.025em", color: nuit ? "#fbeff4" : C.encre }}>
      {mots.map((m, i) => {
        const p = spring({ frame: f - i * 4, fps, config: { damping: 13, stiffness: 160, mass: 0.6 } });
        return <span key={i} style={{ display: "inline-block", transform: `translateY(${(1 - p) * 60 * u}px)`, opacity: op(p), color: couleurs[i], fontStyle: italique.includes(i) ? "italic" : "normal" }}>{m}</span>;
      })}
    </div>
  );
};

// Téléphone qui entre avec un léger basculement, placé selon le format.
const Scene: React.FC<{ video?: string; image?: string; debut?: number; vitesse?: number; sombre?: boolean; titre?: React.ReactNode; children?: React.ReactNode; nuit?: boolean }> = ({
  video, image, debut, vitesse, sombre, titre, children, nuit,
}) => {
  const f = useCurrentFrame();
  const { vertical, u, w, h } = useMise();
  const p = useRessort(0, 120);
  const H = vertical ? 1040 * u : 860 * u;
  const balance = Math.sin(f / 22) * 1.2;
  return (
    <AbsoluteFill>
      <Fond nuit={nuit} />
      {titre}
      <div
        style={{
          position: "absolute", left: vertical ? (w - H * 0.45) / 2 : w * 0.24 - (H * 0.45) / 2, top: vertical ? 450 * u : (h - H) / 2 - 20 * u,
          transform: `translateY(${(1 - p) * 220 * u}px) rotate(${(1 - p) * -6 + balance}deg) scale(${0.92 + 0.08 * p})`,
          opacity: op(p * 1.6),
        }}
      >
        <Telephone hauteur={H} video={video} image={image} debut={debut} vitesse={vitesse} sombre={sombre}>
          {children}
        </Telephone>
      </div>
    </AbsoluteFill>
  );
};

// Bulle de message dessinée par-dessus l'écran (arrive avec un « pop »).
const BulleMsg: React.FC<{ texte: string; depart: number; moi?: boolean; y: number }> = ({ texte, depart, moi, y }) => {
  const p = useRessort(depart, 200);
  const { vertical, u } = useMise();
  const k = (vertical ? 1040 : 860) / 2400; // échelle de l'écran
  if (p <= 0.001) return null;
  return (
    <div
      style={{
        position: "absolute", top: y * k * u, [moi ? "right" : "left"]: 36 * k * u, maxWidth: 760 * k * u,
        padding: `${26 * k * u}px ${40 * k * u}px`, borderRadius: 52 * k * u, fontFamily: "system-ui, Roboto", fontSize: 42 * k * u,
        color: moi ? "#fff" : C.encre, background: moi ? "linear-gradient(135deg,#e8417a,#f39c6b)" : "#fff",
        boxShadow: "0 6px 20px rgba(0,0,0,.12)", transform: `scale(${p})`, transformOrigin: moi ? "right bottom" : "left bottom",
      }}
    >
      {texte}
    </div>
  );
};

// --------------------------------------------------------------------------------------------- les scènes

const Accroche: React.FC = () => {
  const f = useCurrentFrame();
  const { vertical, u, w, h } = useMise();
  const p = useRessort(4, 220);
  const lueur = interpolate(f, [0, 10, 90], [0, 1, 0.8], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill>
      <AbsoluteFill style={{ background: C.prune }} />
      <OffthreadVideo src={staticFile("clips/intro-nuit.mp4")} muted startFrom={0} style={{ width: "100%", height: "100%", objectFit: "cover", opacity: 0.55 }} />
      {/* notification FouLove : le contenu reste privé, comme dans l'app */}
      <div
        style={{
          position: "absolute", left: "50%", top: vertical ? 300 * u : h * 0.18, width: vertical ? 900 * u : 760 * u,
          transform: `translate(-50%, ${(1 - p) * -160 * u}px) scale(${0.9 + 0.1 * p})`, opacity: op(p),
          display: "flex", gap: 26 * u, alignItems: "center", padding: `${28 * u}px ${32 * u}px`, borderRadius: 38 * u,
          background: "rgba(255,255,255,.14)", border: "1px solid rgba(255,255,255,.22)", backdropFilter: "blur(18px)",
          boxShadow: `0 0 ${80 * u * lueur}px rgba(255,111,159,${0.35 * lueur})`,
        }}
      >
        <Img src={staticFile("img/icone.png")} style={{ width: 96 * u, height: 96 * u, borderRadius: 24 * u }} />
        <div style={{ fontFamily: sans, color: "#fff" }}>
          <div style={{ fontWeight: 800, fontSize: 38 * u, display: "flex", justifyContent: "space-between", gap: 30 * u }}>
            <span>FouLove</span>
            <span style={{ fontWeight: 400, opacity: 0.7 }}>00:00</span>
          </div>
          <div style={{ fontSize: 40 * u, opacity: 0.92 }}>Nouveau message 💌</div>
        </div>
      </div>
      <div style={{ position: "absolute", left: 0, right: 0, top: vertical ? 760 * u : h * 0.5, textAlign: "center", fontFamily: serif, fontStyle: "italic", fontSize: (vertical ? 190 : 150) * u, color: "#fbeff4", opacity: interpolate(f, [18, 34], [0, 1], { extrapolateRight: "clamp" }), letterSpacing: "-0.02em" }}>
        00:00
      </div>
    </AbsoluteFill>
  );
};

const Distance: React.FC = () => {
  const f = useCurrentFrame();
  const { vertical, u, w, h } = useMise();
  const dA = Math.round((t(3) - t(2)) * 30); // « Mille kilomètres entre nous… »
  const km = interpolate(f, [0, dA * 0.7], [0, 1000], { extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
  // les deux points (elle en rose, lui en or) : écartés, puis ils foncent l'un vers l'autre
  const rapproche = interpolate(f, [dA - 12, dA], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.in(Easing.cubic) });
  const ecart = (vertical ? 0.36 : 0.3) * w * (1 - rapproche);
  const cy = vertical ? h * 0.56 : h * 0.6;
  const pulse = 1 + 0.12 * Math.sin(f / 4);
  const entree = spring({ frame: f, fps: 30, config: { damping: 15, stiffness: 120 } });
  const orbe = (x: number, c1: string) => (
    <div style={{ position: "absolute", left: x - 40 * u, top: cy - 40 * u, width: 80 * u, height: 80 * u, borderRadius: "50%", transform: `scale(${pulse * entree})`,
      background: `radial-gradient(circle, #fff 0 18%, ${c1} 38%, transparent 70%)`, boxShadow: `0 0 ${90 * u}px ${30 * u}px ${c1}88` }} />
  );
  const flash = interpolate(f, [dA - 2, dA + 2, dA + 10], [0, 0.9, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const phaseB = f >= dA;
  return (
    <AbsoluteFill style={{ background: C.prune }}>
      {!phaseB && (
        <>
          <OffthreadVideo src={staticFile("clips/intro-nuit.mp4")} muted startFrom={15} style={{ width: "100%", height: "100%", objectFit: "cover", opacity: 0.6 }} />
          {/* fil entre les deux */}
          <div style={{ position: "absolute", left: w / 2 - ecart, width: ecart * 2, top: cy - 1.5 * u, height: 3 * u, opacity: op(entree * (1 - rapproche)),
            background: `repeating-linear-gradient(90deg, rgba(255,214,227,.75) 0 ${18 * u}px, transparent ${18 * u}px ${34 * u}px)` }} />
          {orbe(w / 2 - ecart, C.rose)}
          {orbe(w / 2 + ecart, C.or)}
          <div style={{ position: "absolute", left: 0, right: 0, top: cy - (vertical ? 420 : 330) * u, textAlign: "center", opacity: op(entree * (1 - rapproche)), transform: `scale(${0.85 + 0.15 * entree})` }}>
            <div style={{ fontFamily: serif, fontWeight: 600, fontSize: (vertical ? 240 : 200) * u, color: "#fbeff4", letterSpacing: "-0.04em", lineHeight: 1 }}>
              {Math.round(km).toLocaleString("fr-FR")}
              <span style={{ fontSize: (vertical ? 110 : 90) * u, color: C.rose, fontStyle: "italic" }}> km</span>
            </div>
            <div style={{ fontFamily: sans, fontWeight: 700, letterSpacing: "0.22em", fontSize: 32 * u, color: "rgba(251,239,244,.75)", marginTop: 16 * u }}>ENTRE NOUS</div>
          </div>
          <div style={{ position: "absolute", left: w / 2 - ecart - 60 * u, top: cy + 70 * u, width: 120 * u, textAlign: "center", fontFamily: sans, fontWeight: 800, fontSize: 30 * u, color: C.rose, opacity: op(entree * (1 - rapproche)) }}>Inès</div>
          <div style={{ position: "absolute", left: w / 2 + ecart - 60 * u, top: cy + 70 * u, width: 120 * u, textAlign: "center", fontFamily: sans, fontWeight: 800, fontSize: 30 * u, color: C.or, opacity: op(entree * (1 - rapproche)) }}>Sami</div>
        </>
      )}
      {phaseB && (
        <Sequence from={dA} layout="none">
          <BulleNuit />
        </Sequence>
      )}
      <AbsoluteFill style={{ background: "#fff", opacity: op(flash) }} />
    </AbsoluteFill>
  );
};

// « Mais une seule bulle. » : l'intro de nuit de l'app, du cœur à la bulle, en grand.
const BulleNuit: React.FC = () => {
  const f = useCurrentFrame();
  const { vertical, u, h } = useMise();
  const duree = (t(4) - t(3)) * 30;
  const zoom = interpolate(f, [0, duree], [1.08, 1.0]);
  const texte = spring({ frame: f - 4, fps: 30, config: { damping: 14, stiffness: 140 } });
  return (
    <AbsoluteFill style={{ background: C.prune }}>
      {!vertical && (
        <OffthreadVideo src={staticFile("clips/intro-nuit.mp4")} muted startFrom={Math.round(4.4 * 30)} playbackRate={(7.4 - 4.4) / ((duree + 4) / 30)}
          style={{ position: "absolute", width: "100%", height: "100%", objectFit: "cover", filter: "blur(40px) brightness(.7)", transform: "scale(1.2)" }} />
      )}
      <OffthreadVideo src={staticFile("clips/intro-nuit.mp4")} muted startFrom={Math.round(4.4 * 30)} playbackRate={(7.4 - 4.4) / ((duree + 4) / 30)}
        style={{ position: "absolute", width: "100%", height: "100%", objectFit: vertical ? "cover" : "contain", WebkitMaskImage: vertical ? undefined : "linear-gradient(90deg, transparent 30%, #000 40%, #000 60%, transparent 70%)", transform: `scale(${vertical ? zoom : zoom * 1.75})`, transformOrigin: vertical ? "50% 50%" : "50% 40%" }} />
      <div style={{ position: "absolute", left: 0, right: 0, top: vertical ? 1240 * u : h * 0.8, textAlign: "center", fontFamily: serif, fontWeight: 600,
        fontSize: (vertical ? 120 : 84) * u, color: "#fbeff4", letterSpacing: "-0.02em", opacity: op(texte), transform: `translateY(${(1 - texte) * 40 * u}px)`,
        textShadow: "0 4px 30px rgba(0,0,0,.5)" }}>
        une seule <em style={{ color: C.rose }}>bulle.</em>
      </div>
    </AbsoluteFill>
  );
};

const TitreFouLove: React.FC = () => {
  const f = useCurrentFrame();
  const { u, vertical } = useMise();
  const p = useRessort(0, 260);
  const flash = interpolate(f, [0, 3, 12], [1, 0.6, 0], { extrapolateRight: "clamp" });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <Fond />
      <Img src={staticFile("img/icone.png")} style={{ width: 300 * u, height: 300 * u, borderRadius: 76 * u, transform: `scale(${p}) rotate(${(1 - p) * -20}deg)`, boxShadow: "0 40px 90px -30px rgba(150,20,70,.6)" }} />
      <div style={{ fontFamily: serif, fontWeight: 600, fontSize: (vertical ? 170 : 150) * u, letterSpacing: "-0.03em", color: C.encre, marginTop: 40 * u, transform: `translateY(${(1 - p) * 50 * u}px)`, opacity: op(p) }}>
        Fou<em style={{ color: C.framboise }}>Love</em>
      </div>
      <Coeurs n={18} x={0.5} y={0.42} />
      <AbsoluteFill style={{ background: "#fff", opacity: flash }} />
    </AbsoluteFill>
  );
};

const Messages: React.FC = () => {
  const { u } = useMise();
  return (
    <Scene video="messages" debut={0.5} vitesse={1.05} titre={<Titre mots={["Rien", "que", "nous", "deux."]} couleurs={[undefined, undefined, C.framboise, C.framboise]} italique={[2, 3]} />}>
      <BulleMsg texte="Tu dors ? 🌙" depart={36} y={1650} />
      <BulleMsg texte="Je pense à toi. Bonne nuit, mon cœur ❤️" depart={70} y={1790} />
      <Coeurs n={10} x={0.5} y={0.72} depart={78} />
      <div style={{ position: "absolute", inset: 0, boxShadow: `inset 0 ${-260 * u}px ${120 * u}px -${120 * u}px rgba(255,248,245,.0)` }} />
    </Scene>
  );
};

const Instant: React.FC = () => {
  const f = useCurrentFrame();
  const { u, vertical } = useMise();
  return (
    <Scene video="instant" debut={0.3} sombre titre={<Titre mots={["Un", "instant,", "24 h."]} couleurs={[undefined, undefined, C.framboise]} italique={[2]} />}>
      <div style={{ position: "absolute", top: 60 * u, right: 40 * u, fontFamily: sans, fontWeight: 800, fontSize: (vertical ? 34 : 26) * u, color: "#fff", background: "rgba(0,0,0,.35)", padding: `${8 * u}px ${18 * u}px`, borderRadius: 99 }}>
        ⏳ {Math.max(0, 24 - Math.floor(f / 3))} h
      </div>
    </Scene>
  );
};

const Souvenirs: React.FC = () => (
  <Scene video="souvenirs" debut={0.3} titre={<Titre mots={["Vos", "souvenirs,", "rangés."]} couleurs={[undefined, undefined, C.framboise]} italique={[2]} />} />
);

const Lettres: React.FC = () => {
  const f = useCurrentFrame();
  const { u, vertical, w } = useMise();
  const p = useRessort(52, 200);
  return (
    <Scene video="lettres" debut={0.8} titre={<Titre mots={["Une", "lettre,", "scellée."]} couleurs={[undefined, undefined, C.framboise]} italique={[2]} />}>
      <div
        style={{
          position: "absolute", left: "50%", top: "42%", transform: `translate(-50%,-50%) scale(${p}) rotate(${(1 - p) * 30 - 8}deg)`,
          width: (vertical ? 260 : 200) * u, height: (vertical ? 260 : 200) * u, borderRadius: "50%",
          background: "radial-gradient(circle at 35% 30%, #ff8fab, #c2255c 60%, #8e1442)", boxShadow: "0 20px 40px rgba(120,10,50,.45), inset 0 -8px 20px rgba(0,0,0,.25)",
          display: "grid", placeItems: "center", color: "#ffe3ea", fontFamily: serif, fontSize: (vertical ? 46 : 36) * u, fontWeight: 600, textAlign: "center", lineHeight: 1,
          opacity: f > 52 ? 1 : 0,
        }}
      >
        14<br />fév.
      </div>
    </Scene>
  );
};

const Languir: React.FC = () => {
  const { vertical, u } = useMise();
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <Fond />
      <Titre mots={["Tu", "me", "fais", "languir", "!"]} couleurs={[undefined, undefined, undefined, C.framboise, C.framboise]} italique={[3]} taille={vertical ? 150 : 130} y={vertical ? 760 * u : 380 * u} pas={3} />
      <Coeurs n={22} x={0.5} y={0.48} depart={8} />
    </AbsoluteFill>
  );
};

const Invitation: React.FC = () => {
  const f = useCurrentFrame();
  const bascule = Math.round((t(10) + 2.1 - t(10)) * 30);
  return f < bascule ? (
    <Scene image="invA" titre={<Titre mots={["Un", "simple", "message."]} couleurs={[undefined, undefined, C.framboise]} italique={[2]} />} />
  ) : (
    <Sequence from={bascule} layout="none">
      <Scene image="b2" titre={<Titre mots={["Votre", "bulle", "est", "née."]} couleurs={[undefined, C.framboise, undefined, C.framboise]} italique={[1, 3]} />}>
        <Coeurs n={16} x={0.5} y={0.5} depart={6} />
      </Scene>
    </Sequence>
  );
};

const Chiffre: React.FC = () => {
  const f = useCurrentFrame();
  const { u, vertical } = useMise();
  const p = useRessort(0, 180);
  const ferme = interpolate(f, [8, 18], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: Easing.out(Easing.back(2)) });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <Fond nuit />
      <svg width={260 * u} height={300 * u} viewBox="0 0 26 30" style={{ transform: `scale(${p})` }}>
        <path d={`M7 ${13 - 4 * (1 - ferme)} V9a6 6 0 0 1 12 0v4`} fill="none" stroke={C.rose} strokeWidth="2.4" strokeLinecap="round" />
        <rect x="3" y="13" width="20" height="15" rx="4" fill={C.framboise} />
        <circle cx="13" cy="20" r="2.2" fill="#ffe3ea" />
      </svg>
      <div style={{ height: (vertical ? 250 : 200) * u }} />
      <TitreCentre mots={["Chiffré", "de", "bout", "en", "bout."]} couleurs={[undefined, undefined, undefined, undefined, C.rose]} italique={[4]} taille={vertical ? 96 : 84} nuit y={(vertical ? 1010 : 640) * u} />
      <div style={{ marginTop: 34 * u, display: "flex", gap: 18 * u, opacity: interpolate(f, [16, 28], [0, 1], { extrapolateRight: "clamp" }) }}>
        {["Sans publicité", "Sans traceur", "Code public"].map((x) => (
          <span key={x} style={{ fontFamily: sans, fontWeight: 700, fontSize: (vertical ? 30 : 26) * u, color: "#fbeff4", padding: `${10 * u}px ${20 * u}px`, borderRadius: 99, border: "1.5px solid rgba(255,143,171,.5)" }}>{x}</span>
        ))}
      </div>
    </AbsoluteFill>
  );
};

const Serveur: React.FC = () => (
  <Scene video="serveur" debut={1.6} vitesse={1.3} titre={<Titre mots={["Ce", "qu'ils", "voient.", "Et", "pas", "plus."]} couleurs={[undefined, undefined, undefined, undefined, C.framboise, C.framboise]} italique={[4, 5]} taille={100} />} />
);

const PasMeme: React.FC = () => {
  const f = useCurrentFrame();
  const { vertical, u } = useMise();
  const zoom = interpolate(f, [0, 45], [1.15, 1], { extrapolateRight: "clamp", easing: Easing.out(Easing.cubic) });
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", background: C.prune }}>
      <div style={{ transform: `scale(${zoom})`, textAlign: "center", fontFamily: serif, fontWeight: 600, fontSize: (vertical ? 190 : 170) * u, lineHeight: 0.98, color: "#fbeff4", letterSpacing: "-0.03em" }}>
        Pas même<br />Fou<em style={{ color: C.rose }}>Love.</em>
      </div>
    </AbsoluteFill>
  );
};

const Fin: React.FC = () => {
  const { vertical, u, h } = useMise();
  const p = useRessort(0, 160);
  const q = useRessort(26, 140);
  const haut = vertical ? 600 * u : h * 0.16;
  return (
    <AbsoluteFill>
      <Fond />
      <Img src={staticFile("img/icone.png")} style={{ position: "absolute", left: "50%", top: haut, width: 230 * u, height: 230 * u, marginLeft: -115 * u, borderRadius: 58 * u, transform: `scale(${p})`, boxShadow: "0 40px 90px -30px rgba(150,20,70,.6)" }} />
      <TitreCentre mots={["Une", "bulle", "à", "deux."]} couleurs={[undefined, undefined, C.framboise, C.framboise]} italique={[2, 3]} taille={vertical ? 130 : 110} y={haut + 290 * u} />
      <div style={{ position: "absolute", left: 0, right: 0, top: haut + (vertical ? 470 : 430) * u, opacity: op(q), transform: `translateY(${(1 - q) * 30 * u}px)`, textAlign: "center", fontFamily: sans }}>
        <div style={{ display: "inline-block", fontWeight: 800, fontSize: 38 * u, color: "#fff", background: C.framboise, padding: `${16 * u}px ${36 * u}px`, borderRadius: 99 }}>Bientôt sur Google Play</div>
        <div style={{ marginTop: 22 * u, fontSize: 34 * u, color: "#6e5864", fontWeight: 700 }}>foulove.josuecode.com</div>
      </div>
      <Coeurs n={14} x={0.5} y={vertical ? 0.36 : 0.3} depart={4} />
    </AbsoluteFill>
  );
};

// --------------------------------------------------------------------------------------------- le film

const sec = (s: number) => Math.round(s * 30);

export const Film: React.FC = () => {
  const plan: [React.FC, number, number][] = [
    [Accroche, 0, t(2)],
    [Distance, t(2), t(4)],
    [TitreFouLove, t(4), t(5)],
    [Messages, t(5), t(6)],
    [Instant, t(6), t(7)],
    [Souvenirs, t(7), t(8)],
    [Lettres, t(8), t(9)],
    [Languir, t(9), t(10)],
    [Invitation, t(10), t(11)],
    [Chiffre, t(11), t(12)],
    [Serveur, t(12), t(13)],
    [PasMeme, t(13), t(14)],
    [Fin, t(14), DUREE],
  ];
  const f = useCurrentFrame();
  const volMusique = (fr: number) => {
    const s = fr / 30;
    const parle = S.some((x) => s >= x.debut - 0.1 && s <= x.fin + 0.1);
    const fin = interpolate(s, [DUREE - 2.2, DUREE], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
    return (parle ? 0.28 : 0.55) * fin;
  };
  return (
    <AbsoluteFill style={{ background: C.creme }}>
      {plan.map(([Comp, a, b], i) => (
        <Sequence key={i} from={sec(a)} durationInFrames={Math.max(1, sec(b) - sec(a))}>
          <Comp />
        </Sequence>
      ))}
      <SousTitres />
      <Audio src={staticFile("voix-dialogue.mp3")} />
      <Audio src={staticFile("son/musique.mp3")} startFrom={sec(MUSIQUE_DECALAGE)} volume={volMusique} />
      <Sequence from={sec(0.12)}><Audio src={staticFile("son/notification.mp3")} volume={0.7} /></Sequence>
      <Sequence from={sec(t(4))}><Audio src={staticFile("son/pop.mp3")} volume={0.8} /></Sequence>
      <Sequence from={sec(t(5)) + 36}><Audio src={staticFile("son/pop.mp3")} volume={0.5} /></Sequence>
      <Sequence from={sec(t(5)) + 70}><Audio src={staticFile("son/pop.mp3")} volume={0.5} /></Sequence>
      <Sequence from={sec(t(8)) + 50}><Audio src={staticFile("son/sceau.mp3")} volume={0.8} /></Sequence>
      {[t(6), t(7), t(10), t(12)].map((x, i) => (
        <Sequence key={i} from={Math.max(0, sec(x) - 8)}><Audio src={staticFile("son/souffle.mp3")} volume={0.6} /></Sequence>
      ))}
      {f < 0 && null}
    </AbsoluteFill>
  );
};
