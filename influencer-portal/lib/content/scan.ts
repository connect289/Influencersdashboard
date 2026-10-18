import "server-only";
// The automatic compliance scan of a submission (spec 10.2, 16), run on the server right after the creator submits.
// Results are recorded with the service role (inf.compliance_record refuses anyone else), so a client can never
// report a clean scan for itself.
import { z } from "zod";
import type { Platform } from "@/lib/creators/schemas";
import type { Json } from "@/lib/database.types";
import { SETTINGS } from "@/lib/settings/registry";
import { adminClient } from "@/lib/supabase/admin";
import { scanSubmission, type BannedClaim, type ScanResult } from "./compliance";

const claims = z.array(
  z.object({
    id: z.string(),
    pattern: z.string(),
    kind: z.enum(["phrase", "regex"]),
    severity: z.enum(["block", "warn"]),
    note: z.string().nullable(),
  }),
) satisfies z.ZodType<BannedClaim[]>;

/** Scans the text of a submission (script, caption, notes) and records both checks. */
export async function scanAndRecord(input: {
  submissionId: string;
  kind: "concept" | "draft";
  platform: Platform;
  text: string;
}): Promise<ScanResult> {
  const db = adminClient();
  const [list, setting] = await Promise.all([
    db.rpc("banned_claims_active"),
    db.rpc("setting", { p_key: "content.review" }),
  ]);
  if (list.error) throw new Error(list.error.message);
  const review = SETTINGS["content.review"].schema.catch(SETTINGS["content.review"].default).parse(setting.data);
  const result = scanSubmission(input.text, input.kind, input.platform, claims.parse(list.data), review);
  const blocking = result.claims.filter((m) => m.severity === "block");
  const matches = result.claims.slice(0, 50).map((m) => ({
    claim_id: m.claim_id,
    severity: m.severity,
    text: m.text,
    index: m.index,
    note: m.note,
  }));
  const checks: { kind: string; passed: boolean; result: Json }[] = [
    { kind: "banned_claims", passed: blocking.length === 0, result: { claims: matches } },
  ];
  const d = result.disclosure;
  if (d)
    checks.push({
      kind: "disclosure",
      passed: !d.required || d.present,
      result: { required: d.required, present: d.present, found: d.found },
    });
  const { error } = await db.rpc("compliance_record", {
    p_submission: input.submissionId,
    p_checks: checks,
  });
  if (error) throw new Error(error.message);
  return result;
}
