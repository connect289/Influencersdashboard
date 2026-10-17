import { Fragment } from "react";

/**
 * Markdown-lite for Witty's replies: paragraphs, "- " / "• " bullets, **bold** / *bold*, and bare https links (brochures).
 * Builds React nodes (no HTML injection).
 */
function inline(text: string, key: string) {
  const parts = text.split(/(\*\*[^*]+\*\*|\*[^*\s][^*]*\*|https:\/\/\S+)/g).filter(Boolean);
  return parts.map((p, i) => {
    if (/^\*\*[^*]+\*\*$/.test(p)) return <strong key={`${key}-${i}`}>{p.slice(2, -2)}</strong>;
    if (/^\*[^*]+\*$/.test(p)) return <strong key={`${key}-${i}`}>{p.slice(1, -1)}</strong>;
    if (/^https:\/\//.test(p))
      return (
        <a key={`${key}-${i}`} href={p.replace(/[).,]+$/, "")} target="_blank" rel="noopener noreferrer" className="text-accent underline underline-offset-4">
          Brochure
        </a>
      );
    return <Fragment key={`${key}-${i}`}>{p}</Fragment>;
  });
}

export function RichText({ text }: { text: string }) {
  const blocks = text.split(/\n{2,}/);
  return (
    <>
      {blocks.map((b, bi) => {
        const lines = b.split("\n");
        const bullets = lines.filter((l) => /^\s*([-•])\s+/.test(l));
        if (bullets.length && bullets.length === lines.filter((l) => l.trim()).length) {
          return (
            <ul key={bi} className="my-2 grid list-disc gap-1 pl-5">
              {lines.filter((l) => l.trim()).map((l, li) => (
                <li key={li}>{inline(l.replace(/^\s*[-•]\s+/, ""), `${bi}-${li}`)}</li>
              ))}
            </ul>
          );
        }
        return (
          <p key={bi} className="my-2 first:mt-0 last:mb-0">
            {lines.map((l, li) => (
              <Fragment key={li}>
                {li ? <br /> : null}
                {inline(l, `${bi}-${li}`)}
              </Fragment>
            ))}
          </p>
        );
      })}
    </>
  );
}
