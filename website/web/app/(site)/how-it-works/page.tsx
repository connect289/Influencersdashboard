import type { Metadata } from "next";
import Link from "next/link";
import { Check, X } from "lucide-react";
import { JsonLd } from "@/components/seo/JsonLd";
import { Disclosure } from "@/components/ui/Disclosure";
import { HOW_IT_WORKS, SERVICES } from "@/content/home";
import { faqLd } from "@/lib/seo/jsonld";
import { faqsFor } from "@/lib/server/content";

export const metadata: Metadata = {
  title: "How it works",
  description: "Explore programmes, get matched to what fits you, and apply with a counsellor's help. Free counselling; no payment on this website.",
  alternates: { canonical: "/how-it-works" },
};

const DO = [
  "Show every programme's full fee as the university publishes it, with the date it was last checked",
  "Mark which programmes you're eligible for, and say when a counsellor needs to confirm it",
  "Help you compare universities side by side",
  "Help you with documents and the university's application",
];
const DONT = [
  "Take any payment on this website",
  "Promise jobs, placements or admission",
  "Share your details beyond the purposes you agree to",
];

export default async function HowItWorksPage() {
  const faqs = await faqsFor("how-it-works");
  return (
    <main id="main" className="container-site grid gap-12 pt-10 pb-28 lg:pb-16">
      {faqs.length ? <JsonLd data={faqLd(faqs)} /> : null}
      <header className="max-w-3xl">
        <p className="eyebrow">How it works</p>
        <h1 className="font-display text-text mt-2 text-4xl font-semibold sm:text-5xl">Explore. Get matched. Apply with support.</h1>
      </header>
      <ol className="grid gap-4 md:grid-cols-3">
        {HOW_IT_WORKS.map((s, i) => (
          <li key={s.title} className="glass grid gap-2 rounded-[var(--radius-xl)] p-6">
            <span className="tabular font-display text-gradient-lumen text-4xl font-semibold" aria-hidden>0{i + 1}</span>
            <h2 className="text-text text-xl font-semibold">{s.title}</h2>
            <p className="text-muted">{s.body}</p>
          </li>
        ))}
      </ol>
      <section className="grid gap-4 md:grid-cols-2" aria-label="What Eduwit does and doesn't do">
        <div className="border-border rounded-[var(--radius-xl)] border p-6">
          <h2 className="text-text font-semibold">What we do</h2>
          <ul className="mt-3 grid gap-2">
            {DO.map((d) => <li key={d} className="text-muted flex gap-2 text-sm"><Check className="text-success mt-0.5 size-4 shrink-0" aria-hidden /> {d}</li>)}
          </ul>
        </div>
        <div className="border-border rounded-[var(--radius-xl)] border p-6">
          <h2 className="text-text font-semibold">What we never do</h2>
          <ul className="mt-3 grid gap-2">
            {DONT.map((d) => <li key={d} className="text-muted flex gap-2 text-sm"><X className="text-danger mt-0.5 size-4 shrink-0" aria-hidden /> {d}</li>)}
          </ul>
        </div>
      </section>
      <section className="grid gap-4" aria-labelledby="services-h">
        <h2 id="services-h" className="font-display text-text text-2xl font-semibold">Our services</h2>
        <ul className="grid gap-4 md:grid-cols-3">
          {SERVICES.map((s) => (
            <li key={s.title} className="glass rounded-[var(--radius-xl)] p-6">
              <h3 className="text-text font-semibold">{s.title}</h3>
              <p className="text-muted mt-1 text-sm">{s.body}</p>
            </li>
          ))}
        </ul>
      </section>
      {faqs.length ? (
        <section className="grid max-w-3xl gap-4" aria-labelledby="faq-h">
          <h2 id="faq-h" className="font-display text-text text-2xl font-semibold">Questions</h2>
          <Disclosure items={faqs.map((f, i) => ({ id: String(i), title: f.q, content: f.a }))} />
        </section>
      ) : null}
      <div className="flex flex-wrap gap-3">
        <Link href="/programmes?guided=1" className="bg-primary text-on-primary inline-flex h-12 items-center rounded-full px-6 font-semibold">Start the guided finder</Link>
        <Link href="/contact#enquiry" className="border-border-strong text-text inline-flex h-12 items-center rounded-full border px-6 font-semibold">Get free counselling</Link>
      </div>
    </main>
  );
}
