// Musique (ElevenLabs Music) et bruitages (Sound Effects) de la vidéo.
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
import { writeFile } from "node:fs/promises";
const c = new ElevenLabsClient();
const lire = async (s) => { const ch = []; for await (const x of s) ch.push(Buffer.from(x)); return Buffer.concat(ch); };
const quoi = process.argv[2] ?? "tout";
const seul = process.argv[3];
if (quoi === "tout" || quoi === "musique") {
  const audio = await c.music.compose({
    prompt:
      "Instrumental, 50 seconds, romantic and modern, for a love app ad about a long-distance couple. " +
      "0-6s: intimate night, soft felt piano and warm pad, very quiet. " +
      "At 6s a gentle drop: warm afro-pop groove, soft log drum, shakers, clean guitar riff, 104 BPM, joyful but tender. " +
      "Builds lightly until 40s, then breaks down to piano and resolves warmly at the end. No vocals, leave room for voice-over.",
    musicLengthMs: 50000,
    modelId: "music_v2_5",
    forceInstrumental: true,
  });
  await writeFile("public/son/musique.mp3", await lire(audio));
  console.log("musique ok");
}
if (quoi === "tout" || quoi === "bruits") {
  const sons = {
    notification: "A soft, modern phone message notification chime, two gentle notes, clean, no background",
    pop: "A tiny soft bubble pop with a warm sparkle, very short",
    souffle: "A deep, soft, warm whoosh, like a heavy fabric swept slowly through the air: woooosh. Low frequencies, rounded and smooth, no high-pitched swish, no zip, no whistle",
    sceau: "A soft wax seal stamp press on paper, gentle thud, short",
  };
  for (const [nom, texte] of Object.entries(sons)) {
    if (seul && nom !== seul) continue;
    const a = await c.textToSoundEffects.convert({ text: texte, durationSeconds: nom === "souffle" ? 1.4 : 1, promptInfluence: 0.6 });
    await writeFile(`public/son/${nom}.mp3`, await lire(a));
    console.log("son ok", nom);
  }
}
