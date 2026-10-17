import Image from "next/image";
import { cn } from "@/lib/utils";

/** The Eduwit mark with the product name. Navy "Edu" and amber-ink "wit", as in the logo. */
export function Logo({
  className,
  compact = false,
  label,
}: {
  className?: string;
  compact?: boolean;
  label: string;
}) {
  return (
    <span className={cn("inline-flex items-center gap-2", className)}>
      <Image
        src="/brand/icon-192.png"
        alt=""
        width={32}
        height={32}
        className="size-8 rounded-md bg-white"
        priority
      />
      {compact ? (
        <span className="sr-only">{label}</span>
      ) : (
        <span className="leading-tight">
          <span className="block text-[15px] font-bold">
            <span className="text-primary">Edu</span>
            <span className="text-accent-ink">wit</span>
          </span>
          <span className="block text-xs text-muted">{label}</span>
        </span>
      )}
    </span>
  );
}
