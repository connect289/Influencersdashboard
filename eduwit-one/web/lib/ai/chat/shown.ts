// The arguments an action card showed, as its Confirm button sends them back (0031, D-115): the database runs the action
// only if they are the stored ones. Anything that is not a JSON object of at most 20 kB is no card's.

const MAX_CHARS = 20_000;

export function shownArgs(raw: unknown): Record<string, unknown> | null {
  if (typeof raw !== "string" || raw.length === 0 || raw.length > MAX_CHARS) return null;
  try {
    const v: unknown = JSON.parse(raw);
    return v !== null && typeof v === "object" && !Array.isArray(v) ? (v as Record<string, unknown>) : null;
  } catch {
    return null;
  }
}
