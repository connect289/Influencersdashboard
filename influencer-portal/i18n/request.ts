import { getRequestConfig } from "next-intl/server";

// English only for now; every string lives in messages/<locale>.json so Hindi can be added without refactoring.
export const LOCALES = ["en"] as const;
export const DEFAULT_LOCALE = "en";
export const TIME_ZONE = "Asia/Kolkata";

export default getRequestConfig(async () => {
  const locale = DEFAULT_LOCALE;
  const messages = (await import(`../messages/${locale}.json`)) as { default: Record<string, unknown> };
  return { locale, messages: messages.default, timeZone: TIME_ZONE, now: new Date() };
});
