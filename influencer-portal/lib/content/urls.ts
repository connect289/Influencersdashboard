// Live-post URLs (spec 10.2 go-live): the format each platform's post links take, normalised for storage, and the
// public oEmbed endpoint where one exists without credentials (YouTube). Pure.
import type { Platform } from "@/lib/creators/schemas";

export type UrlCheck =
  | { ok: true; url: string }
  | { ok: false; error: "invalid" | "not_https" | "wrong_platform" };

const HOSTS: Record<Exclude<Platform, "other">, readonly string[]> = {
  instagram: ["instagram.com"],
  youtube: ["youtube.com", "youtu.be", "m.youtube.com"],
  facebook: ["facebook.com", "fb.watch", "m.facebook.com"],
  linkedin: ["linkedin.com"],
  x: ["x.com", "twitter.com"],
  telegram: ["t.me"],
  moj_josh: ["mojapp.in", "share.myjosh.in", "myjosh.in"],
};

/** Path shapes of a single post on each platform (profiles and home pages are not posts). */
const PATHS: Partial<Record<Platform, RegExp>> = {
  instagram: /^\/(p|reel|reels|tv|stories\/[A-Za-z0-9._]+)\/[A-Za-z0-9_-]+\/?$/,
  youtube: /^\/(watch|shorts\/[A-Za-z0-9_-]{6,}|live\/[A-Za-z0-9_-]{6,}|[A-Za-z0-9_-]{6,})\/?$/,
  linkedin: /^\/(posts\/[^/]+|feed\/update\/[^/]+)\/?$/,
  x: /^\/[A-Za-z0-9_]{1,15}\/status\/\d+\/?$/,
  telegram: /^\/[A-Za-z0-9_]{3,}\/\d+\/?$/,
};

function hostMatches(host: string, allowed: readonly string[]): boolean {
  const h = host.toLowerCase().replace(/^www\./, "");
  return allowed.some((a) => h === a || h.endsWith(`.${a}`));
}

/** Validates and normalises a live-post URL for a platform. "other" (e.g. a blog) accepts any https URL. */
export function checkPostUrl(platform: Platform, raw: string): UrlCheck {
  let u: URL;
  try {
    u = new URL(raw.trim());
  } catch {
    return { ok: false, error: "invalid" };
  }
  if (u.protocol !== "https:") return { ok: false, error: "not_https" };
  if (u.username || u.password || !u.hostname.includes(".")) return { ok: false, error: "invalid" };
  if (platform !== "other") {
    if (!hostMatches(u.hostname, HOSTS[platform])) return { ok: false, error: "wrong_platform" };
    const path = PATHS[platform];
    if (path) {
      const host = u.hostname.toLowerCase().replace(/^www\./, "");
      const isShortYoutube = platform === "youtube" && host === "youtu.be";
      const shape = isShortYoutube ? /^\/[A-Za-z0-9_-]{6,}\/?$/ : path;
      if (!shape.test(u.pathname)) return { ok: false, error: "invalid" };
      if (
        platform === "youtube" &&
        u.pathname.replace(/\/$/, "") === "/watch" &&
        !u.searchParams.get("v")
      )
        return { ok: false, error: "invalid" };
    }
  }
  u.hash = "";
  // Tracking parameters are dropped; the ones that identify the post are kept.
  for (const k of [...u.searchParams.keys()])
    if (/^(utm_|igsh|igshid|si|feature|fbclid|ref)/i.test(k)) u.searchParams.delete(k);
  return { ok: true, url: u.toString() };
}

/** Public oEmbed endpoint for a post, when the platform offers one without an access token. */
export function oembedEndpoint(platform: Platform, url: string): string | null {
  if (platform !== "youtube") return null;
  return `https://www.youtube.com/oembed?format=json&url=${encodeURIComponent(url)}`;
}

/** The fields kept from an oEmbed answer (never its HTML). */
export interface OembedInfo {
  title: string | null;
  author_name: string | null;
  thumbnail_url: string | null;
}

export function pickOembed(data: unknown): OembedInfo | null {
  if (!data || typeof data !== "object") return null;
  const d = data as Record<string, unknown>;
  const str = (v: unknown) => (typeof v === "string" && v.length <= 500 ? v : null);
  const thumb = str(d.thumbnail_url);
  return {
    title: str(d.title),
    author_name: str(d.author_name),
    thumbnail_url: thumb?.startsWith("https://") ? thumb : null,
  };
}
