// Uniform result for server actions called from client components.
export type ActionResult<T = undefined> = { ok: true; data?: T; message?: string } | { ok: false; error: string };

export function fail(error: string): ActionResult<never> {
  return { ok: false, error };
}
