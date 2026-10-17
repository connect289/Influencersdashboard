"use client";

import { Checkbox as Cb } from "radix-ui";
import { Check } from "lucide-react";
import { cn } from "@/lib/utils";

export function Checkbox({ className, ...props }: React.ComponentProps<typeof Cb.Root>) {
  return (
    <Cb.Root
      className={cn(
        "border-border-strong bg-bg-elev data-[state=checked]:border-primary data-[state=checked]:bg-primary data-[state=checked]:text-on-primary aria-[invalid=true]:border-danger grid size-5 shrink-0 place-items-center rounded-[6px] border transition-colors",
        className,
      )}
      {...props}
    >
      <Cb.Indicator>
        <Check className="size-3.5" strokeWidth={3} aria-hidden />
      </Cb.Indicator>
    </Cb.Root>
  );
}
