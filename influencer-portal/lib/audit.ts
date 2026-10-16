import { z } from "zod";

/** Filters for the audit log viewer, parsed from the URL (never trusted). */
export const auditFilterSchema = z.object({
  entity: z
    .string()
    .regex(/^[a-z_]{2,40}$/)
    .optional()
    .catch(undefined),
  action: z
    .string()
    .regex(/^[a-z_]{2,40}$/)
    .optional()
    .catch(undefined),
  actor: z.uuid().optional().catch(undefined),
  from: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .catch(undefined),
  to: z
    .string()
    .regex(/^\d{4}-\d{2}-\d{2}$/)
    .optional()
    .catch(undefined),
  before: z.coerce.number().int().positive().optional().catch(undefined),
});
export type AuditFilter = z.infer<typeof auditFilterSchema>;

export const AUDIT_PAGE_SIZE = 50;

/** IST calendar day → UTC instant range [start, end). */
export function istDayStart(day: string): string {
  return new Date(`${day}T00:00:00+05:30`).toISOString();
}
export function istDayEnd(day: string): string {
  const d = new Date(`${day}T00:00:00+05:30`);
  d.setUTCDate(d.getUTCDate() + 1);
  return d.toISOString();
}

export function auditQueryString(f: AuditFilter, overrides: Partial<AuditFilter> = {}): string {
  const merged = { ...f, ...overrides };
  const p = new URLSearchParams();
  for (const [k, v] of Object.entries(merged) as [string, string | number | undefined][])
    if (v !== undefined) p.set(k, String(v));
  const s = p.toString();
  return s ? `?${s}` : "";
}
