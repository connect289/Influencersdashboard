import Link from "next/link";
import { Info, TriangleAlert } from "lucide-react";
import { useTranslations } from "next-intl";
import type { ReactNode } from "react";
import { Card } from "@/components/ui/card";
import { Table, Td, Th } from "@/components/ui/table";
import type { Block, Guide } from "@/lib/guides/types";

/** **bold**, `code` and [label](/path) inside guide text. Internal links only (guides never link out). */
export function Inline({ text }: { text: string }): ReactNode {
  const out: ReactNode[] = [];
  const re = /\*\*(.+?)\*\*|`(.+?)`|\[(.+?)\]\((\/[^)\s]*)\)/g;
  let last = 0;
  let n = 0;
  for (const m of text.matchAll(re)) {
    if (m.index > last) out.push(text.slice(last, m.index));
    if (m[1] !== undefined) out.push(<strong key={n++}>{m[1]}</strong>);
    else if (m[2] !== undefined)
      out.push(
        <code key={n++} className="rounded bg-surface-2 px-1 py-0.5 text-[0.85em]">
          {m[2]}
        </code>,
      );
    else
      out.push(
        <Link key={n++} href={m[4] ?? "/"} className="font-medium text-primary underline-offset-2 hover:underline">
          {m[3]}
        </Link>,
      );
    last = m.index + m[0].length;
  }
  if (last < text.length) out.push(text.slice(last));
  return <>{out}</>;
}

function BlockView({ b }: { b: Block }) {
  if ("p" in b)
    return (
      <p className="text-sm leading-relaxed">
        <Inline text={b.p} />
      </p>
    );
  if ("h" in b) return <h4 className="text-sm font-semibold">{b.h}</h4>;
  if ("steps" in b)
    return (
      <ol className="flex list-decimal flex-col gap-1.5 pl-5 text-sm leading-relaxed">
        {b.steps.map((s, i) => (
          <li key={i}>
            <Inline text={s} />
          </li>
        ))}
      </ol>
    );
  if ("list" in b)
    return (
      <ul className="flex list-disc flex-col gap-1.5 pl-5 text-sm leading-relaxed">
        {b.list.map((s, i) => (
          <li key={i}>
            <Inline text={s} />
          </li>
        ))}
      </ul>
    );
  if ("tip" in b)
    return (
      <p className="flex gap-2 rounded-xl bg-primary-soft px-3 py-2 text-sm text-primary">
        <Info className="mt-0.5 size-4 shrink-0" aria-hidden />
        <span>
          <Inline text={b.tip} />
        </span>
      </p>
    );
  if ("warning" in b)
    return (
      <p className="flex gap-2 rounded-xl bg-accent-soft px-3 py-2 text-sm text-accent-ink">
        <TriangleAlert className="mt-0.5 size-4 shrink-0" aria-hidden />
        <span>
          <Inline text={b.warning} />
        </span>
      </p>
    );
  return (
    <Table>
      <thead>
        <tr>
          {b.table.head.map((h) => (
            <Th key={h}>{h}</Th>
          ))}
        </tr>
      </thead>
      <tbody>
        {b.table.rows.map((r, i) => (
          <tr key={i}>
            {r.map((c, j) => (
              <Td key={j} className="align-top text-sm">
                <Inline text={c} />
              </Td>
            ))}
          </tr>
        ))}
      </tbody>
    </Table>
  );
}

/** A full guide: contents on the side (top on phones), then each section with an anchor. */
export function GuideView({ guide }: { guide: Guide }) {
  const t = useTranslations();
  return (
    <div className="grid items-start gap-4 lg:grid-cols-[220px_minmax(0,1fr)]">
      <nav aria-label={t("help.contents")} className="lg:sticky lg:top-20">
        <Card>
          <h2 className="mb-2 text-sm font-semibold">{t("help.contents")}</h2>
          <ol className="flex flex-col gap-1 text-sm">
            {guide.sections.map((s) => (
              <li key={s.id}>
                <a href={`#${s.id}`} className="text-muted hover:text-primary">
                  {s.title}
                </a>
              </li>
            ))}
          </ol>
        </Card>
      </nav>
      <div className="flex flex-col gap-4">
        {guide.sections.map((s) => (
          <Card key={s.id}>
            <section id={s.id} className="flex scroll-mt-24 flex-col gap-3" aria-labelledby={`${s.id}-title`}>
              <h2 id={`${s.id}-title`} className="text-base font-semibold">
                {s.title}
              </h2>
              {s.blocks.map((b, i) => (
                <BlockView key={i} b={b} />
              ))}
            </section>
          </Card>
        ))}
      </div>
    </div>
  );
}
