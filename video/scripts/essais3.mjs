import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
import { writeFile } from "node:fs/promises";
const c = new ElevenLabsClient();
const texte = "Il est minuit… et il m'écrit encore. Ici, il n'y a que nous deux : nos mots doux, nos photos, nos vocaux.";
const essais = [
  ["A-fatou", "Vza9yt3uSx3RXnRx6YfI", { modelId: "eleven_v4", languageCode: "fr" }],
  ["B-alimata", "4SFJvuIUvxaPLgk8FoK3", { modelId: "eleven_v4", languageCode: "fr" }],
  ["C-alimata-multilingue", "4SFJvuIUvxaPLgk8FoK3", { modelId: "eleven_multilingual_v2",
    voiceSettings: { stability: 0.45, similarityBoost: 0.9, style: 0.25, useSpeakerBoost: true } }],
];
for (const [nom, v, opts] of essais) {
  const a = await c.textToSpeech.convert(v, { text: texte, outputFormat: "mp3_44100_128", ...opts });
  const ch = []; for await (const x of a) ch.push(Buffer.from(x));
  await writeFile(`public/voix/essais3/${nom}.mp3`, Buffer.concat(ch)); console.log("ok", nom);
}
