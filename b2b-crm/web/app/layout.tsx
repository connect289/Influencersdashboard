import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import { GeistSans } from "geist/font/sans";
import { GeistMono } from "geist/font/mono";
import { Providers } from "./providers";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Eduwit Partner CRM", template: "%s · Eduwit Partner CRM" },
  description: "Eduwit's B2B partner CRM: lead allocation, partner sync and commission.",
  robots: { index: false, follow: false },
};

export const viewport: Viewport = {
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#f6f7f9" },
    { media: "(prefers-color-scheme: dark)", color: "#0a0d12" },
  ],
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // Every page is rendered per request: the nonce in the CSP must be fresh, and nothing here may be cached.
  const nonce = (await headers()).get("x-nonce") ?? undefined;
  return (
    <html lang="en-IN" suppressHydrationWarning className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body className="min-h-dvh">
        <Providers nonce={nonce}>{children}</Providers>
      </body>
    </html>
  );
}
