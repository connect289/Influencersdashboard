import { describe, expect, it } from "vitest";
import { deviceType, inAppBrowser, isCrawler } from "./bots";

const IPHONE_IG =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 Instagram 330.0.0.0.0";
const ANDROID_CHROME =
  "Mozilla/5.0 (Linux; Android 14; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36";
const DESKTOP =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36";
const FB_APP =
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Mobile/15E148 [FBAN/FBIOS;FBAV/450.0]";

describe("crawler detection", () => {
  it.each([
    "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
    "WhatsApp/2.23.20.0 A",
    "Twitterbot/1.0",
    "TelegramBot (like TwitterBot)",
    "Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)",
    "LinkedInBot/1.0",
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "curl/8.4.0",
    "python-requests/2.31",
    "",
  ])("%j is a crawler", (ua) => {
    expect(isCrawler(ua)).toBe(true);
  });

  it("people in browsers and in-app browsers are not", () => {
    for (const ua of [IPHONE_IG, ANDROID_CHROME, DESKTOP, FB_APP])
      expect(isCrawler(ua), ua).toBe(false);
  });

  it("HEAD requests and missing agents are treated as crawlers", () => {
    expect(isCrawler(DESKTOP, "HEAD")).toBe(true);
    expect(isCrawler(null)).toBe(true);
  });

  it("classifies devices and in-app browsers", () => {
    expect(deviceType(IPHONE_IG)).toBe("mobile");
    expect(deviceType(ANDROID_CHROME)).toBe("mobile");
    expect(deviceType("Mozilla/5.0 (iPad; CPU OS 17_0 like Mac OS X)")).toBe("tablet");
    expect(deviceType("Mozilla/5.0 (Linux; Android 13; SM-X200) Safari")).toBe("tablet");
    expect(deviceType(DESKTOP)).toBe("desktop");
    expect(inAppBrowser(IPHONE_IG)).toBe("instagram");
    expect(inAppBrowser(FB_APP)).toBe("facebook");
    expect(inAppBrowser(DESKTOP)).toBeNull();
  });
});
