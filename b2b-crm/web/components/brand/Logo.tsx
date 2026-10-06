import Image from "next/image";
import { cn } from "@/components/ui/cn";

/** The Eduwit mark on a white tile (the artwork has a light background) plus the two-tone wordmark. */
export function LogoMark({ size = 32, className }: { size?: number; className?: string }) {
  return (
    <span
      className={cn("inline-grid shrink-0 place-items-center overflow-hidden rounded-[9px] bg-white ring-1 ring-black/5", className)}
      style={{ width: size, height: size }}
    >
      <Image src="/brand/eduwit-mark.png" alt="" width={size} height={size} priority className="scale-110" />
    </span>
  );
}

export function Logo({ compact = false, className }: { compact?: boolean; className?: string }) {
  return (
    <span className={cn("inline-flex items-center gap-2.5", className)} aria-label="Eduwit Partner CRM">
      <LogoMark />
      {!compact && (
        <span className="flex flex-col leading-none">
          <span className="text-[15px] font-semibold tracking-tight">
            <span className="text-navy dark:text-fg">Edu</span>
            <span className="text-amber">wit</span>
          </span>
          <span className="mt-1 text-[10.5px] font-medium uppercase tracking-[0.14em] text-subtle">Partner CRM</span>
        </span>
      )}
    </span>
  );
}
