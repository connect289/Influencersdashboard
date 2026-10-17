import type { Metadata } from "next";
import { Logo } from "@/components/brand/Logo";
import { ComponentGallery } from "@/components/styleguide/ComponentGallery";
import { MotionGallery } from "@/components/styleguide/MotionGallery";
import { ThemeToggle } from "@/components/theme/ThemeToggle";
import { CONTRAST_PAIRS, contrast } from "@/lib/design/contrast";

export const metadata: Metadata = { title: "Style guide", robots: { index: false, follow: false } };

const SWATCHES = [
  "bg",
  "bg-elev",
  "surface-solid",
  "border-strong",
  "text",
  "text-muted",
  "text-subtle",
  "primary",
  "secondary",
  "accent",
  "success",
  "warning",
  "danger",
  "focus",
];
const SCALES = {
  navy: ["50", "100", "200", "300", "400", "500", "600", "700", "800", "900", "950"],
  amber: ["50", "100", "200", "300", "400", "500", "600", "700", "800", "900"],
};
const TYPE = [
  ["6xl", "Display XL — hero"],
  ["5xl", "Display L"],
  ["4xl", "Heading 1"],
  ["3xl", "Heading 2"],
  ["2xl", "Heading 3"],
  ["xl", "Lead"],
  ["lg", "Large body"],
  ["base", "Body — 16px, never smaller for inputs"],
  ["sm", "Small"],
  ["xs", "Caption"],
];

function Section({ id, title, children }: { id: string; title: string; children: React.ReactNode }) {
  return (
    <section id={id} aria-labelledby={`${id}-h`} className="grid gap-6 py-12">
      <h2 id={`${id}-h`} className="text-display text-[length:var(--text-3xl)] font-semibold">
        {title}
      </h2>
      {children}
    </section>
  );
}

