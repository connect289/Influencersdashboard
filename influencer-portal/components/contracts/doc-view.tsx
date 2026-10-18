// Renders contract document blocks as React elements (never as stored HTML). Used for contracts, clause previews and
// change-request suggestions.
import type { Block, Inline } from "@/lib/contracts/doc";
import { cn } from "@/lib/utils";

function InlineView({ content }: { content: readonly Inline[] | undefined }) {
  return (
    <>
      {(content ?? []).map((n, i) => {
        if (n.type === "hardBreak") return <br key={i} />;
        let el: React.ReactNode = n.text;
        for (const m of n.marks ?? []) {
          if (m.type === "bold") el = <strong>{el}</strong>;
          else if (m.type === "italic") el = <em>{el}</em>;
          else el = <u>{el}</u>;
        }
        return <span key={i}>{el}</span>;
      })}
    </>
  );
}

function BlockView({ block }: { block: Block }) {
  switch (block.type) {
    case "paragraph":
      return (
        <p>
          <InlineView content={block.content} />
        </p>
      );
    case "heading": {
      const H = `h${String(block.attrs.level)}` as "h2" | "h3" | "h4";
      return (
        <H>
          <InlineView content={block.content} />
        </H>
      );
    }
    case "bulletList":
    case "orderedList": {
      const L = block.type === "bulletList" ? "ul" : "ol";
      return (
        <L>
          {block.content.map((li, i) => (
            <li key={i}>
              {li.content.map((b, j) => (
                <BlockView key={j} block={b} />
              ))}
            </li>
          ))}
        </L>
      );
    }
    case "table":
      return (
        <div className="overflow-x-auto">
          <table>
            <thead>
              <tr>
                {block.head.map((h, i) => (
                  <th key={i} scope="col">
                    {h}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {block.rows.map((r, i) => (
                <tr key={i}>
                  {r.map((c, j) => (
                    <td key={j}>{c}</td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      );
  }
}

export function DocView({ blocks, className }: { blocks: readonly Block[]; className?: string }) {
  return (
    <div className={cn("doc", className)}>
      {blocks.map((b, i) => (
        <BlockView key={i} block={b} />
      ))}
    </div>
  );
}
