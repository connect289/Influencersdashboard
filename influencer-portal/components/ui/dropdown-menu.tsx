"use client";
import { DropdownMenu as M } from "radix-ui";
import type { ComponentProps } from "react";
import { cn } from "@/lib/utils";

export const DropdownMenu = M.Root;
export const DropdownMenuTrigger = M.Trigger;

export function DropdownMenuContent({ className, ...props }: ComponentProps<typeof M.Content>) {
  return (
    <M.Portal>
      <M.Content
        sideOffset={6}
        className={cn(
          "z-50 min-w-48 rounded-xl bg-surface p-1 shadow-[var(--shadow-card)] ring-1 ring-line",
          className,
        )}
        {...props}
      />
    </M.Portal>
  );
}

export function DropdownMenuItem({ className, ...props }: ComponentProps<typeof M.Item>) {
  return (
    <M.Item
      className={cn(
        "flex cursor-pointer items-center gap-2 rounded-lg px-3 py-2 text-sm outline-none select-none data-[highlighted]:bg-surface-2 [&_svg]:size-4",
        className,
      )}
      {...props}
    />
  );
}

export function DropdownMenuLabel({ className, ...props }: ComponentProps<typeof M.Label>) {
  return <M.Label className={cn("px-3 py-1.5 text-xs text-muted", className)} {...props} />;
}

export function DropdownMenuSeparator() {
  return <M.Separator className="my-1 h-px bg-line" />;
}