export default function StyleguidePage() {
  return (
    <div data-concept="a" className="bg-bg text-text min-h-dvh">
      <header className="border-border sticky top-0 z-[var(--z-header)] border-b bg-[color-mix(in_oklab,var(--bg)_80%,transparent)] backdrop-blur-xl">
        <div className="container-site flex h-16 items-center gap-4">
          <Logo height={28} />
          <span className="text-muted text-sm">Design system</span>
          <nav aria-label="Sections" className="text-muted ml-auto hidden gap-4 text-sm md:flex">
            {["brand", "colour", "type", "space", "components", "motion", "tiers"].map((s) => (
              <a key={s} href={`#${s}`} className="hover:text-text capitalize">
                {s}
              </a>
            ))}
          </nav>
          <ThemeToggle scoped />
        </div>
      </header>
      <main className="container-site">
        <Section id="brand" title="Brand">
          <p className="text-muted max-w-2xl">
            The Eduwit logo is used unchanged (SVG trace of the owner&apos;s file, pending confirmation — S-40). The
            navy half switches to a light tone on dark surfaces so the mark stays legible.
          </p>
          <div className="flex flex-wrap items-end gap-10">
            <Logo variant="full" height={180} />
            <Logo variant="mark" height={96} />
            <Logo variant="lockup" height={48} />
          </div>
        </Section>

        <Section id="colour" title="Colour (both themes)">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {SWATCHES.map((s) => (
              <div key={s} className="border-border flex items-center gap-3 rounded-[var(--radius-md)] border p-3">
                <span
                  className="border-border size-10 rounded-[var(--radius-sm)] border"
                  style={{ background: `var(--${s})` }}
                />
                <code className="text-sm">--{s}</code>
              </div>
            ))}
          </div>
          {Object.entries(SCALES).map(([name, steps]) => (
            <div key={name} className="grid gap-2">
              <p className="eyebrow">{name}</p>
              <div className="grid grid-cols-6 gap-1 sm:grid-cols-11">
                {steps.map((st) => (
                  <div key={st} className="text-subtle grid gap-1 text-center text-[10px]">
                    <span className="h-10 rounded-[var(--radius-xs)]" style={{ background: `var(--${name}-${st})` }} />
                    {st}
                  </div>
                ))}
              </div>
            </div>
          ))}
          <div className="border-border overflow-x-auto rounded-[var(--radius-lg)] border">
            <table className="w-full text-sm">
              <caption className="text-muted p-3 text-left">
                WCAG 2.1 AA contrast — checked in CI (lib/design/contrast.test.ts)
              </caption>
              <thead>
                <tr className="text-subtle text-left text-xs">
                  <th className="p-3">Theme</th>
                  <th className="p-3">Pair</th>
                  <th className="p-3">Sample</th>
                  <th className="p-3">Ratio</th>
                </tr>
              </thead>
              <tbody>
                {CONTRAST_PAIRS.map((p) => {
                  const r = contrast(p.fg, p.bg);
                  return (
                    <tr key={p.theme + p.name} className="border-border border-t">
                      <td className="text-muted p-3">{p.theme}</td>
                      <td className="p-3">{p.name}</td>
                      <td className="p-3">
                        <span className="rounded px-2 py-1" style={{ color: p.fg, background: p.bg }}>
                          Aa ₹1,00,000
                        </span>
                      </td>
                      <td className="tabular p-3 font-semibold">
                        {r.toFixed(2)}:1 {r >= p.min ? "✓" : "✗"}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        </Section>

        <Section id="type" title="Typography">
          <p className="text-muted max-w-2xl">
            Display: Bricolage Grotesque (Concept A) or Roboto Flex (Concept B), variable with optical sizing. Body:
            Inter variable. Fees and counts use tabular figures.
          </p>
          <div className="grid gap-4">
            {TYPE.map(([k, label]) => (
              <div
                key={k}
                className="border-border grid gap-1 border-b pb-4 sm:grid-cols-[10rem_1fr] sm:items-baseline"
              >
                <code className="text-subtle text-xs">text-{k}</code>
                <p
                  className={k!.length > 2 || ["xl", "lg"].includes(k!) ? "font-display font-semibold" : ""}
                  style={{ fontSize: `var(--text-${k})`, lineHeight: 1.15 }}
                >
                  {label}
                </p>
              </div>
            ))}
            <p className="tabular font-display text-4xl font-semibold">₹1,00,000 · ₹85,500 · ₹2,49,000</p>
          </div>
        </Section>

        <Section id="space" title="Space, radius, elevation, blur, z-layers">
          <div className="flex flex-wrap items-end gap-3">
            {[1, 2, 3, 4, 6, 8, 12, 16, 24].map((s) => (
              <div key={s} className="text-subtle grid justify-items-center gap-1 text-xs">
                <span className="bg-primary w-6" style={{ height: `var(--space-${s})` }} />
                {s}
              </div>
            ))}
          </div>
          <div className="flex flex-wrap gap-4">
            {["xs", "sm", "md", "lg", "xl", "2xl"].map((r) => (
              <div
                key={r}
                className="border-border-strong bg-surface text-subtle grid size-20 place-items-center border text-xs"
                style={{ borderRadius: `var(--radius-${r})` }}
              >
                {r}
              </div>
            ))}
          </div>
          <div className="flex flex-wrap gap-6">
            {[1, 2, 3].map((e) => (
              <div
                key={e}
                className="bg-bg-elev text-subtle grid size-28 place-items-center rounded-[var(--radius-lg)] text-xs"
                style={{ boxShadow: `var(--shadow-${e})` }}
              >
                elevation {e}
              </div>
            ))}
            <div className="bg-bg-elev text-subtle grid size-28 place-items-center rounded-[var(--radius-lg)] text-xs shadow-[var(--glow-amber)]">
              glow amber
            </div>
            <div className="bg-bg-elev text-subtle grid size-28 place-items-center rounded-[var(--radius-lg)] text-xs shadow-[var(--glow-azure)]">
              glow azure
            </div>
          </div>
          <p className="text-muted text-sm">
            Z-layers: base 0 · raised 10 · sticky 100 · header 200 · dock 300 · overlay 400 · panel 500 · modal 600 ·
            toast 700 · skip link 800.
          </p>
        </Section>

        <section id="components" className="py-12">
          <h2 className="text-display text-[length:var(--text-3xl)] font-semibold">Components</h2>
          <ComponentGallery />
        </section>

        <Section id="motion" title="Motion gallery">
          <p className="text-muted max-w-2xl">
            Durations: instant 80 · fast 160 · base 240 · slow 420 · slower 700 · cinematic 1100 ms. Easings: standard,
            emphasized, out-expo, in-out, spring. Every animation has a still equivalent for reduced motion.
          </p>
          <MotionGallery />
        </Section>

        <Section id="tiers" title="Capability tiers">
          <ul className="grid gap-3 md:grid-cols-3">
            <li className="glass rounded-[var(--radius-xl)] p-5">
              <p className="font-semibold">Low</p>
              <p className="text-muted mt-1 text-sm">
                Reduced motion, Save-Data, ≤ 2 GB memory, ≤ 4 cores, battery saver or no WebGL → static gradient
                posters, CSS-only motion, solid surfaces, no grain.
              </p>
            </li>
            <li className="glass rounded-[var(--radius-xl)] p-5">
              <p className="font-semibold">Mid</p>
              <p className="text-muted mt-1 text-sm">≤ 4 GB memory → shaders at 0.5× resolution, 30 fps cap.</p>
            </li>
            <li className="glass rounded-[var(--radius-xl)] p-5">
              <p className="font-semibold">High</p>
              <p className="text-muted mt-1 text-sm">
                Everything else → shaders at 0.75× resolution, 60 fps cap. All tiers: shaders load after first paint and
                pause off-screen or in hidden tabs.
              </p>
            </li>
          </ul>
        </Section>
      </main>
    </div>
  );
}
