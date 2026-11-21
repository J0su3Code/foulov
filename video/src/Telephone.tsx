import React from "react";
import { AbsoluteFill, Img, OffthreadVideo, staticFile } from "remotion";

// Cadre de téléphone : l'écran affiche un vrai enregistrement de l'app (barre d'état de l'émulateur retirée,
// remplacée par une barre propre « 9:41 »).
export const Telephone: React.FC<{
  hauteur: number;
  video?: string;
  image?: string;
  debut?: number; // seconde de départ dans le clip
  vitesse?: number;
  sombre?: boolean; // texte de la barre d'état en clair (sur photo)
  style?: React.CSSProperties;
  children?: React.ReactNode;
}> = ({ hauteur, video, image, debut = 0, vitesse = 1, sombre = false, style, children }) => {
  const largeur = hauteur * (1080 / 2400);
  const bord = hauteur * 0.018;
  const rayon = hauteur * 0.07;
  const encre = sombre ? "#fff" : "#2b1a22";
  return (
    <div
      style={{
        width: largeur + bord * 2,
        height: hauteur + bord * 2,
        padding: bord,
        borderRadius: rayon + bord,
        background: "linear-gradient(150deg,#3b2a33,#120a0f 60%,#2a1d24)",
        boxShadow: `inset 0 0 0 ${hauteur * 0.0025}px rgba(255,255,255,.14), 0 ${hauteur * 0.05}px ${hauteur * 0.1}px -${hauteur * 0.03}px rgba(110,20,60,.55)`,
        ...style,
      }}
    >
      <div style={{ position: "relative", width: largeur, height: hauteur, borderRadius: rayon, overflow: "hidden", background: "#fff8f5" }}>
        {video && (
          <OffthreadVideo
            src={staticFile(`clips/${video}.mp4`)}
            startFrom={Math.round(debut * 30)}
            playbackRate={vitesse}
            muted
            style={{ position: "absolute", top: hauteur * (112 / 2400), left: 0, width: largeur, height: hauteur * (2288 / 2400), objectFit: "cover" }}
          />
        )}
        {image && (
          <Img src={staticFile(`img/${image}.png`)} style={{ position: "absolute", top: hauteur * (112 / 2400), left: 0, width: largeur, height: hauteur * (2288 / 2400), objectFit: "cover" }} />
        )}
        {/* Barre d'état : prolonge le haut de l'écran filmé */}
        <div style={{ position: "absolute", inset: `0 0 auto 0`, height: hauteur * (112 / 2400), background: sombre ? "linear-gradient(#0006,#0000)" : "#fdf5f3" }} />
        <div
          style={{
            position: "absolute", top: hauteur * 0.016, left: largeur * 0.08, right: largeur * 0.08, display: "flex",
            justifyContent: "space-between", alignItems: "center", color: encre, fontFamily: "system-ui, -apple-system, Roboto",
            fontWeight: 600, fontSize: hauteur * 0.018,
          }}
        >
          <span>9:41</span>
          <span style={{ width: hauteur * 0.014, height: hauteur * 0.014, borderRadius: 99, background: "#0b0709" }} />
          <span style={{ display: "flex", gap: hauteur * 0.004, alignItems: "flex-end" }}>
            {[0.45, 0.65, 0.85, 1].map((h, i) => (
              <i key={i} style={{ width: hauteur * 0.0032, height: hauteur * 0.012 * h, background: encre, borderRadius: 1 }} />
            ))}
            <b style={{ marginLeft: hauteur * 0.006, width: hauteur * 0.022, height: hauteur * 0.011, border: `${hauteur * 0.0012}px solid ${encre}`, borderRadius: hauteur * 0.003, padding: hauteur * 0.0012, display: "flex" }}>
              <b style={{ flex: 0.8, background: encre, borderRadius: hauteur * 0.0015 }} />
            </b>
          </span>
        </div>
        <AbsoluteFill>{children}</AbsoluteFill>
      </div>
    </div>
  );
};
