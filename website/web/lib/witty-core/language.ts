import type { Language } from "./contract";

/** Reply language follows the student (english | hinglish | hindi). Short messages keep the previous language. */
const HINGLISH = /\b(hai|hain|kya|kaise|kitna|kitni|kitne|mujhe|mera|meri|karna|karni|chahiye|chahta|chahti|aap|aapka|mein|nahi|haan|batao|bata|kar|wala|wali|tha|thi|kiya|lena|padhna|abhi|jaldi|ke liye|kaun|kab|kyun|accha|achha|theek|thik)\b/gi;

export function detectLanguage(message: string, previous: Language = "english"): Language {
  if (/[ऀ-ॿ]/.test(message)) return "hindi";
  const words = message.trim().split(/\s+/).filter(Boolean);
  const hits = message.match(HINGLISH)?.length ?? 0;
  if (hits >= 2 || (hits >= 1 && words.length <= 4)) return "hinglish";
  if (words.length <= 2) return previous;
  return "english";
}
