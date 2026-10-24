"use server";
import { z } from "zod";
import { act, fields, invalid, type ActionResult } from "./act.ts";

const fixId = z.string().regex(/^FIX-[A-Z0-9]+(-[A-Z0-9]+)*$/);

/** The owner switches a fix or changes its limits, with a reason (0019; the database refuses before the window ends). */
export async function setFix(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z
    .object({
      fix: fixId,
      enabled: z.enum(["on", "off"]),
      per_tick: z.coerce.number().int().min(1, "per_tick is 1 to 500.").max(500, "per_tick is 1 to 500."),
      cooldown_min: z.coerce
        .number()
        .int()
        .min(1, "The cooldown is 1 to 1440 minutes.")
        .max(1440, "The cooldown is 1 to 1440 minutes."),
      reason: z.string().trim().min(3, "Give a reason of at least 3 characters.").max(500),
    })
    .safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  const d = p.data;
  return act(
    "ui_fix_set",
    {
      p_fix: d.fix,
      p_patch: { enabled: d.enabled === "on", per_tick: d.per_tick, cooldown_min: d.cooldown_min },
      p_reason: d.reason,
    },
    d.enabled === "on" ? `${d.fix} is on.` : `${d.fix} saved.`,
  );
}

const dryRunSchema = z.looseObject({
  dry_run: z.boolean().optional(),
  applies: z.boolean().optional(),
  why_not: z.string().nullable().optional(),
  skipped: z.string().optional(),
  over_limit: z.boolean().optional(),
});

/** A dry run now on an open incident: it records what the fix would do and changes nothing. */
export async function dryRunFix(_: ActionResult | undefined, form: FormData): Promise<ActionResult> {
  const p = z.object({ fix: fixId, incident: z.coerce.number().int().positive() }).safeParse(fields(form));
  if (!p.success) return invalid(p.error.issues);
  return act("ui_fix_dry_run", { p_fix: p.data.fix, p_incident: p.data.incident }, (data) => {
    const r = dryRunSchema.safeParse(data).data;
    if (r?.dry_run)
      return r.over_limit ? "Recorded: too many rows, it would open a proposal." : "Dry run recorded below.";
    if (r?.skipped) return `Nothing recorded: ${r.skipped}.`;
    return `It does not apply now: ${r?.why_not ?? "nothing to do"}.`;
  });
}
