import type { Metadata, Viewport } from "next";
import { AnalyticsLoader } from "@/components/consent/AnalyticsLoader";
import { BOOT_SCRIPT } from "@/lib/client/boot-script";
import { fontVariables } from "@/lib/fonts";
import { getSettings } from "@/lib/server/settings";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000"),
  title: { default: "Eduwit — Choose your education wisely", template: "%s · Eduwit" },
  description:
    "Find the right online or distance degree. Compare programmes, fees and approvals across Eduwit's partner universities, and get free counselling.",
  applicationName: "Eduwit",
  icons: { icon: "/brand/eduwit-mark.svg" },
  formatDetection: { telephone: false },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: [
    { media: "(prefers-color-scheme: dark)", color: "#030913" },
    { media: "(prefers-color-scheme: light)", color: "#f6f8fc" },
  ],
};

export default async function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  const s = await getSettings();
  return (
    <html
      lang="en-IN"
      data-theme="dark"
      data-default-theme={s.default_theme}
      data-concept={s.design_concept}
      data-tier="low"
      className={fontVariables}
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: BOOT_SCRIPT }} />
      </head>
      <body>
        <a
          href="#main"
          className="sr-only-focusable bg-primary text-on-primary fixed top-3 left-3 z-[var(--z-skip)] rounded-full px-4 py-2 font-semibold"
        >
          Skip to content
        </a>
        {children}
        <AnalyticsLoader
          ga4={process.env.NEXT_PUBLIC_GA4_ID}
          pixel={process.env.NEXT_PUBLIC_META_PIXEL_ID}
          clarity={process.env.NEXT_PUBLIC_CLARITY_ID}
        />
      </body>
    </html>
  );
}
