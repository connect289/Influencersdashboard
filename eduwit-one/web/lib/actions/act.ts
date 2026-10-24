import "server-only";
import { log } from "../log.ts";
import { assertUser } from "../session.ts";
import { ui, UiError } from "../ui/api.ts";
import { okSchema } from "../ui/schemas.ts";

// Server actions: validate the form (zod), call one one.ui_* function with a fresh request id, map a refusal to a
// message. The database checks the role again (one.ui_require). An action does not revalidate: every console page is
// dynamic, and ActionForm refreshes the page itself once the answer is shown, so a refresh can never hold the answer
// back (the click-through saw answers lost while a revalidated tree was being applied).

export type ActionResult = { ok: true; message?: string } | { ok: false; error: string };
export type Action = (prev: ActionResult | undefined, form: FormData) => Promise<ActionResult>;

export async function act(fn: string, args: Record<string, unknown>, message?: string): Promise<ActionResult> {
  const requestId = crypto.randomUUID();
  try {
    await assertUser();
    await ui(fn, okSchema, { ...args, p_request_id: requestId });
  } catch (e) {
    if (e instanceof UiError) return { ok: false, error: e.message };
    log("error", "action.failed", { fn, requestId, error: e instanceof Error ? e.message : "error" });
    return { ok: false, error: "That did not work. Try again." };
  }
  return { ok: true, message };
}

/** The first problem zod found, as a sentence. */
export function invalid(issues: Array<{ message: string }>): ActionResult {
  return { ok: false, error: issues[0]?.message ?? "Check the form." };
}

/** FormData as a plain object (one value per name), for zod. */
export function fields(form: FormData): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of form.entries()) if (typeof v === "string") out[k] = v;
  return out;
}
