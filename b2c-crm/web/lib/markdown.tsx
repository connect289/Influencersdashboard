/* eslint-disable @next/next/no-img-element */
import { Fragment } from "react";

/**
 * The guides' small Markdown (spec B16): a blank line starts a paragraph, "- " lines are a list, **bold**, and
 * ![caption](image:N) shows the article's Nth screenshot (from 1) through a short signed link. Rendered as React
 * elements, never as HTML, so an article cannot inject markup.
 */
export type MdImage = { url: string | null; caption?: string | null };

const IMAGE = /^!\[([^\]]*)\]\(image:(\d{1,2})\)$/;

function image(alt: string, n: number, images: MdImage[] | undefined, key: number | string, block: boolean) {
  const img = images?.[n - 1];
  const caption = alt || img?.caption || `Screenshot ${n}`;
  if (!img?.url) return <span key={key} className="muted">[{caption}]</span>;
  const el = <img src={img.url} alt={caption} loading="lazy" style={{ maxWidth: "100%", height: "auto", borderRadius: 8, border: "1px solid var(--line)" }} />;
  return block ? <figure key={key} className="md-figure" style={{ margin: "8px 0" }}>{el}<figcaption className="small muted">{caption}</figcaption></figure> : <Fragment key={key}>{el}</Fragment>;
}

function inline(text: string, images?: MdImage[]) {
  return text.split(/(\*\*[^*]+\*\*|!\[[^\]]*\]\(image:\d{1,2}\))/g).map((part, i) => {
    const m = IMAGE.exec(part);
    if (m) return image(m[1]!, Number(m[2]), images, i, false);
    return part.startsWith("**") && part.endsWith("**") && part.length > 4 ? <b key={i}>{part.slice(2, -2)}</b> : <Fragment key={i}>{part}</Fragment>;
  });
}

export function Markdown({ text, images }: { text: string; images?: MdImage[] }) {
  const blocks = text.replace(/\r\n?/g, "\n").trim().split(/\n{2,}/);
  return (
    <>
      {blocks.map((b, i) => {
        const lines = b.split("\n");
        const only = IMAGE.exec(b.trim());
        if (only) return image(only[1]!, Number(only[2]), images, i, true);
        if (lines.every((l) => /^\s*- /.test(l))) {
          return <ul key={i} className="md-list">{lines.map((l, k) => <li key={k}>{inline(l.replace(/^\s*- /, ""), images)}</li>)}</ul>;
        }
        return <p key={i}>{lines.map((l, k) => <Fragment key={k}>{k > 0 && <br />}{inline(l, images)}</Fragment>)}</p>;
      })}
    </>
  );
}

/** Does an article's screen pattern cover this path? "/s/leads/*" covers every lead; others match exactly. */
export function screenMatches(pattern: string, path: string): boolean {
  if (pattern.endsWith("/*")) return path.startsWith(pattern.slice(0, -1)) && path.length > pattern.length - 1;
  return pattern === path;
}
