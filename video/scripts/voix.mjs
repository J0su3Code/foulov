// Génère chaque réplique (ElevenLabs eleven_v4, français) avec le minutage de chaque caractère,
// pour caler les textes animés sur la voix. Sortie : public/voix/<n>.mp3 et src/voix.json.
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
import { writeFile } from "node:fs/promises";
const c = new ElevenLabsClient();
const ELLE = "4SFJvuIUvxaPLgk8FoK3"; // Alimata (choisie le 21 nov. 2026)
const LUI = "M4ZqLOXSFqxSkn9RDxFO"; // Tony
const lignes = [
  [ELLE, "Il est minuit… et il m'écrit encore.", null],
  [LUI, "Mille kilomètres entre nous.", null],
  [ELLE, "Mais une seule bulle.", null],
  [LUI, "FouLove.", null],
  [ELLE, "Ici, il n'y a que nous deux. Nos mots doux, nos photos, nos vocaux.", null],
  [LUI, "Nos instants, qui s'effacent après vingt-quatre heures.", null],
  [ELLE, "Et tous nos souvenirs, rangés tout seuls.", null],
  [LUI, "J'ai même scellé une lettre. Elle ne pourra l'ouvrir que le jour de nos quatre ans.", null],
  [ELLE, "Tu me fais languir !", null],
  [LUI, "Pour l'inviter, un simple message. Nos téléphones se sont reconnus tout seuls.", null],
  [ELLE, "Et tout est chiffré de bout en bout.", null],
  [LUI, "Personne ne peut lire ce qu'on se dit.", null],
  [ELLE, "Pas même FouLove.", null],
  [ELLE, "Une bulle à deux.", null],
  [LUI, "Une bulle à deux.", null],
];
const seulement = process.argv[2] ? process.argv[2].split(",").map(Number) : null;
const sortie = [];
for (const [i, [voix, texte, affiche]] of lignes.entries()) {
  if (seulement && !seulement.includes(i + 1)) continue;
  // Chaque réplique seule (sans enchaînement) : l'enchaînement lissait l'accent.
  // Elle : eleven_v4 ; lui : multilingue v2, plus fidèle à sa voix d'origine.
  const r = await c.textToSpeech.convertWithTimestamps(voix, voix === ELLE
    ? { text: texte, modelId: "eleven_v4", languageCode: "fr", outputFormat: "mp3_44100_128" }
    : { text: texte, modelId: "eleven_multilingual_v2", outputFormat: "mp3_44100_128",
        voiceSettings: { stability: 0.45, similarityBoost: 0.9, style: 0.25, useSpeakerBoost: true } });
  await writeFile(`public/voix/${String(i + 1).padStart(2, "0")}.mp3`, Buffer.from(r.audioBase64, "base64"));
  const a = r.alignment;
  sortie.push({ n: i + 1, voix: voix === ELLE ? "elle" : "lui", texte: affiche ?? texte,
    fin: a.characterEndTimesSeconds.at(-1), chars: a.characters, debuts: a.characterStartTimesSeconds });
  console.log("ok", i + 1, a.characterEndTimesSeconds.at(-1).toFixed(2), "s");
}
if (!seulement) await writeFile("src/voix.json", JSON.stringify(sortie));
