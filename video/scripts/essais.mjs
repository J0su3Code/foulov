// Extraits pour choisir la voix : même texte, plusieurs voix (bibliothèque ElevenLabs, français, accent africain).
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
import { writeFile } from "node:fs/promises";
const c = new ElevenLabsClient();
const texte = "Il y a les messageries pour tout le monde. Et puis il y a FouLove : une bulle, rien que pour vous deux.";
const voix = {
  "1-fatou": "Vza9yt3uSx3RXnRx6YfI",
  "2-alimata": "4SFJvuIUvxaPLgk8FoK3",
  "3-tony": "M4ZqLOXSFqxSkn9RDxFO",
  "4-marco": "jTPvJ3iCi8GhXDwdQHLK",
  "5-idriss": "WFGpsFiyRV1Fv6MHC5tU",
  "6-esaie": "HbDa7eEZNGkUODgNzru6",
};
for (const [nom, id] of Object.entries(voix)) {
  try {
    const audio = await c.textToSpeech.convert(id, { text: texte, modelId: "eleven_v4", languageCode: "fr", outputFormat: "mp3_44100_128" });
    const chunks = []; for await (const ch of audio) chunks.push(ch);
    await writeFile(`public/voix/essais/${nom}.mp3`, Buffer.concat(chunks.map((x) => Buffer.from(x))));
    console.log("ok", nom);
  } catch (e) { console.log("échec", nom, e.statusCode ?? "", (e.body?.detail?.message ?? e.message ?? "").toString().slice(0, 140)); }
}
