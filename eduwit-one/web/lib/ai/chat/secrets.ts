// A message that looks like it carries a secret is not sent to the model and not stored (D-094: no secrets in chat).
// The shapes: vendor key prefixes, a JWT, a long run of token characters, or a line that names a key and gives one.

const PREFIXES =
  /\b(sk-ant-[A-Za-z0-9_-]{10,}|sk-[A-Za-z0-9_-]{20,}|re_[A-Za-z0-9_-]{12,}|sb_(secret|publishable)_[A-Za-z0-9_-]{8,}|sbp_[A-Za-z0-9]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16}|EAA[A-Za-z0-9]{40,}|n8n_api_[A-Za-z0-9]{10,})/;
const JWT = /\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b/;
const LONG_TOKEN = /(?<![A-Za-z0-9_/+=-])[A-Za-z0-9_/+=-]{40,}(?![A-Za-z0-9_/+=-])/;
const LABELLED =
  /\b(api[ _-]?key|secret|token|password|passcode|service[ _-]?role|access[ _-]?key|private[ _-]?key)\b\s*[:=]\s*\S{12,}/i;
const CONNECTION_STRING = /\bpostgres(ql)?:\/\/[^\s]+:[^\s]+@/i;

/** True when the text seems to carry a key, a token, a password or a connection string. */
export function looksLikeSecret(text: string): boolean {
  if (PREFIXES.test(text) || JWT.test(text) || CONNECTION_STRING.test(text) || LABELLED.test(text)) return true;
  // A long opaque token, unless it is a URL path or a hash-looking id inside a sentence of ordinary words.
  const m = LONG_TOKEN.exec(text);
  if (!m) return false;
  const token = m[0];
  if (/^[0-9a-f]+$/i.test(token) && token.length <= 64) return false; // a hex id (a request id, a sha)
  if (/^[A-Za-z]+$/.test(token)) return false; // a very long word
  return true;
}
