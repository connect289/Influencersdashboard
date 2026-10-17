/**
 * Junk-risk score for a gate or form attempt (spec 7.2). 0 = looks genuine, 100 = almost certainly junk. It never blocks
 * on its own: it is stored on the attempt (and passed to the lead once A-LEAD-3 is approved), and unverified attempts
 * above 50 are never pushed as leads. Inputs are already validated and normalised.
 */
export interface JunkInput {
  name: string;
  phone: string; // E.164 +91XXXXXXXXXX
  email: string;
}

export interface JunkResult {
  score: number;
  reasons: string[];
}

const TEST_WORDS = /\b(test|testing|asdf|qwerty|abc|xyz|dummy|fake|sample|na|none|nil|demo)\b/i;
const KEYBOARD = /(asdf|qwer|zxcv|hjkl|1234|abcd)/i;

function maxRun(s: string): number {
  let best = 1;
  let run = 1;
  for (let i = 1; i < s.length; i++) {
    run = s[i] === s[i - 1] ? run + 1 : 1;
    best = Math.max(best, run);
  }
  return best;
}

function sequential(digits: string): boolean {
  let up = 1;
  let down = 1;
  for (let i = 1; i < digits.length; i++) {
    const d = Number(digits[i]) - Number(digits[i - 1]);
    up = d === 1 ? up + 1 : 1;
    down = d === -1 ? down + 1 : 1;
    if (up >= 7 || down >= 7) return true;
  }
  return false;
}

export function junkScore(i: JunkInput): JunkResult {
  const reasons: string[] = [];
  let score = 0;
  const add = (points: number, reason: string) => {
    score += points;
    reasons.push(reason);
  };

  const digits = i.phone.replace(/\D/g, "").slice(-10);
  if (maxRun(digits) >= 6) add(35, "phone_repeated_digits");
  if (sequential(digits)) add(30, "phone_sequential");
  if (new Set(digits).size <= 3) add(20, "phone_low_variety");

  const name = i.name.trim();
  if (TEST_WORDS.test(name)) add(35, "name_test_word");
  if (KEYBOARD.test(name.replace(/\s/g, ""))) add(25, "name_keyboard_pattern");
  if (/(.)\1\1/i.test(name.replace(/\s/g, ""))) add(15, "name_repeated_letters");
  if (name.replace(/[^\p{L}]/gu, "").length < 3) add(10, "name_very_short");

  const [local = "", domain = ""] = i.email.split("@");
  if (TEST_WORDS.test(local.replace(/[._\-+\d]/g, " "))) add(25, "email_test_word");
  if (KEYBOARD.test(local)) add(20, "email_keyboard_pattern");
  const letters = local.replace(/[^a-z]/g, "");
  if (letters.length >= 8 && !/[aeiou]/.test(letters)) add(20, "email_no_vowels");
  if (/^\d+$/.test(local) && local.length >= 8 && local.includes(digits.slice(-8)) === false) add(5, "email_numeric");
  if (/^(example|test|mailinator)\./.test(domain)) add(30, "email_test_domain");

  return { score: Math.min(100, score), reasons };
}
