import { type ReactNode } from "react";

/**
 * The brief's Markdown as plain React: headings, bullet lists and paragraphs. No HTML is ever passed through, so a
 * model's output cannot inject markup into the page.
 */
export function Markdown({ text }: { text: string }) {
  const out: ReactNode[] = [];
  let list: string[] = [];
  const flush = () => {
    if (list.length) {
      out.push(
        <ul key={`l${out.length}`} className="ml-5 list-disc">
          {list.map((li, n) => (
            <li key={n}>{li}</li>
          ))}
        </ul>,
      );
      list = [];
    }
  };
  for (const line of text.split("\n")) {
    const t = line.trimEnd();
    if (/^\s*[-*] /.test(t)) {
      list.push(t.replace(/^\s*[-*] /, ""));
      continue;
    }
    flush();
    if (!t.trim()) continue;
    const h = t.match(/^(#{1,4})\s+(.*)$/);
    if (h)
      out.push(
        <h3
          key={out.length}
          className={(h[1] as string).length <= 2 ? "mt-3 text-lg font-semibold" : "mt-2 font-semibold"}
        >
          {h[2]}
        </h3>,
      );
    else out.push(<p key={out.length}>{t.replace(/\*\*(.+?)\*\*/g, "$1")}</p>);
  }
  flush();
  return <div className="grid gap-2 text-sm leading-relaxed">{out}</div>;
}
