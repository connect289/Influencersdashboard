/**
 * Cookie options for staff Supabase Auth sessions (admin only). The session tokens are valid against the shared
 * production project, so they are HttpOnly (no script can read them), sent only to /admin (never to public pages),
 * Secure in production and SameSite=Lax. Every staff auth flow (password, Google OAuth with PKCE, callback, refresh)
 * runs on the server under /admin.
 */
export const STAFF_COOKIE_OPTIONS = {
  path: "/admin",
  httpOnly: true,
  secure: process.env.NODE_ENV === "production",
  sameSite: "lax" as const,
};
