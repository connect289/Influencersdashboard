import type { ComponentProps } from "react";
import { cn } from "@/lib/utils";

/** Plain accessible table with sticky header; on phones it scrolls horizontally inside its card. */
export function Table({ className, ...props }: ComponentProps<"table">) {
  return (
    // Focusable so keyboard users can scroll a wide table sideways.
    <div
      tabIndex={0}
      className="-mx-4 overflow-x-auto focus-visible:outline-2 focus-visible:outline-[var(--focus)] md:mx-0"
    >
      <table className={cn("w-full min-w-[640px] border-collapse text-sm", className)} {...props} />
    </div>
  );
}
export function Th({ className, ...props }: ComponentProps<"th">) {
  return (
    <th
      scope="col"
      className={cn("border-b border-line bg-surface px-3 py-2 text-left text-xs font-medium text-muted", className)}
      {...props}
    />
  );
}
export function Td({ className, ...props }: ComponentProps<"td">) {
  return <td className={cn("border-b border-line px-3 py-2.5 align-top", className)} {...props} />;
}
