import type { Metadata } from "next";
import { LogoMark } from "@/components/brand/Logo";

/**
 * Pages a student reaches from an email (M34j: /u/<lead>/<token>, the unsubscribe link). Public and never indexed: the
 * address carries the student's token, so it is also kept out of the Referer header.
 */
export const metadata: Metadata = {
  title: { absolute: "Unsubscribe · Eduwit" },
  description: "Stop emails from Eduwit about your enquiry.",
  robots: { index: false, follow: false, nocache: true, googleBot: { index: false, follow: false, noimageindex: true } },
  referrer: "no-referrer",
};

export default function StudentLinkLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="grid min-h-dvh place-items-center px-4 py-10">
      <div className="w-full max-w-[420px] rounded-2xl border border-border bg-surface p-6 sm:p-8">
        <div className="mb-6 flex items-center gap-2.5">
          <LogoMark size={36} />
          <span className="text-[15px] font-semibold tracking-tight text-fg">Eduwit</span>
        </div>
        {children}
      </div>
    </main>
  );
}
