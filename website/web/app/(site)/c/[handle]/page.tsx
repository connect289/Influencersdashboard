import type { Metadata } from "next";
import Link from "next/link";
import { ArrowRight, Sparkles } from "lucide-react";
import { EnquiryForm } from "@/components/forms/EnquiryForm";
import { getCreator } from "@/lib/server/creators";
import { getSettings } from "@/lib/server/settings";

// Known params are prerendered; other params (and the shared shell, re-rendered when a cache tag expires) render on
// demand. Reading `params` outside <Suspense> is allowed so the content stays in the static HTML (D-058).
export const instant = false;

type Props = { params: Promise<{ handle: string }> };

export async function generateStaticParams() {
  return [{ handle: "demo-creator" }];
}

export const metadata: Metadata = { robots: { index: false, follow: true } };

/**
 * /c/<handle>?code=… — co-branded creator landing page (spec 9.3). The proxy stores the code (or the handle) as the
 * attribution touch, so every lead from this visit carries it; codes never gate anything.
 */
export default async function CreatorPage({ params }: Props) {
  const { handle: raw } = await params;
  const handle = raw.toLowerCase();
  const [creator, settings] = await Promise.all([getCreator(handle), getSettings()]);
  return (
    <main id="main" className="container-site grid gap-10 pt-10 pb-20 lg:grid-cols-[1.1fr_1fr] lg:items-start">
      <section className="grid gap-5">
        <p className="eyebrow inline-flex items-center gap-2">
          <Sparkles className="size-4" aria-hidden /> {creator ? `Recommended by ${creator.display_name}` : "Welcome to Eduwit"}
        </p>
        <h1 className="font-display text-text text-3xl leading-tight font-semibold sm:text-5xl">
          Find the right degree, with a counsellor who checks the details.
        </h1>
        {creator?.bio ? <p className="text-muted max-w-prose">{creator.bio}</p> : null}
        <p className="text-muted max-w-prose">
          Compare online, distance and on-campus programmes by full fee, duration, approvals and eligibility, then get free guidance from an
          Eduwit counsellor. Your referral is noted automatically — there&apos;s nothing to enter.
        </p>
        {creator?.featured.length ? (
          <div className="grid gap-2">
            <h2 className="text-text font-semibold">{creator.display_name}&apos;s picks</h2>
            <ul className="flex flex-wrap gap-2">
              {creator.featured.map((f) => (
                <li key={f.href}>
                  <Link href={f.href} className="border-border bg-surface hover:bg-surface-hover inline-flex h-10 items-center gap-2 rounded-full border px-4 text-sm font-medium">
                    {f.title} <ArrowRight className="size-4" aria-hidden />
                  </Link>
                </li>
              ))}
            </ul>
          </div>
        ) : null}
        <Link href="/programmes" className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 justify-self-start rounded-full px-6 text-sm font-semibold">
          Explore all programmes <ArrowRight className="size-4" aria-hidden />
        </Link>
      </section>
      <section className="glass grid gap-4 rounded-[var(--radius-xl)] p-5 sm:p-6" aria-labelledby="creator-form">
        <h2 id="creator-form" className="font-display text-text text-xl font-semibold">Talk to a counsellor</h2>
        <EnquiryForm whatsapp={settings.counsellor_whatsapp} creatorHandle={handle} />
      </section>
    </main>
  );
}
