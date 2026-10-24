"use server";
import { z } from "zod";
import { act, fields, invalid, type ActionResult } from "./act.ts";

const jsonText = z
  .string()
  .trim()
  .transform((s, ctx) => {
    if (!s) return undefined;
    try {
      const v: unknown = JSON.parse(s);
      if (typeof v !== "object" || v === null || Array.isArray(v)) throw new Error("not an object");
      return v as Record<string, unknown>;
    } catch {
      ctx.addIssue({ code: "custom", message: "The change must be a JSON object." });
      return z.NEVER;
    }
  });

export async function decide(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({
      id: z.coerce.number().int().positive(),
      decision: z.enum(["approve", "reject", "snooze"]),
      note: z.string().trim().max(1000).optional(),
      change: jsonText.optional(),
      snooze_days: z.coerce.number().int().min(1).max(30).optional(),
    })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  const d = p.data;
  const done = { approve: "Approved.", reject: "Rejected.", snooze: `Snoozed for ${d.snooze_days ?? 0} days.` }[
    d.decision
  ];
  return act(
    "ui_proposal_decide",
    {
      p_id: d.id,
      p_decision: d.decision,
      p_note: d.note ?? null,
      p_change: d.change ?? null,
      p_snooze_days: d.snooze_days ?? null,
    },
    done,
  );
}

export async function create(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({
      kind: z.enum(["fix", "feature", "config", "cleanup"]),
      app: z.enum(["witty", "b2b", "b2c", "web", "influencer", "one", "platform", "catalogue", "integrity"]),
      title: z.string().trim().min(5, "A title of at least 5 characters.").max(200),
      rationale: z.string().trim().min(10, "Say why, in at least 10 characters.").max(4000),
      change: jsonText.optional(),
      risk: z.enum(["low", "medium", "high"]),
      incident_id: z.coerce.number().int().positive().optional(),
    })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  const d = p.data;
  return act(
    "ui_proposal_create",
    {
      p_kind: d.kind,
      p_app: d.app,
      p_title: d.title,
      p_rationale: d.rationale,
      p_change: d.change ?? {},
      p_risk: d.risk,
      p_incident_id: d.incident_id ?? null,
    },
    "Proposal created.",
  );
}
