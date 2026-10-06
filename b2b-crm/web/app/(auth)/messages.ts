/** Fixed copy for ?error= and ?reason= codes, so URLs can never inject text into the page. */
export const AUTH_ERRORS: Record<string, string> = {
  restricted: "This app is restricted. Your account is not allowed to use the Eduwit Partner CRM. The attempt was logged.",
  locked: "Too many failed attempts. Sign-in is locked for 15 minutes.",
  link: "That sign-in link is invalid or has expired. Request a new one.",
  oauth: "Google sign-in did not complete. Try again.",
  setup: "Your sign-in worked, but the app cannot reach its data yet. In Supabase, add b2b under Project Settings → Data API → Exposed schemas, save, and sign in again.",
};

export const AUTH_REASONS: Record<string, string> = {
  idle: "You were signed out after 12 hours without activity.",
  signed_out: "You have signed out.",
  password_updated: "Your password was updated. Sign in with it now.",
};
