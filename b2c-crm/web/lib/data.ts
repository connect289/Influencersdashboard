import "server-only";
import { ZodError } from "zod";
import { createClient } from "@/lib/supabase/server";

/**
 * Calls a b2c.* function as the signed-in person. The function does the permission check (b2c.require, require_lead)
 * and raises a plain-English message, which is what the screen shows.
 */
export async function rpc<T = unknown>(fn: string, args: Record<string, unknown> = {}): Promise<T> {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new RpcError(error.message, error.code);
  return data as T;
}

export class RpcError extends Error {
  constructor(message: string, readonly code?: string) {
    super(message);
  }
}

/** Server-action result: the screen shows `error` as written, or `notice` as a toast. */
export type ActionResult<T = unknown> = { ok: true; data?: T; notice?: string } | { ok: false; error: string };

/** Runs a database call for a server action and turns a raised exception into a message for the person. */
export async function act<T>(run: () => Promise<T>, notice?: string): Promise<ActionResult<T>> {
  try {
    const data = await run();
    return { ok: true, data, notice };
  } catch (e) {
    return { ok: false, error: friendly(e) };
  }
}

export function friendly(e: unknown): string {
  if (e instanceof ZodError) return e.issues[0]?.message ?? "Check what you entered.";
  const msg = e instanceof Error ? e.message : String(e);
  if (/not allowed|permission denied|42501/i.test(msg)) return "You are not allowed to do that.";
  if (/PGRST106/.test(msg)) return "The app cannot reach its data yet (the b2c schema is not exposed).";
  return msg.length > 300 ? msg.slice(0, 300) + "…" : msg;
}
