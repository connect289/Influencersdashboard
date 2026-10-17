import type { Block } from "@/lib/server/content";

/** Renders stored content blocks (legal pages, guides) as plain semantic HTML — no raw HTML is ever injected. */
export function Blocks({ blocks }: { blocks: Block[] }) {
  return (
    <div className="prose-site grid gap-4">
      {blocks.map((b, i) => {
        switch (b.type) {
          case "h2":
            return <h2 key={i} className="font-display text-text mt-4 text-2xl font-semibold">{b.text}</h2>;
          case "h3":
            return <h3 key={i} className="text-text mt-2 text-lg font-semibold">{b.text}</h3>;
          case "p":
            return <p key={i} className="text-muted leading-relaxed">{b.text}</p>;
          case "ul":
            return <ul key={i} className="text-muted grid list-disc gap-1 pl-6">{b.items.map((t, j) => <li key={j}>{t}</li>)}</ul>;
          case "ol":
            return <ol key={i} className="text-muted grid list-decimal gap-1 pl-6">{b.items.map((t, j) => <li key={j}>{t}</li>)}</ol>;
          default:
            return null;
        }
      })}
    </div>
  );
}
