import "server-only";
import { type z } from "zod";
import { userClient } from "../supabase.ts";

// One door for page reads and writes: the signed-in person's session calls a one.ui_* function and the answer is
// validated against its schema (spec standard 4). A refusal or a shape the page does not expect becomes a typed
// error, which the page shows; it never throws a raw database message into the UI.

export class UiError extends Error {
  readonly kind: "not_allowed" | "not_found" | "invalid" | "conflict" | "unavailable" | "shape";
  readonly code: string | undefined;

  constructor(kind: UiError["kind"], message: string, code?: string) {
    super(message);
    this.kind = kind;
    this.code = code;
  }
}

export const SETTING_CONFLICT = "Someone else changed this setting — reload and try again.";

/**
 * A refusal that names what only the owner may do (one.ui_mute on a P1 check or an app that has one, D-139) is shown
 * as the database worded it; every other 42501 keeps the one sentence, whatever its text.
 */
const OWNER_ONLY = /^only the owner can /i;

/** A database error code as the kind of refusal it is, and a message a person can act on. */
export function fromDbError(error: { code?: string; message?: string }): UiError {
  switch (error.code) {
    case "42501":
      return new UiError(
        "not_allowed",
        OWNER_ONLY.test(error.message ?? "") ? sentence(error.message) : "Your role cannot do this.",
        error.code,
      );
    case "P0002":
      return new UiError("not_found", sentence(error.message) || "Not found.", error.code);
    case "22023":
    case "23514":
    case "22P02":
      return new UiError("invalid", sentence(error.message) || "That value is not accepted.", error.code);
    case "40001":
      // A save over a version that is no longer current (one.ui_settings_put, D-137): nothing was saved.
      return new UiError("conflict", SETTING_CONFLICT, error.code);
    case "PGRST106":
      return new UiError(
        "unavailable",
        "Schema one is not exposed in the Supabase Data API (Setup item supabase_api_schema).",
        error.code,
      );
    case "PGRST202":
      // The function is not on this database: a page shipped before its migration was applied (RUNBOOK-database.md).
      return new UiError(
        "unavailable",
        "This page needs a database migration that is not applied here yet; the app is ahead of the database.",
        error.code,
      );
    default:
      // The client's 15 s limit cut the call (lib/fetch-timeout.ts, D-137): no code, the fetch error's name.
      if (!error.code && /^TimeoutError:/.test(error.message ?? ""))
        return new UiError("unavailable", "The database took too long to answer. Try again in a minute.", error.code);
      return new UiError("unavailable", "The database did not answer as expected. Try again.", error.code);
  }
}

function sentence(message: string | undefined): string {
  if (!message) return "";
  const m = message.replace(/^.*?ERROR:\s*/, "").trim();
  return `${m.charAt(0).toUpperCase()}${m.slice(1)}${/[.!?]$/.test(m) ? "" : "."}`;
}

/** Calls one.<fn> as the signed-in person and validates the answer. */
export async function ui<S extends z.ZodType>(
  fn: string,
  schema: S,
  args: Record<string, unknown> = {},
): Promise<z.infer<S>> {
  const { data, error } = await (await userClient()).rpc(fn, args);
  if (error) throw fromDbError(error);
  const parsed = schema.safeParse(data);
  if (!parsed.success) throw new UiError("shape", `one.${fn} answered in a shape this page does not expect.`);
  return parsed.data;
}
