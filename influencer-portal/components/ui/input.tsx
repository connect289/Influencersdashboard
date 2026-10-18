import type { ComponentProps } from "react";
import { cn } from "@/lib/utils";

const field =
  "w-full rounded-xl bg-surface px-3 text-ink ring-1 ring-inset ring-line-strong placeholder:text-faint focus-visible:outline-2 focus-visible:outline-offset-0 aria-[invalid=true]:ring-danger disabled:opacity-60";

export function Input({ className, ...props }: ComponentProps<"input">) {
  return <input className={cn(field, "h-11 md:h-10", className)} {...props} />;
}

export function Textarea({ className, ...props }: ComponentProps<"textarea">) {
  return <textarea className={cn(field, "min-h-24 py-2", className)} {...props} />;
}

export function Select({ className, ...props }: ComponentProps<"select">) {
  return <select className={cn(field, "h-11 pr-8 md:h-10", className)} {...props} />;
}
