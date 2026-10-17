// Tracking link destinations (spec 9.1, INTEGRATION_CONTRACTS §1.3): the Witty WhatsApp deep link with a pre-filled
// message, the website landing page and a custom URL, each with UTMs. The short link `/r/<code>` logs the click and
// redirects to one of these. Pure.

export const DESTINATIONS = ["whatsapp_witty", "website_landing", "custom_url"] as const;
export type Destination = (typeof DESTINATIONS)[number];

export interface Utm {
  utm_source: string;
  utm_medium: string;
  utm_campaign: string;
  utm_content: string;
}

/** UTMs for a creator link: source from settings, medium = platform, campaign = campaign slug, content = code. */
export function utmFor(input: { source: string; platform: string | null; campaign: string | null; code: string }): Utm {
  return {
    utm_source: input.source,
    utm_medium: input.platform ?? "creator",
    utm_campaign: input.campaign ?? "always-on",
    utm_content: input.code,
  };
}

/** A URL-safe campaign slug. */
export function slugify(s: string): string {
  return (
    s
      .normalize("NFKD")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 60) || "campaign"
  );
}

export interface MessageVars {
  creator_name: string;
  programme: string;
  code: string;
  access_code: string | null;
}

/**
 * The pre-filled WhatsApp message from the template. Without an access code (Witty unavailable, or a crawler), every
 * sentence that mentions `{access_code}` is dropped and the creator code is kept as `(ref CODE)`, so the lead can
 * still be attributed (Route B).
 */
export function renderMessage(template: string, v: MessageVars): string {
  let t = template;
  if (!v.access_code) {
    const parts = t.split(/(?<=[.!?])\s+/);
    t = parts.filter((p) => !p.includes("{access_code}")).join(" ");
    if (!t.includes("{code}")) t = `${t} (ref {code})`.trim();
  }
  return t
    .replaceAll("{creator_name}", v.creator_name)
    .replaceAll("{programme}", v.programme)
    .replaceAll("{code}", v.code)
    .replaceAll("{access_code}", v.access_code ?? "")
    .replace(/\s{2,}/g, " ")
    .trim();
}

/** `https://wa.me/<digits>?text=…` */
export function whatsappUrl(number: string, text: string): string {
  return `https://wa.me/${number.replace(/\D/g, "")}?text=${encodeURIComponent(text)}`;
}

/** An https URL safe to redirect to (no credentials, a public host), normalised, or null. */
export function safeHttpsUrl(raw: string): URL | null {
  let u: URL;
  try {
    u = new URL(raw.trim());
  } catch {
    return null;
  }
  if (u.protocol !== "https:" || u.username || u.password) return null;
  const h = u.hostname.toLowerCase();
  if (!h.includes(".") || h === "localhost" || /^\d+\.\d+\.\d+\.\d+$/.test(h) || h.startsWith("[") || h.endsWith(".local"))
    return null;
  return u;
}

/** The URL with the UTMs set (replacing any existing ones). */
export function withUtm(url: URL, utm: Utm): string {
  const u = new URL(url.toString());
  for (const [k, v] of Object.entries(utm)) u.searchParams.set(k, v);
  return u.toString();
}

/** The website's co-branded landing page: `<base>/c/<handle>?code=…&utm_…`. */
export function landingUrl(base: string, handle: string, code: string, utm: Utm): string | null {
  const u = safeHttpsUrl(`${base.replace(/\/+$/, "")}/c/${encodeURIComponent(handle)}`);
  if (!u) return null;
  u.searchParams.set("code", code);
  return withUtm(u, utm);
}

/** The short link printed on posts and QR codes. */
export function shortLink(base: string, code: string): string {
  return `${base.replace(/\/+$/, "")}/${code}`;
}
