import Link from "next/link";
import { ArrowRight, Compass, MessageCircle } from "lucide-react";
import { KineticHeadline } from "@/components/concepts/KineticHeadline";
import { TrustLine } from "@/components/concepts/TrustLine";
import { SearchBox } from "@/components/finder/SearchBox";
import { Atmosphere } from "@/components/fx/Atmosphere";
import { WittyHeroOrb } from "@/components/witty/WittyChatHead";
import { HERO } from "@/content/home";
import { WITTY } from "@/content/site";
import type { CatalogStats } from "@/lib/search/types";

/**
 * Hero (spec 8.1, 7): Witty at the centre when the advisor is on; when it is off (flag, circuit breaker), the hero
 * becomes search + the guided finder + "Get free counselling" (spec 7.3 feature flag). The trust line is live (D-014).
 */
export function HomeHero({ stats, advisorEnabled, popular }: { stats: CatalogStats | null; advisorEnabled: boolean; popular: { label: string; href: string }[] }) {
  return (
    <section className="grain relative isolate overflow-hidden">
      <Atmosphere variant="aurora" />
      <div className="container-site relative flex min-h-[calc(100dvh-4rem)] flex-col items-center justify-center gap-5 py-10 text-center sm:gap-7 sm:py-14">
        {stats ? <TrustLine universities={stats.universities} programmes={stats.offerings} allDeb={stats.all_ugc_deb} /> : null}
        <KineticHeadline text={advisorEnabled ? HERO.advisorHeadline : HERO.headline} className="text-text max-w-4xl text-[length:var(--text-5xl)]" />
        {advisorEnabled ? (
          <>
            <div className="flex flex-col items-center gap-3">
              <WittyHeroOrb href="/witty" />
              <p className="text-muted max-w-xl text-base sm:text-lg">{WITTY.greeting}</p>
            </div>
            <Link href="/witty" className="glass-strong hairline-lumen group flex w-full max-w-2xl items-center gap-3 rounded-[var(--radius-2xl)] p-2 pl-5 text-left transition-shadow hover:shadow-[var(--glow-amber)]">
              <span className="text-subtle flex-1 truncate text-base">Ask Witty anything about online degrees…</span>
              <span className="bg-primary text-on-primary grid size-12 place-items-center rounded-full shadow-[var(--glow-amber)]">
                <ArrowRight className="size-5 transition-transform group-hover:translate-x-0.5" aria-hidden />
              </span>
            </Link>
            <ul className="flex max-w-2xl flex-wrap justify-center gap-2" aria-label="Suggested questions">
              {WITTY.starters.map((s) => (
                <li key={s}>
                  <Link href={`/witty?q=${encodeURIComponent(s)}`} className="border-border bg-surface text-muted hover:border-border-strong hover:text-text inline-flex min-h-10 items-center rounded-full border px-4 text-sm backdrop-blur transition-colors">
                    {s}
                  </Link>
                </li>
              ))}
            </ul>
          </>
        ) : (
          <>
            <p className="text-muted max-w-2xl text-base sm:text-lg">{HERO.sub}</p>
            <SearchBox size="hero" className="w-full max-w-2xl text-left" />
            <nav aria-label="Popular searches" className="flex max-w-3xl flex-wrap justify-center gap-2">
              {[{ label: "Undergraduate", href: "/programmes?level=ug" }, { label: "Postgraduate", href: "/programmes?level=pg" }, { label: "Diploma", href: "/programmes?level=diploma" }, ...popular.slice(0, 5)].map((p) => (
                <Link key={p.href} href={p.href} className="border-border bg-surface text-muted hover:border-border-strong hover:text-text inline-flex min-h-10 items-center rounded-full border px-4 text-sm backdrop-blur transition-colors">
                  {p.label}
                </Link>
              ))}
            </nav>
            <div className="flex flex-wrap justify-center gap-3">
              <Link href="/programmes?guided=1" className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold shadow-[var(--glow-amber)]">
                <Compass className="size-4" aria-hidden /> Answer 3 quick questions
              </Link>
              <Link href="/contact#enquiry" className="border-border-strong text-text bg-surface inline-flex h-12 items-center gap-2 rounded-full border px-6 font-semibold">
                <MessageCircle className="size-4" aria-hidden /> Get free counselling
              </Link>
            </div>
          </>
        )}
      </div>
    </section>
  );
}
