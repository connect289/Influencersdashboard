"use client";
import { Switch as S } from "radix-ui";
import type { ComponentProps } from "react";
import { cn } from "@/lib/utils";

export function Switch({ className, ...props }: ComponentProps<typeof S.Root>) {
  return (
    <S.Root className={cn("relative inline-flex h-6 w-11 shrink-0 items-center rounded-full bg-line-strong transition-colors data-[state=checked]:bg-primary", className)} {...props}>
      <S.Thumb className="block size-5 translate-x-0.5 rounded-full bg-surface shadow transition-transform data-[state=checked]:translate-x-[22px]" />
    </S.Root>
  );
}
