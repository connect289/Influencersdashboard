// Values the browser may see. Next inlines NEXT_PUBLIC_* only when written out literally, so each is read by name.
export const publicEnv = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL ?? "",
  supabaseKey: process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? "",
  siteUrl: process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3200",
} as const;

/** Google sign-in buttons appear only when the provider is configured in Supabase Auth. */
export const googleEnabled = process.env.NEXT_PUBLIC_AUTH_GOOGLE === "on";
