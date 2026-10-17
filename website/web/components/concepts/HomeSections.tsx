import Link from "next/link";
import { Compass, FileCheck2, MessagesSquare, Phone, Mail, MapPin, Sparkles } from "lucide-react";
import { Disclosure } from "@/components/ui/Disclosure";
import { Badge } from "@/components/ui/Badge";
import { formatInrRange } from "@/lib/format";
import type { SeedGroup } from "@/lib/seed/concept";
import { cn } from "@/lib/utils";
import type { ConceptId } from "./ConceptFrame";

const STEPS = [
  {
    icon: Compass,
    title: "Explore",
    body: "Search or ask Witty. Compare programmes, fees, approvals and eligibility across partner universities.",
  },
  {
    icon: MessagesSquare,
    title: "Get matched",
    body: "Witty asks about your background, goals and budget first, then shows only programmes you are eligible for.",
  },
  {
    icon: FileCheck2,
    title: "Apply with support",
    body: "Fill one pre-application. A counsellor completes the university application with you — no payment on this site.",
  },
];

/** Shared homepage sections for both concepts (spec §8 order); composition differs by concept. */
export function HomeSections({
  concept,
  groups,
  universities,
}: {
  concept: ConceptId;
  groups: SeedGroup[];
  universities: string[];
}) {
  const a = concept === "a";
  return (
    <>
      <section className="container-site grid gap-6 py-16" aria-labelledby="popular">
        <div className="flex flex-wrap items-end justify-between gap-4">
          <div>
            <p className="eyebrow">Popular right now</p>
            <h2 id="popular" className="mt-2 text-[length:var(--text-3xl)] font-semibold">
              Programmes students compare most
            </h2>
          </div>
          <div className="flex gap-2">
            {["UG", "PG", "Diploma"].map((l) => (
              <Link
                key={l}
                href={`/concepts/${concept}/finder`}
                className="border-border text-muted hover:text-text rounded-full border px-4 py-2 text-sm"
              >
                {l}
              </Link>
            ))}
          </div>
        </div>
        {/* Focusable scroll region so keyboard users can scroll the carousel (WCAG 2.1.1). */}
        <div
          role="region"
          aria-label="Popular programmes"
          tabIndex={0}
          className="-mx-[var(--gutter)] overflow-x-auto px-[var(--gutter)] pb-2"
        >
          <ul className="flex snap-x snap-mandatory gap-4">
            {groups.slice(0, 8).map((g, i) => (
              <li
                key={g.key}
                data-reveal
                className={cn(
                  "glass hairline-lumen w-[17rem] shrink-0 snap-start p-5",
                  a ? "rounded-[var(--radius-xl)]" : "rounded-[var(--radius-lg)]",
                )}
                style={{ animationDelay: `${i * 60}ms` }}
              >
                <p className="eyebrow">{g.level === "PG" ? "Postgraduate" : "Undergraduate"}</p>
                <p className="font-display mt-2 text-xl leading-tight font-semibold">
                  {g.programme} <span className="text-muted">· {g.specialisation}</span>
                </p>
                <p className="tabular mt-4 font-semibold">{formatInrRange(g.feeMin, g.feeMax)}</p>
                <p className="text-subtle text-xs">
                  {g.universities.length} {g.universities.length === 1 ? "university" : "universities"} · Easy EMI
                  available
                </p>
                {g.bestNaac ? (
                  <Badge tone="verified" className="mt-3">
                    Up to NAAC {g.bestNaac}
                  </Badge>
                ) : null}
              </li>
            ))}
          </ul>
        </div>
      </section>

      <section className="border-border border-y py-8" aria-label="Partner universities">
        <div className="container-site">
          <p className="eyebrow mb-4 text-center">Partner universities</p>
          <ul className="text-muted flex flex-wrap justify-center gap-x-6 gap-y-2 text-sm">
            {universities.map((u) => (
              <li key={u} className="whitespace-nowrap">
                {u}
              </li>
            ))}
          </ul>
          <p className="text-subtle mt-3 text-center text-xs">
            University logos appear only with each university&apos;s permission.
          </p>
        </div>
      </section>

      <section className="container-site grid gap-10 py-20" aria-labelledby="how">
        <div className={cn(a ? "text-center" : "")}>
          <p className="eyebrow">How it works</p>
          <h2 id="how" className="mt-2 text-[length:var(--text-4xl)] font-semibold">
            Explore. Get matched. <span className="text-gradient-lumen">Apply with support.</span>
          </h2>
        </div>
        <ol
          className={cn(
            "grid gap-4",
            a ? "md:grid-cols-3" : "md:divide-border md:border-border md:grid-cols-3 md:gap-0 md:divide-x md:border-y",
          )}
        >
          {STEPS.map((s, i) => (
            <li
              key={s.title}
              data-reveal
              className={cn("relative grid gap-3 p-6", a ? "glass hairline-lumen rounded-[var(--radius-xl)]" : "")}
            >
              <span className="tabular font-display text-gradient-lumen text-5xl font-semibold">0{i + 1}</span>
              <s.icon className="text-amber-text size-6" aria-hidden />
              <h3 className="text-xl font-semibold">{s.title}</h3>
              <p className="text-muted">{s.body}</p>
            </li>
          ))}
        </ol>
      </section>

      <section className="container-site grid gap-4 pb-20 md:grid-cols-6" aria-labelledby="why">
        <div
          className={cn(
            "glass hairline-lumen grid content-between gap-6 p-7 md:col-span-4 md:row-span-2",
            a ? "rounded-[var(--radius-2xl)]" : "rounded-[var(--radius-xl)]",
          )}
          data-reveal
        >
          <div>
            <p className="eyebrow">Why Eduwit</p>
            <h2 id="why" className="mt-2 text-[length:var(--text-3xl)] font-semibold">
              The bridge between students and universities
            </h2>
          </div>
          <p className="border-border-strong text-subtle max-w-xl rounded-[var(--radius-md)] border border-dashed p-4 text-sm">
            Pending migration: this block reuses the current site&apos;s &ldquo;bridge between students and
            universities&rdquo; copy verbatim once the crawl runs (D-006).
          </p>
          <div className="flex flex-wrap gap-2">
            <Badge tone="verified">Facts from university records</Badge>
            <Badge tone="info">Your consent, your data</Badge>
            <Badge tone="amber">Free counselling</Badge>
          </div>
        </div>
        {["Educational Counselling", "Course Discovery & Comparison", "Application & Enrollment Support"].map((s) => (
          <div
            key={s}
            data-reveal
            className={cn(
              "glass grid content-start gap-2 p-6 md:col-span-2",
              a ? "rounded-[var(--radius-xl)]" : "rounded-[var(--radius-lg)]",
              s.startsWith("Application") && "md:col-span-6 lg:col-span-2",
            )}
          >
            <Sparkles className="text-amber-text size-5" aria-hidden />
            <h3 className="font-semibold">{s}</h3>
            <p className="text-subtle text-sm">Service description pending migration.</p>
          </div>
        ))}
      </section>

      <section className="container-site grid gap-6 pb-20 lg:grid-cols-[1fr_1.4fr]" aria-labelledby="faq">
        <div>
          <p className="eyebrow">Questions</p>
          <h2 id="faq" className="mt-2 text-[length:var(--text-3xl)] font-semibold">
            Good to know
          </h2>
        </div>
        <Disclosure
          name="faq"
          items={[
            {
              id: "fee",
              title: "Is counselling really free?",
              content:
                "Yes, counselling with Eduwit is free. You pay programme fees only to the university — never on this website.",
            },
            {
              id: "deb",
              title: "What does UGC-DEB mean?",
              content:
                "The UGC's Distance Education Bureau publishes which universities may offer which programmes online or by distance learning. We show each university's approvals as stated in its records, with the date we last verified them.",
            },
            {
              id: "witty",
              title: "Who is Witty?",
              content:
                "Witty is Eduwit's AI admissions assistant. It answers from Eduwit's programme data and asks a counsellor to confirm anything it does not know.",
            },
          ]}
        />
      </section>

      <section className="container-site pb-20">
        <div
          className={cn(
            "grain relative isolate grid gap-6 overflow-hidden p-8 text-center sm:p-12",
            a
              ? "glass-strong hairline-lumen rounded-[var(--radius-2xl)]"
              : "bg-navy-800 rounded-[var(--radius-xl)] text-white",
          )}
        >
          <h2 className="text-[length:var(--text-4xl)] font-semibold">Not sure where to start?</h2>
          <p className={cn("mx-auto max-w-xl", a ? "text-muted" : "text-navy-100")}>
            Ask Witty, or get free counselling from Eduwit&apos;s team.
          </p>
          <div className="flex flex-wrap justify-center gap-3">
            <Link
              href={`/concepts/${concept}/chat`}
              className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold shadow-[var(--glow-amber)]"
            >
              <Sparkles className="size-4" aria-hidden /> Ask Witty
            </Link>
            <a
              href="tel:+919650683269"
              className={cn(
                "inline-flex h-12 items-center gap-2 rounded-full border px-6 font-semibold",
                a ? "border-border-strong text-text" : "border-white/40 text-white",
              )}
            >
              <Phone className="size-4" aria-hidden /> +91 96506 83269
            </a>
          </div>
        </div>
      </section>

      <footer className="border-border border-t">
        <div className="container-site text-muted grid gap-8 py-12 text-sm md:grid-cols-3">
          <address className="grid gap-2 not-italic">
            <span className="text-text font-semibold">Eduwit Learning Services</span>
            <span className="flex gap-2">
              <MapPin className="size-4 shrink-0" aria-hidden /> 267-F3, Neeti Khand-1, Indirapuram, Ghaziabad, UP
              201014
            </span>
            <a href="tel:+919650683269" className="hover:text-text flex gap-2">
              <Phone className="size-4" aria-hidden /> +91-9650683269
            </a>
            <a href="mailto:connect@eduwit.in" className="hover:text-text flex gap-2">
              <Mail className="size-4" aria-hidden /> connect@eduwit.in
            </a>
            <span>GST 09BXLPJ7928K1ZP</span>
          </address>
          <ul className="grid content-start gap-2">
            {[
              "terms-and-conditions",
              "privacy-policy",
              "disclaimer",
              "refund-policy",
              "cookie-policy",
              "data-privacy-opt-out",
            ].map((l) => (
              <li key={l}>
                <span className="capitalize">{l.replaceAll("-", " ")}</span>
              </li>
            ))}
          </ul>
          <p className="text-subtle text-xs">
            Fees are set by universities and may change; confirm with your counsellor.
          </p>
        </div>
      </footer>
    </>
  );
}
