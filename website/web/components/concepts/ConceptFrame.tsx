import Link from "next/link";
import { Logo } from "@/components/brand/Logo";
import { ThemeToggle } from "@/components/theme/ThemeToggle";
import { cn } from "@/lib/utils";

export type ConceptId = "a" | "b";
export const CONCEPTS: Record<ConceptId, { name: string; lead: "dark" | "light"; tagline: string }> = {
  a: {
    name: "Concept A · Luminous",
    lead: "dark",
    tagline: "AI-native, dark-first: Witty at the centre of a living aurora.",
  },
  b: {
    name: "Concept B · Prism",
    lead: "light",
    tagline: "Editorial, light-first: daylight through a prism, Witty as a floating companion.",
  },
};

/** Preview wrapper: scopes concept + theme (each concept leads with its own theme), with a small review toolbar. */
export function ConceptFrame({
  concept,
  active,
  children,
}: {
  concept: ConceptId;
  active: "home" | "finder" | "chat";
  children: React.ReactNode;
}) {
  const c = CONCEPTS[concept];
  const links = [
    { k: "home", href: `/concepts/${concept}`, label: "Home hero" },
    { k: "finder", href: `/concepts/${concept}/finder`, label: "Finder + panel" },
    { k: "chat", href: `/concepts/${concept}/chat`, label: "Witty chat" },
  ];
  return (
    <div data-concept={concept} data-theme={c.lead} className="bg-bg text-text min-h-dvh">
      <header className="border-border sticky top-0 z-[var(--z-header)] border-b bg-[color-mix(in_oklab,var(--bg)_78%,transparent)] backdrop-blur-xl">
        <div className="container-site flex h-16 items-center gap-4">
          <Link href={`/concepts/${concept}`} aria-label="Eduwit concept home">
            <Logo height={30} />
          </Link>
          <nav aria-label="Concept screens" className="ml-auto hidden items-center gap-1 md:flex">
            {links.map((l) => (
              <Link
                key={l.k}
                href={l.href}
                aria-current={active === l.k ? "page" : undefined}
                className={cn(
                  "text-muted hover:text-text rounded-full px-3 py-1.5 text-sm",
                  active === l.k && "bg-surface text-text",
                )}
              >
                {l.label}
              </Link>
            ))}
          </nav>
          <Link
            href={`/concepts/${concept === "a" ? "b" : "a"}/${active === "home" ? "" : active}`}
            className="border-border text-muted hover:text-text ml-auto rounded-full border px-3 py-1.5 text-sm md:ml-0"
          >
            {concept === "a" ? "See B" : "See A"}
          </Link>
          <ThemeToggle scoped />
        </div>
      </header>
      {children}
      <p className="container-site text-subtle py-8 text-xs">
        {c.name} — {c.tagline} Design preview with real catalogue data (export of 17 Oct 2026); not indexed.
      </p>
    </div>
  );
}
