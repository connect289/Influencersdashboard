import { z } from "zod";
import { PERIODS } from "@/lib/analytics";

/** Reports (B14.3): definitions for tabular, summary and matrix reports. Pure. */

export const FACT_LABEL: Record<string, string> = {
  fact_leads: "Leads", fact_allocations: "Leads routed to partners", fact_enrollments: "Enrolments", fact_sla: "SLA checks", fact_money: "Commission lines",
  fact_invoices: "Invoices", fact_notifications: "Student messages", fact_capi: "Conversions to ad platforms", fact_sync: "Partner sync events", fact_ai: "AI runs and recommendations",
};
export const KIND_LABEL = { tabular: "Tabular: a list of rows", summary: "Summary: metrics by a breakdown", matrix: "Matrix: one metric, rows by columns" } as const;
export type ReportKind = keyof typeof KIND_LABEL;

const filters = z.record(z.string().regex(/^[a-z_]{2,30}$/), z.array(z.string().max(200)).max(50));
export const ReportDefSchema = z.discriminatedUnion("kind", [
  z.object({ kind: z.literal("tabular"), definition: z.object({ fact: z.string().regex(/^fact_[a-z]+$/), columns: z.array(z.string().regex(/^[a-z_0-9]+$/)).min(1, "Choose columns").max(30),
    filters, period: z.enum(PERIODS), sort: z.string().optional(), desc: z.boolean().optional(), limit: z.number().int().min(1).max(5000).optional() }) }),
  z.object({ kind: z.literal("summary"), definition: z.object({ metrics: z.array(z.string()).min(1, "Choose metrics").max(12), dims: z.array(z.string()).min(1, "Choose a breakdown").max(2), filters, period: z.enum(PERIODS) }) }),
  z.object({ kind: z.literal("matrix"), definition: z.object({ metric: z.string().min(1, "Choose a metric"), row_dim: z.string().min(1, "Choose rows"), col_dim: z.string().min(1, "Choose columns"), filters, period: z.enum(PERIODS) })
    .refine((d) => d.row_dim !== d.col_dim, "Rows and columns need different breakdowns") }),
]);
export type ReportDef = z.infer<typeof ReportDefSchema>;

/** A definition in the URL (export of an unsaved report): base64url JSON. */
export const encodeDef = (d: ReportDef) => Buffer.from(JSON.stringify(d)).toString("base64url");
export function decodeDef(s: string): ReportDef | null {
  try { const r = ReportDefSchema.safeParse(JSON.parse(Buffer.from(s, "base64url").toString("utf8"))); return r.success ? r.data : null; } catch { return null; }
}
