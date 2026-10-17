// Link-preview crawlers and automated clients (INTEGRATION_CONTRACTS §1.3 step 5). They get the redirect but never an
// access code, and their visits are logged as bots so they don't count as clicks. In-app browsers of real people
// (Instagram, Facebook, WhatsApp's own browser) are not crawlers. Pure.

const CRAWLER =
  /facebookexternalhit|facebot|meta-externalagent|whatsapp\/|twitterbot|telegrambot|slackbot|slack-imgproxy|linkedinbot|discordbot|googlebot|google-inspectiontool|bingbot|applebot|pinterestbot|redditbot|embedly|skypeuripreview|yandex|duckduckbot|baiduspider|semrush|ahrefs|petalbot|ia_archiver|headlesschrome|python-requests|curl\/|wget\/|go-http-client|okhttp|axios\/|node-fetch|\bbot\b|crawler|spider|preview/i;

export function isCrawler(userAgent: string | null, method = "GET"): boolean {
  if (method.toUpperCase() === "HEAD") return true;
  if (!userAgent || userAgent.trim().length < 8) return true;
  return CRAWLER.test(userAgent);
}

export type DeviceType = "mobile" | "tablet" | "desktop";

export function deviceType(userAgent: string | null): DeviceType {
  const ua = userAgent ?? "";
  if (/ipad|tablet|(android(?!.*mobile))/i.test(ua)) return "tablet";
  if (/mobi|iphone|ipod|android/i.test(ua)) return "mobile";
  return "desktop";
}

/** The app whose in-app browser opened the link, if any. */
export function inAppBrowser(userAgent: string | null): string | null {
  const ua = userAgent ?? "";
  if (/instagram/i.test(ua)) return "instagram";
  if (/FBAN|FBAV|FB_IAB/.test(ua)) return "facebook";
  if (/snapchat/i.test(ua)) return "snapchat";
  if (/linkedinapp/i.test(ua)) return "linkedin";
  return null;
}
