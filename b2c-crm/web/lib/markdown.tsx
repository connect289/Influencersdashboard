import { Fragment } from "react";

/**
 * The guides' small Markdown (spec B16): a blank line starts a paragraph, "- " lines are a list, **bold**. Rendered as
 * React elements, never as HTML, so an article cannot inject markup.
 */
function inline(text: string) {
  return text.split(/(\*\*[^*]+\*\*)/g).map((part, i) =>
    part.startsWith("**") && part.endsWith("**") && part.length > 4 ? <b key={i}>{part.slice(2, -2)}</b> : <Fragment key={i}>{part}</Fragment>);
}

export function Markdown({ text }: { text: string }) {
  const blocks = text.replace(/\r\n?/g, "\n").trim().split(/\n{2,}/);
  return (
    <>
      {blocks.map((b, i) => {
        const lines = b.split("\n");
        if (lines.every((l) => /^\s*- /.test(l))) {
          return <ul key={i} className="md-list">{lines.map((l, k) => <li key={k}>{inline(l.replace(/^\s*- /, ""))}</li>)}</ul>;
        }
        return <p key={i}>{lines.map((l, k) => <Fragment key={k}>{k > 0 && <br />}{inline(l)}</Fragment>)}</p>;
      })}
    </>
  );
}

/** Does an article's screen pattern cover this path? "/s/leads/*" covers every lead; others match exactly. */
export function screenMatches(pattern: string, path: string): boolean {
  if (pattern.endsWith("/*")) return path.startsWith(pattern.slice(0, -1)) && path.length > pattern.length - 1;
  return pattern === path;
}
