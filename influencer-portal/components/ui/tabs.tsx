"use client";
import { Tabs as T } from "radix-ui";
import type { ComponentProps } from "react";
import { cn } from "@/lib/utils";

export const Tabs = T.Root;
export const TabsContent = T.Content;

export function TabsList({ className, ...props }: ComponentProps<typeof T.List>) {
  return (
    <T.List
      className={cn("mb-4 flex gap-1 overflow-x-auto rounded-xl bg-surface-2 p-1", className)}
      {...props}
    />
  );
}

export function TabsTrigger({ className, ...props }: ComponentProps<typeof T.Trigger>) {
  return (
    <T.Trigger
      className={cn(
        "rounded-lg px-3 py-1.5 text-sm whitespace-nowrap text-muted data-[state=active]:bg-surface data-[state=active]:text-ink data-[state=active]:shadow-sm",
        className,
      )}
      {...props}
    />
  );
}
