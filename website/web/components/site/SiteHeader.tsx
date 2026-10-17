import Link from "next/link";
import { GitCompareArrows, Menu, Sparkles, UserRound, X } from "lucide-react";
import { Logo } from "@/components/brand/Logo";
import { ThemeToggle } from "@/components/theme/ThemeToggle";
import { NAV } from "@/content/site";
import { SavedCount } from "./SavedCount";

/**
 * Persistent header (spec 8): logo, Programmes, Universities, Compare (count badge), Resources, About, Contact,
 * "Ask Witty" (or "Get free counselling" while Witty is off), Account. The phone menu uses the native popover API
 * (no JavaScript: top layer, light dismiss, Escape to close).
 */
export function SiteHeader({ advisorEnabled }: { advisorEnabled: boolean }) {
  const cta = advisorEnabled
    ? { href: "/witty", label: "Ask Witty" }
    : { href: "/contact#enquiry", label: "Free counselling" };
  return (
    <header className="border-border sticky top-0 z-[var(--z-header)] border-b bg-[color-mix(in_oklab,var(--bg)_80%,transparent)] backdrop-blur-xl">
      <div className="container-site flex h-16 items-center gap-3">
        <Link href="/" aria-label="Eduwit home" className="shrink-0">
          <Logo height={30} priority />
        </Link>
        <nav aria-label="Main" className="ml-6 hidden items-center gap-1 lg:flex">
          {NAV.map((n) => (
            <Link
              key={n.href}
              href={n.href}
              className="text-muted hover:bg-surface-hover hover:text-text rounded-full px-3 py-2 text-sm font-medium transition-colors"
            >
              {n.label}
            </Link>
          ))}
        </nav>
        <div className="ml-auto flex items-center gap-1.5">
          <Link
            href="/compare"
            className="text-muted hover:bg-surface-hover hover:text-text relative hidden h-10 items-center gap-1.5 rounded-full px-3 text-sm font-medium md:inline-flex"
            aria-label="Compare"
          >
            <GitCompareArrows className="size-[18px]" aria-hidden />
            <span className="hidden xl:inline">Compare</span>
            <SavedCount list="compare" />
          </Link>
          <Link
            href={cta.href}
            className="bg-primary text-on-primary hover:bg-primary-hover inline-flex h-10 items-center gap-1.5 rounded-full px-4 text-sm font-semibold shadow-[var(--glow-amber)] transition-colors"
          >
            <Sparkles className="size-4" aria-hidden />
            {cta.label}
          </Link>
          <Link
            href="/account"
            aria-label="Your account"
            className="border-border text-muted hover:bg-surface-hover hover:text-text hidden size-10 place-items-center rounded-full border sm:grid"
          >
            <UserRound className="size-[18px]" aria-hidden />
          </Link>
          <ThemeToggle className="hidden sm:inline-grid" />
          <button
            type="button"
            popoverTarget="site-menu"
            aria-label="Open menu"
            className="border-border text-muted grid size-10 place-items-center rounded-full border lg:hidden"
          >
            <Menu className="size-5" aria-hidden />
          </button>
        </div>
      </div>
      <nav
        id="site-menu"
        popover="auto"
        aria-label="Menu"
        className="site-menu glass-strong text-text m-0 ml-auto h-dvh w-[min(22rem,100vw)] p-0"
      >
        <div className="border-border flex h-16 items-center justify-between border-b px-5">
          <Logo height={26} />
          <button
            type="button"
            popoverTarget="site-menu"
            popoverTargetAction="hide"
            aria-label="Close menu"
            className="border-border text-muted grid size-10 place-items-center rounded-full border"
          >
            <X className="size-5" aria-hidden />
          </button>
        </div>
        <ul className="grid gap-1 p-3">
          {[
            ...NAV,
            { href: "/compare", label: "Compare" },
            { href: "/account", label: "Account" },
            { href: "/how-it-works", label: "How it works" },
          ].map((n) => (
            <li key={n.href}>
              <Link
                href={n.href}
                className="hover:bg-surface-hover flex h-12 items-center rounded-[var(--radius-md)] px-4 text-base font-medium"
              >
                {n.label}
              </Link>
            </li>
          ))}
        </ul>
        <div className="border-border text-muted flex items-center justify-between border-t px-5 py-4 text-sm">
          Theme <ThemeToggle />
        </div>
      </nav>
    </header>
  );
}
