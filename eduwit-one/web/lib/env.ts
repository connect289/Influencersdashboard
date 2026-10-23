import "server-only";
import { z } from "zod";

// The bootstrap set (spec standard 3): only what the app needs before it can read one.settings. Everything else is
// runtime configuration. Names are Eduwit One's own: the build environment's generic SUPABASE_* variables belong to
// another project and are never read (D-013, CLAUDE.md environment note).
const schema = z.object({
  ONE_SUPABASE_URL: z.url().optional(),
  ONE_SUPABASE_SERVICE_KEY: z.string().min(20).optional(),
  ONE_INTERNAL_KEY: z.string().min(32).optional(),
});

export type BootEnv = z.infer<typeof schema>;

let cached: BootEnv | undefined;

export function bootEnv(): BootEnv {
  cached ??= schema.parse({
    ONE_SUPABASE_URL: process.env.ONE_SUPABASE_URL || undefined,
    ONE_SUPABASE_SERVICE_KEY: process.env.ONE_SUPABASE_SERVICE_KEY || undefined,
    ONE_INTERNAL_KEY: process.env.ONE_INTERNAL_KEY || undefined,
  });
  return cached;
}

/** First non-empty value among the names; the second name is the one the build environment already uses. */
export function secretEnv(...names: string[]): string | undefined {
  for (const name of names) {
    const value = process.env[name]?.trim();
    if (value) return value;
  }
  return undefined;
}
