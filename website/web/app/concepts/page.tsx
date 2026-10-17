import Link from "next/link";
import { CONCEPTS } from "@/components/concepts/ConceptFrame";

export default function ConceptsIndex() {
  return (
    <main className="container-site grid min-h-dvh content-center gap-8 py-16">
      <h1 className="text-display text-[length:var(--text-4xl)] font-semibold">Design concepts</h1>
      <ul className="grid gap-4 md:grid-cols-2">
        {(["a", "b"] as const).map((k) => (
          <li key={k} className="glass hairline-lumen grid gap-3 rounded-[var(--radius-xl)] p-6">
            <h2 className="text-xl font-semibold">{CONCEPTS[k].name}</h2>
            <p className="text-muted">{CONCEPTS[k].tagline}</p>
            <div className="flex flex-wrap gap-2 text-sm">
              <Link
                className="border-border hover:bg-surface-hover rounded-full border px-3 py-1.5"
                href={`/concepts/${k}`}
              >
                Home hero
              </Link>
              <Link
                className="border-border hover:bg-surface-hover rounded-full border px-3 py-1.5"
                href={`/concepts/${k}/finder`}
              >
                Finder + panel
              </Link>
              <Link
                className="border-border hover:bg-surface-hover rounded-full border px-3 py-1.5"
                href={`/concepts/${k}/chat`}
              >
                Witty chat
              </Link>
            </div>
          </li>
        ))}
      </ul>
      <Link href="/styleguide" className="text-accent underline-offset-4 hover:underline">
        Style guide and motion gallery →
      </Link>
    </main>
  );
}
