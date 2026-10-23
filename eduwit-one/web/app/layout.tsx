import "./globals.css";
import { type Metadata, type Viewport } from "next";
import { cookies } from "next/headers";
import { type ReactNode } from "react";
import { brand, themes } from "@/lib/brand/tokens.ts";
import { THEME_COOKIE } from "@/lib/security.ts";

export const metadata: Metadata = {
  title: { default: "Eduwit One", template: "%s · Eduwit One" },
  description: "Monitoring, alerts, tests and fixes across Eduwit's five apps.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: brand.navy },
    { media: "(prefers-color-scheme: dark)", color: themes.dark.bg },
  ],
};

// Every page is per-person and live, so nothing is prerendered (and the CSP nonce reaches every script).
export const dynamic = "force-dynamic";

export default async function RootLayout({ children }: { children: ReactNode }) {
  const theme = (await cookies()).get(THEME_COOKIE)?.value;
  return (
    <html lang="en-IN" data-theme={theme === "light" || theme === "dark" ? theme : undefined}>
      <body className="min-h-dvh bg-bg font-sans text-fg antialiased">{children}</body>
    </html>
  );
}
