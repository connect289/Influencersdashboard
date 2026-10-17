import "server-only";
import { cacheLife, cacheTag } from "next/cache";
import { z } from "zod";
import { env, isProduction } from "./env";
import { log } from "./log";

/**
 * Creator (influencer) landing pages, spec 9.3 / D-018. The Influencer Portal's public read-only API is not live yet, so
 * the site reads creators through this typed provider: HTTP when `CREATOR_API_URL` is set, otherwise a mock with one
 * demo creator outside production. Without a provider in production, /c/<handle> renders a neutral referral page that
 * never claims an endorsement (nobody can make the site say "Recommended by <anyone>").
 */
export const creatorSchema = z.object({
  handle: z.string().regex(/^[a-z0-9_.-]{2,40}$/),
  display_name: z.string().min(1).max(80),
  photo_url: z.url().optional().nullable(),
  bio: z.string().max(280).optional().nullable(),
  code: z.string().regex(/^[a-z0-9_-]{2,40}$/i),
  featured: z.array(z.object({ title: z.string().max(120), href: z.string().startsWith("/") })).max(6).default([]),
});
export type Creator = z.infer<typeof creatorSchema>;

export interface CreatorProvider {
  readonly name: "http" | "mock" | "none";
  get(handle: string): Promise<Creator | null>;
}

const MOCK: Creator[] = [
  {
    handle: "demo-creator",
    display_name: "Demo Creator",
    photo_url: null,
    bio: "Sample creator used in development and tests (D-018).",
    code: "demo-creator",
    featured: [
      { title: "Online MBA", href: "/programmes/online-mba" },
      { title: "Online BCA", href: "/programmes/online-bca" },
      { title: "Online MCA", href: "/programmes/online-mca" },
    ],
  },
];

const mockProvider: CreatorProvider = { name: "mock", get: async (h) => MOCK.find((c) => c.handle === h) ?? null };
const noProvider: CreatorProvider = { name: "none", get: async () => null };
const httpProvider = (base: string): CreatorProvider => ({
  name: "http",
  async get(handle) {
    const res = await fetch(new URL(`creators/${encodeURIComponent(handle)}`, base.endsWith("/") ? base : `${base}/`), {
      signal: AbortSignal.timeout(4000),
      headers: { accept: "application/json" },
    });
    if (res.status === 404) return null;
    if (!res.ok) throw new Error(`creator api ${res.status}`);
    const parsed = creatorSchema.safeParse(await res.json());
    if (!parsed.success) {
      log("warn", "creator.invalid_payload", { handle });
      return null;
    }
    return parsed.data;
  },
});

export function creatorProvider(): CreatorProvider {
  const url = env().CREATOR_API_URL;
  if (url) return httpProvider(url);
  return isProduction() ? noProvider : mockProvider;
}

export async function getCreator(handle: string): Promise<Creator | null> {
  "use cache";
  cacheLife("hours");
  cacheTag("creators", `creator:${handle}`);
  if (!/^[a-z0-9_.-]{2,40}$/.test(handle)) return null;
  try {
    return await creatorProvider().get(handle);
  } catch (e) {
    log("warn", "creator.fetch_failed", { handle, message: e instanceof Error ? e.message : String(e) });
    return null;
  }
}
