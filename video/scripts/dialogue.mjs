// Le dialogue d'Inès et Sami en UNE génération (ElevenLabs Text to Dialogue, eleven_v4) : les deux voix se
// répondent, avec des indications d'émotion. Sortie : public/voix/dialogue-<prise>.mp3 et src/dialogue-<prise>.json
// (début et fin de chaque réplique, minutage des caractères pour les textes animés).
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
import { writeFile } from "node:fs/promises";
const c = new ElevenLabsClient();
const ELLE = "4SFJvuIUvxaPLgk8FoK3"; // Alimata
const LUI = "M4ZqLOXSFqxSkn9RDxFO"; // Tony
const repliques = [
  [ELLE, "[whispers] Il est minuit… et il m'écrit encore."],
  [LUI, "[softly] Mille kilomètres entre nous…"],
  [ELLE, "[smiling] Mais une seule bulle."],
  [LUI, "FouLove."],
  [ELLE, "Ici, il n'y a que nous deux. Nos mots doux, nos photos, nos vocaux…"],
  [LUI, "Nos instants, qui s'effacent après vingt-quatre heures."],
  [ELLE, "Et tous nos souvenirs, rangés tout seuls."],
  [LUI, "[teasing] J'ai même scellé une lettre. Tu ne pourras l'ouvrir que le jour de nos quatre ans."],
  [ELLE, "[laughs] Tu me fais languir !"],
  [LUI, "Pour t'inviter, un simple message. Nos téléphones se sont reconnus tout seuls."],
  [ELLE, "Et tout est chiffré de bout en bout."],
  [LUI, "Personne ne peut lire ce qu'on se dit."],
  [ELLE, "[whispers] Pas même FouLove."],
  [LUI, "[softly] Une bulle…"],
  [ELLE, "[smiling] …à deux."],
];
const prise = process.argv[2] ?? "1";
const r = await c.textToDialogue.convertWithTimestamps({
  inputs: repliques.map(([voiceId, text]) => ({ voiceId, text })),
  modelId: "eleven_v4", languageCode: "fr", outputFormat: "mp3_44100_128",
  seed: Number(prise) * 7919,
});
await writeFile(`public/voix/dialogue-${prise}.mp3`, Buffer.from(r.audioBase64, "base64"));
const a = r.alignment;
const segments = r.voiceSegments.map((s) => ({ n: s.dialogueInputIndex + 1, voix: s.voiceId === ELLE ? "elle" : "lui",
  debut: s.startTimeSeconds, fin: s.endTimeSeconds, texte: repliques[s.dialogueInputIndex][1].replace(/\[[^\]]+\]\s*/g, "") }));
await writeFile(`src/dialogue-${prise}.json`, JSON.stringify({ segments, chars: a?.characters, debuts: a?.characterStartTimesSeconds }));
for (const s of segments) console.log(s.n, s.voix, s.debut.toFixed(2), "→", s.fin.toFixed(2), s.texte);
