// Mêmes voix (Fatou, Tony), modèle multilingue v2, sans enchaînement entre répliques : accent d'origine.
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
import { writeFile } from "node:fs/promises";
const c = new ElevenLabsClient();
const ELLE = "Vza9yt3uSx3RXnRx6YfI", LUI = "M4ZqLOXSFqxSkn9RDxFO";
const lignes = [
  ["1-elle", ELLE, "Il est minuit… et il m'écrit encore."],
  ["2-lui", LUI, "Mille kilomètres entre nous."],
  ["5-elle", ELLE, "Ici, il n'y a que nous deux. Nos mots doux, nos photos, nos vocaux."],
  ["8-lui", LUI, "J'ai même scellé une lettre. Elle ne pourra l'ouvrir que le jour de nos quatre ans."],
];
for (const [nom, v, texte] of lignes) {
  const a = await c.textToSpeech.convert(v, { text: texte, modelId: "eleven_multilingual_v2", outputFormat: "mp3_44100_128",
    voiceSettings: { stability: 0.45, similarityBoost: 0.9, style: 0.25, useSpeakerBoost: true } });
  const ch = []; for await (const x of a) ch.push(Buffer.from(x));
  await writeFile(`public/voix/essais2/${nom}.mp3`, Buffer.concat(ch)); console.log("ok", nom);
}
