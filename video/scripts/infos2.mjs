import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
const c = new ElevenLabsClient();
for (const q of [{ gender: "female", accent: "african" }, { gender: "female", search: "africaine" }]) {
  const r = await c.voices.getShared({ pageSize: 25, language: "fr", ...q });
  for (const v of r.voices) console.log(v.voiceId, "|", v.name, "|", v.age, "|", v.useCase, "|", (v.description || "").replace(/\s+/g, " ").slice(0, 90));
  console.log("--");
}
