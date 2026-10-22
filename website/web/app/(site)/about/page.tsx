import type { Metadata } from "next";
import Link from "next/link";
import { BadgeCheck, Building2, Mail, MapPin, Phone, ShieldCheck } from "lucide-react";
import { ABOUT } from "@/content/about";
import { PRINCIPLES, SERVICES } from "@/content/home";
import { COMPANY } from "@/content/site";
import { catalogStats } from "@/lib/server/search";
import { withOverrides } from "@/lib/server/page-meta";

const META: Metadata = {
  title: "About Eduwit",
  description: "Eduwit Learning Services helps students choose and apply to online, distance and on-campus programmes from partner universities, with free counselling.",
  alternates: { canonical: "/about" },
};

export async function generateMetadata(): Promise<Metadata> {
  return withOverrides("/about", META);
}

export default async function AboutPage() {
  const stats = await catalogStats();
  const a = COMPANY.address;
  return (
    <main id="main" className="container-site grid gap-12 pt-10 pb-28 lg:pb-16">
      <header className="max-w-3xl">
        <p className="eyebrow">About</p>
        <h1 className="font-display text-text mt-2 text-4xl font-semibold sm:text-5xl">Choose your education wisely</h1>
        <p className="text-muted mt-4 text-lg">{ABOUT.intro}</p>
      </header>

      {stats ? (
        <section aria-label="Eduwit in numbers" className="grid gap-4 sm:grid-cols-3">
          {[
            { n: stats.universities, label: "partner universities" },
            { n: stats.offerings, label: "programmes: online, distance and on-campus" },
            { n: stats.programmes, label: "degrees and diplomas, from BA to MBA" },
          ].map((x) => (
            <div key={x.label} className="glass rounded-[var(--radius-xl)] p-6">
              <p className="tabular font-display text-text text-4xl font-semibold">{x.n}</p>
              <p className="text-muted mt-1">{x.label}</p>
            </div>
          ))}
        </section>
      ) : null}

      <section className="grid max-w-3xl gap-4" aria-labelledby="how-h">
        <h2 id="how-h" className="font-display text-text text-2xl font-semibold">How we work</h2>
        <p className="text-muted">{ABOUT.how}</p>
      </section>

      <section className="grid gap-4" aria-labelledby="services-h">
        <h2 id="services-h" className="font-display text-text text-2xl font-semibold">What we do</h2>
        <ul className="grid gap-4 md:grid-cols-3">
          {SERVICES.map((s) => (
            <li key={s.title} className="glass rounded-[var(--radius-xl)] p-6">
              <BadgeCheck className="text-amber-text size-5" aria-hidden />
              <h3 className="text-text mt-2 font-semibold">{s.title}</h3>
              <p className="text-muted mt-1 text-sm">{s.body}</p>
            </li>
          ))}
        </ul>
      </section>

      <section className="grid gap-4" aria-labelledby="principles-h">
        <h2 id="principles-h" className="font-display text-text text-2xl font-semibold">What we promise</h2>
        <ul className="grid gap-4 md:grid-cols-3">
          {PRINCIPLES.map((p) => (
            <li key={p.title} className="border-border rounded-[var(--radius-xl)] border p-6">
              <ShieldCheck className="text-success size-5" aria-hidden />
              <h3 className="text-text mt-2 font-semibold">{p.title}</h3>
              <p className="text-muted mt-1 text-sm">{p.body}</p>
            </li>
          ))}
        </ul>
      </section>

      <section className="glass grid gap-4 rounded-[var(--radius-2xl)] p-6 sm:p-8 md:grid-cols-2" aria-labelledby="company-h">
        <div>
          <h2 id="company-h" className="font-display text-text text-2xl font-semibold">Company details</h2>
          <address className="text-muted mt-4 grid gap-2 not-italic">
            <span className="text-text flex items-center gap-2 font-semibold"><Building2 className="size-4" aria-hidden /> {COMPANY.name}</span>
            <span className="flex gap-2"><MapPin className="mt-0.5 size-4 shrink-0" aria-hidden /> {a.line1}, {a.locality}, {a.city}, {a.region} {a.postalCode}</span>
            <a href={`tel:${COMPANY.phoneE164}`} className="hover:text-text flex gap-2"><Phone className="size-4" aria-hidden /> {COMPANY.phone}</a>
            <a href={`mailto:${COMPANY.email}`} className="hover:text-text flex gap-2"><Mail className="size-4" aria-hidden /> {COMPANY.email}</a>
            <span>GST {COMPANY.gst}</span>
          </address>
        </div>
        <div className="grid content-center gap-3">
          <Link href="/programmes" className="bg-primary text-on-primary inline-flex h-12 items-center justify-center rounded-full px-6 font-semibold">Find a programme</Link>
          <Link href="/contact#enquiry" className="border-border-strong text-text inline-flex h-12 items-center justify-center rounded-full border px-6 font-semibold">Get free counselling</Link>
        </div>
      </section>
    </main>
  );
}
