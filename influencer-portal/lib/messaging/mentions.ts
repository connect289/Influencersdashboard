// @mentions in messages (spec 14, staff only): the composer inserts "@[Name](user:<uuid>)"; the database records who
// was mentioned and notifies them; screens show "@Name". Pure.

const TOKEN_RE = /@\[([^\]\n]{1,80})\]\(user:([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\)/g;

export function mentionToken(name: string, userId: string): string {
  return `@[${name.replace(/[\]\n]/g, " ").trim()}](user:${userId})`;
}

/** Mentioned user ids, each once, in order. */
export function parseMentions(body: string): string[] {
  const out: string[] = [];
  for (const m of body.matchAll(TOKEN_RE)) if (m[2] && !out.includes(m[2])) out.push(m[2]);
  return out;
}

export type MessagePart = { kind: "text"; text: string } | { kind: "mention"; name: string; userId: string };

/** Splits a body into text and mentions for display. */
export function messageParts(body: string): MessagePart[] {
  const parts: MessagePart[] = [];
  let last = 0;
  for (const m of body.matchAll(TOKEN_RE)) {
    const at = m.index;
    if (at > last) parts.push({ kind: "text", text: body.slice(last, at) });
    parts.push({ kind: "mention", name: m[1] ?? "", userId: m[2] ?? "" });
    last = at + m[0].length;
  }
  if (last < body.length) parts.push({ kind: "text", text: body.slice(last) });
  return parts;
}

/** Plain text for notifications and search: mentions become "@Name". */
export function plainText(body: string): string {
  return body.replace(TOKEN_RE, (_, name: string) => `@${name}`);
}
