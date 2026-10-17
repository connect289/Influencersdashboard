// Quiet hours (setting notifications.delivery, IST): WhatsApp messages and digests wait until the quiet period ends;
// in-app and email notifications are never held. Windows may cross midnight (21:00–09:00). Pure.

const IST_OFFSET_MIN = 330;

function minutesIst(d: Date): number {
  return (d.getUTCHours() * 60 + d.getUTCMinutes() + IST_OFFSET_MIN) % 1440;
}

function toMin(hhmm: string): number {
  const [h, m] = hhmm.split(":").map(Number) as [number, number];
  return h * 60 + m;
}

export function inQuietHours(at: Date, start: string, end: string): boolean {
  const s = toMin(start);
  const e = toMin(end);
  if (s === e) return false;
  const t = minutesIst(at);
  return s < e ? t >= s && t < e : t >= s || t < e;
}

/** When a held message may go out: the end of the current quiet period, or `at` itself outside quiet hours. */
export function sendAfterQuiet(at: Date, start: string, end: string): Date {
  if (!inQuietHours(at, start, end)) return at;
  const wait = (toMin(end) - minutesIst(at) + 1440) % 1440;
  const out = new Date(at.getTime() + wait * 60_000);
  out.setUTCSeconds(0, 0);
  return out;
}
