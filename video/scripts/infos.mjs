// Offre du compte et voix françaises disponibles (lecture seule).
import { ElevenLabsClient } from "@elevenlabs/elevenlabs-js";
const c = new ElevenLabsClient();
const sub = await c.user.subscription.get();
console.log("offre :", sub.tier, "| caractères utilisés :", sub.characterCount, "/", sub.characterLimit);
const shared = await c.voices.getShared({ pageSize: 30, language: "fr", search: "africain" });
for (const v of shared.voices) console.log("bibliothèque :", v.voiceId, "|", v.name, "|", v.gender, "|", v.accent, "|", v.age, "|", (v.description || "").slice(0, 70));
const shared2 = await c.voices.getShared({ pageSize: 30, language: "fr", accent: "african" });
for (const v of shared2.voices) console.log("accent african :", v.voiceId, "|", v.name, "|", v.gender, "|", v.accent, "|", (v.description || "").slice(0, 70));
