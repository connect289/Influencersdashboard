import type { Metadata, Viewport } from "next";
import { fontVariables } from "@/lib/fonts";
import { BOOT_SCRIPT } from "@/lib/client/boot-script";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL(process.env.NEXT_PUBLIC_SITE_URL ?? "http://localhost:3000"),
  title: { default: "Eduwit — Choose your education wisely", template: "%s · Eduwit" },
  description:
    "Find the right UGC-DEB entitled online or distance degree. Compare programmes, fees and approvals across Eduwit's partner universities, and get free counselling from Witty.",
  applicationName: "Eduwit",
  icons: { icon: "/brand/eduwit-mark.svg" },
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

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html
      lang="en-IN"
      data-theme="dark"
      data-default-theme="system"
      data-concept="a"
      data-tier="low"
      className={fontVariables}
      suppressHydrationWarning
    >
      <head>
        <script dangerouslySetInnerHTML={{ __html: BOOT_SCRIPT }} />
      </head>
      <body>{children}</body>
    </html>
  );
}
