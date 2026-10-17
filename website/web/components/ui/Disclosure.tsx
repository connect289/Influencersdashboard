import { ChevronDown } from "lucide-react";
import { cn } from "@/lib/utils";

/**
 * Zero-JavaScript accordion built on <details>/<summary> for server-rendered content (FAQs, explanations). Accessible by
 * default (native expanded state, keyboard), searchable by find-in-page, and animated with CSS where supported.
 */
export function Disclosure({
  items,
  className,
  name,
}: {
  items: { id: string; title: React.ReactNode; content: React.ReactNode }[];
  className?: string;
  name?: string;
}) {
  return (
    <div className={cn("divide-border border-border divide-y rounded-[var(--radius-lg)] border", className)}>
      {items.map((it) => (
        <details key={it.id} name={name} className="disclosure group">
          <summary className="text-text hover:bg-surface-hover flex cursor-pointer list-none items-center justify-between gap-4 px-5 py-4 font-medium [&::-webkit-details-marker]:hidden">
            {it.title}
            <ChevronDown
              className="text-subtle size-5 shrink-0 transition-transform duration-300 group-open:rotate-180"
              aria-hidden
            />
          </summary>
          <div className="text-muted px-5 pb-5">{it.content}</div>
        </details>
      ))}
    </div>
  );
}
