import type { Metadata } from "next";
import Link from "next/link";
import { CheckCircle2 } from "lucide-react";

export const metadata: Metadata = { title: "Thank you", robots: { index: false } };

/** Generic confirmation (used when JavaScript is unavailable; forms normally confirm inline). */
export default function ThankYou() {
  return (
    <main id="main" className="container-site grid min-h-[60dvh] content-center justify-items-start gap-5 py-20">
      <CheckCircle2 className="text-success size-10" aria-hidden />
      <h1 className="text-display text-[length:var(--text-4xl)] font-semibold">
        Thank you — we&apos;ve got your details.
      </h1>
      <ol className="text-muted grid max-w-xl list-decimal gap-2 pl-5">
        <li>A counsellor will contact you, usually within one working day.</li>
        <li>They will confirm fees, eligibility and the documents you need.</li>
        <li>They complete the university application with you. You never pay on this website.</li>
      </ol>
      <Link
        href="/programmes"
        className="bg-primary text-on-primary inline-flex h-11 items-center rounded-full px-5 font-semibold"
      >
        Explore more programmes
      </Link>
    </main>
  );
}
