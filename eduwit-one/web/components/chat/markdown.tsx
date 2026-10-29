import Link from "next/link";
import { Fragment, type ReactNode } from "react";

// The assistant's prose as React nodes: paragraphs, lists, a few inline marks and links to the console's own pages.
// Nothing is injected as HTML; a link is followed only when it is a path inside Eduwit One (/incidents/12), otherwise
// its text is shown and the address stays visible.

const INLINE = /(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\([^)\s]+\))/g;

function inline(text: string, keyBase: string): ReactNode[] {
  const out: ReactNode[] = [];
  let i = 0;
  for (const part of text.split(INLINE)) {
    if (!part) continue;
    const key = `${keyBase}-${i++}`;
    if (part.startsWith("**") && part.endsWith("**")) {
      out.push(<strong key={key}>{part.slice(2, -2)}</strong>);
    } else if (part.startsWith("`") && part.endsWith("`")) {
      out.push(
        <code key={key} className="rounded bg-surface-2 px-1 py-0.5 font-mono text-[0.9em]">
          {part.slice(1, -1)}
        </code>,
      );
    } else if (part.startsWith("[")) {
      const m = /^\[([^\]]+)\]\(([^)\s]+)\)$/.exec(part);
      const label = m?.[1] ?? part;
      const href = m?.[2] ?? "";
      if (/^\/[A-Za-z0-9/_.?=&%-]*$/.test(href)) {
        out.push(
          <Link key={key} href={href} className="underline decoration-fg-muted underline-offset-2 hover:decoration-fg">
            {label}
          </Link>,
        );
      } else {
        out.push(
          <span key={key}>
            {label} ({href})
          </span>,
        );
      }
    } else {
      out.push(<Fragment key={key}>{part}</Fragment>);
    }
  }
  return out;
}

export function Markdown({ text }: { text: string }) {
  const blocks = text
    .replace(/\r\n/g, "\n")
    .trim()
    .split(/\n{2,}/);
  return (
    <div className="grid gap-2 text-sm leading-relaxed [overflow-wrap:anywhere]">
      {blocks.map((block, b) => {
        const lines = block.split("\n");
        const bullets = lines.every((l) => /^\s*[-*•]\s+/.test(l));
        const numbered = lines.every((l) => /^\s*\d+[.)]\s+/.test(l));
        if (bullets || numbered) {
          const items = lines.map((l) => l.replace(/^\s*(?:[-*•]|\d+[.)])\s+/, ""));
          const List = numbered ? "ol" : "ul";
          return (
            <List key={b} className={numbered ? "list-decimal pl-5" : "list-disc pl-5"}>
              {items.map((it, i) => (
                <li key={i}>{inline(it, `${b}-${i}`)}</li>
              ))}
            </List>
          );
        }
        const heading = /^#{1,6}\s+(.*)$/.exec(block.trim());
        if (heading && lines.length === 1) {
          return (
            <p key={b} className="font-semibold">
              {inline(heading[1] ?? "", `${b}-h`)}
            </p>
          );
        }
        return (
          <p key={b} className="whitespace-pre-line">
            {inline(block, `${b}-p`)}
          </p>
        );
      })}
    </div>
  );
}
