import type { Ask, Language } from "./contract";

/**
 * Fixed texts and the engine's question for each ask (task.ask_text), in English and Hinglish. Sources: the counselor
 * and extractor prompts' examples (production w2_prompts v6) and the hand-off texts used live (witty.md §4.5). Lines
 * marked "web" have no published Witty wording and are the website's own (verified against Witty's ENGINE under A-AGENT-1).
 */
type Bi = { english: string; hinglish: string };
const pick = (t: Bi, lang: Language) => (lang === "english" ? t.english : t.hinglish);

const ASK_TEXT: Record<Exclude<Ask, "NONE">, Bi> = {
  ASK_NAME: { english: "By the way, what's your name so I can set up your profile properly?", hinglish: "Waise, aapka naam kya hai, taaki main aapki profile theek se bana sakoon?" },
  ASK_LAST_NAME: { english: "Could you share your last name too, so I can complete your profile?", hinglish: "Kya aap apna surname bhi bata sakte hain, taaki profile complete ho jaye?" },
  CONFIRM_NAME: { english: "Just to confirm, your name is {name}?", hinglish: "Confirm kar loon, aapka naam {name} hai?" },
  ASK_QUALIFICATION: { english: "What's your highest qualification so far?", hinglish: "Aapki highest qualification abhi tak kya hai?" },
  ASK_SCORE: { english: "What percentage or CGPA did you get in your {qualification}?", hinglish: "{qualification} mein aapke kitne percentage ya CGPA aaye the?" },
  ASK_QUAL_AND_SCORE: {
    english: "What's your highest qualification, and what percentage or CGPA did you get in it?",
    hinglish: "Aapki highest qualification kya hai, aur usme kitne percentage ya CGPA aaye the?",
  },
  ASK_QUAL_AND_COURSE: { english: "What's your highest qualification, and which course are you interested in?", hinglish: "Aapki highest qualification kya hai, aur aap kaunsa course karna chahte hain?" }, // web (hinglish)
  ASK_COURSE: { english: "What would you like to study? Do you have a course or field in mind?", hinglish: "Aap kya padhna chahte hain? Koi course ya field dimaag mein hai?" }, // web (hinglish)
  ASK_SPECIALIZATION: {
    english: "Do you have a specialization in mind (for example {examples})?",
    hinglish: "Kya aapke mann mein koi specialization hai (jaise {examples})?", // web (hinglish)
  },
  ASK_EMAIL: {
    english: "What's your email address? It helps us verify eligibility and connect you with a counselor if needed.",
    hinglish: "Aapka email address kya hai? Isse eligibility verify karne aur zarurat ho toh counselor se connect karne mein madad milti hai.",
  },
  ASK_BUDGET: { english: "Does that fee range work for you, or should I look at a different range?", hinglish: "Kya yeh fee range aapke liye theek hai, ya main kisi aur range mein dekhun?" },
  ASK_TIMELINE: { english: "When are you hoping to start: this session or later?", hinglish: "Aap kab se shuru karna chahte hain: isi session se ya baad mein?" },
  ASK_STUDY_MODE: { english: "Would you prefer online, ODL (distance) or regular on-campus classes?", hinglish: "Aap online, ODL (distance) ya regular on-campus classes mein se kya prefer karenge?" }, // web (hinglish)
  ASK_MOTIVATION: { english: "What's making you think about studying further right now?", hinglish: "Abhi aage padhne ka sochne ki main wajah kya hai?" }, // web (hinglish)
  ASK_UNIVERSITY: { english: "Do you have a university in mind?", hinglish: "Kya koi university aapke mann mein hai?" }, // web (hinglish)
  CONFIRM_COURSE: { english: "Just to confirm, you're interested in {course}?", hinglish: "Confirm kar loon, aap {course} karna chahte hain?" }, // web
  OFFER_HANDOFF: {
    english: "Would you like an academic counsellor to help you with the next steps?",
    hinglish: "Kya aap chahenge ki ek academic counsellor next steps mein aapki madad kare?", // web (hinglish)
  },
};

/** NO_MATCH / NOT_ELIGIBLE follow-up (counselor prompt examples). */
const DIFFERENT_COURSE: Bi = { english: "Would you like to look at a different course instead?", hinglish: "Kya aap koi aur course dekhna chahenge?" };

export function askText(ask: Ask, lang: Language, vars: Record<string, string> = {}): string {
  if (ask === "NONE") return "";
  const t = pick(ASK_TEXT[ask], lang);
  return t.replace(/\{(\w+)\}/g, (_, k: string) => vars[k] ?? "");
}
export function differentCourseText(lang: Language): string {
  return pick(DIFFERENT_COURSE, lang);
}

/** HANDOFF (fixed text, live wording): "Thank you{name}. An academic counsellor will contact you shortly about {course}." */
export function handoffText(lang: Language, firstName?: string | null, course?: string | null): string {
  const name = firstName ? ` ${firstName}` : "";
  return lang === "english"
    ? `Thank you${name}. An academic counsellor will contact you shortly about ${course || "your programme"}.`
    : `Thank you${name}. Ek academic counsellor jald hi aapse ${course || "aapke programme"} ke baare mein contact karenge.`;
}

/** Web-only fixed texts (the website's channel; Witty's WhatsApp "reply STOP" has no web equivalent). */
export function stopText(lang: Language): string {
  return lang === "english"
    ? "Okay, I'll stop here. You can come back any time, and you can manage or delete your data from your account."
    : "Theek hai, main yahin rukta hoon. Aap kabhi bhi wapas aa sakte hain, aur apna data account se manage ya delete kar sakte hain.";
}
export function erasureText(lang: Language): string {
  return lang === "english"
    ? "You can ask us to delete your data from your account page (Your data → Delete my data). We'll confirm by email."
    : "Aap apne account page se data delete karne ki request kar sakte hain (Your data → Delete my data). Hum email se confirm karenge.";
}
