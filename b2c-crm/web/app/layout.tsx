import type { Metadata, Viewport } from "next";
import { headers } from "next/headers";
import { GeistSans } from "geist/font/sans";
import { GeistMono } from "geist/font/mono";
import { Providers } from "./providers";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "Eduwit Spark", template: "%s · Eduwit Spark" },
  description: "Eduwit's in-house sales and nurture CRM.",
  robots: { index: false, follow: false },
  icons: { icon: "/logo.jpg", apple: "/logo.jpg" },
  manifest: "/manifest.webmanifest",
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: light)", color: "#FFFFFF" },
    { media: "(prefers-color-scheme: dark)", color: "#020D19" },
  ],
};

export default async function RootLayout({ children }: { children: React.ReactNode }) {
  // Every page is rendered per request: the nonce in the CSP must be fresh, and nothing here may be cached.
  const nonce = (await headers()).get("x-nonce") ?? undefined;
  return (
    <html lang="en-IN" suppressHydrationWarning className={`${GeistSans.variable} ${GeistMono.variable}`}>
      <body>
        <Providers nonce={nonce}>{children}</Providers>
      </body>
    </html>
  );
}
