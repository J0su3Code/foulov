import { continueRender, delayRender, staticFile } from "remotion";

// Fraunces (titres) et Atkinson Hyperlegible Next (sous-titres), les polices du site.
const attente = delayRender("polices");
const polices = [
  new FontFace("Fraunces FouLove", `url(${staticFile("fonts/fraunces-normal.woff2")})`, { weight: "500 650" }),
  new FontFace("Fraunces FouLove", `url(${staticFile("fonts/fraunces-italic.woff2")})`, { weight: "500 650", style: "italic" }),
  new FontFace("Atkinson", `url(${staticFile("fonts/atkinson.woff2")})`, { weight: "200 800" }),
];
Promise.all(polices.map((p) => p.load())).then((ok) => {
  ok.forEach((p) => document.fonts.add(p));
  continueRender(attente);
});
