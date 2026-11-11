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
export function HomeHero({
  stats,
  advisorEnabled,
  popular,
}: {
  stats: CatalogStats | null;
  advisorEnabled: boolean;
  popular: { label: string; href: string }[];
}) {
  return (
    // The hero starts behind the floating header and its atmosphere dissolves into the site backdrop (D-093). z-[1]
    // keeps the docked "Ask Witty" chat-head (fixed, inside this stacking context) above the sections that follow.
    <section className="grain relative isolate z-[1] -mt-[var(--header-h)] overflow-hidden">
      <Atmosphere variant="aurora" className="atmosphere-fade" />
      <div aria-hidden className="cine-bloom" />
      <div aria-hidden className="horizon-grid" />
      <div aria-hidden className="cine-vignette" />
      <div className="container-site relative flex min-h-dvh flex-col items-center justify-center gap-5 pt-[calc(var(--header-h)+2rem)] pb-12 text-center sm:gap-7 sm:pb-16">
        {stats ? (
          <TrustLine universities={stats.universities} programmes={stats.offerings} allDeb={stats.all_ugc_deb} />
        ) : null}
        <KineticHeadline
          text={advisorEnabled ? HERO.advisorHeadline : HERO.headline}
          accentLast={advisorEnabled ? 1 : 2}
          className="text-text headline-bloom max-w-5xl text-[length:var(--text-5xl)]"
        />
        {advisorEnabled ? (
          <>
            <div className="flex flex-col items-center gap-3">
              <span className="orb-halo my-4">
                <span aria-hidden className="lens-flare" />
                <WittyHeroOrb href="/witty" size={96} />
              </span>
              <p className="text-text/90 max-w-xl text-base sm:text-lg">{WITTY.greeting}</p>
            </div>
            {/* A plain GET form: works before hydration and opens the full chat at /witty (D-057). */}
            <form
              action="/witty"
              method="get"
              role="search"
              aria-label="Ask Witty"
              className="glass-strong beam group flex w-full max-w-2xl items-center gap-3 rounded-full p-2 pl-6 text-left transition-shadow focus-within:shadow-[var(--inner-light),var(--glow-azure)] hover:shadow-[var(--inner-light),var(--glow-azure)]"
            >
              <label htmlFor="hero-ask" className="sr-only">
                Ask Witty
              </label>
              <input
                id="hero-ask"
                name="q"
                required
                maxLength={300}
                autoComplete="off"
                placeholder="Ask Witty anything about degrees and admissions…"
                className="placeholder:text-subtle text-text min-w-0 flex-1 bg-transparent text-base outline-none"
              />
              <button
                type="submit"
                aria-label="Ask Witty"
                className="bg-primary text-on-primary grid size-12 shrink-0 place-items-center rounded-full"
              >
                <ArrowRight className="size-5 transition-transform group-hover:translate-x-0.5" aria-hidden />
              </button>
            </form>
            <ul className="flex max-w-2xl flex-wrap justify-center gap-2" aria-label="Suggested questions">
              {WITTY.starters.map((s) => (
                <li key={s}>
                  <Link
                    href={`/witty?q=${encodeURIComponent(s)}`}
                    className="border-border bg-surface text-muted hover:border-border-strong hover:bg-surface-hover hover:text-text inline-flex min-h-10 items-center rounded-full border px-4 text-sm backdrop-blur transition-colors"
                  >
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
              {[
                { label: "Undergraduate", href: "/programmes?level=ug" },
                { label: "Postgraduate", href: "/programmes?level=pg" },
                { label: "Diploma", href: "/programmes?level=diploma" },
                ...popular.slice(0, 5),
              ].map((p) => (
                <Link
                  key={p.href}
                  href={p.href}
                  className="border-border bg-surface text-muted hover:border-border-strong hover:bg-surface-hover hover:text-text inline-flex min-h-10 items-center rounded-full border px-4 text-sm backdrop-blur transition-colors"
                >
                  {p.label}
                </Link>
              ))}
            </nav>
            <div className="flex flex-wrap justify-center gap-3">
              <Link
                href="/programmes?guided=1"
                className="bg-primary text-on-primary inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold"
              >
                <Compass className="size-4" aria-hidden /> Answer 3 quick questions
              </Link>
              <Link
                href="/contact#enquiry"
                className="glass text-text hover:bg-surface-hover inline-flex h-12 items-center gap-2 rounded-full px-6 font-semibold"
              >
                <MessageCircle className="size-4" aria-hidden /> Get free counselling
              </Link>
            </div>
          </>
        )}
      </div>
    </section>
  );
}
