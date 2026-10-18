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

/**
 * The composer shows "@Name" for a picked colleague; before sending, each "@Name" still in the text becomes a token
 * (longest names first, so "@Asha Rao" wins over "@Asha"; a token starts "@[", so a shorter name never matches inside
 * one). Names removed from the text are simply not mentioned.
 */
export function encodeMentions(body: string, picked: readonly { name: string; userId: string }[]): string {
  return [...picked]
    .sort((a, b) => b.name.length - a.name.length)
    .reduce((out, p) => out.split(`@${p.name}`).join(mentionToken(p.name, p.userId)), body);
}

/** Whether a thread has messages from others newer than the reader's last visit. */
export function hasUnread(
  messages: readonly { mine: boolean; created_at: string }[],
  myReadAt: string | null,
): boolean {
  const seen = myReadAt ? new Date(myReadAt).getTime() : -Infinity;
  return messages.some((m) => !m.mine && new Date(m.created_at).getTime() > seen);
}
