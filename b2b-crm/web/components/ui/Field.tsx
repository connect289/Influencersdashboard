import type { InputHTMLAttributes } from "react";
import { cn } from "./cn";

export function Input({ className, ...rest }: InputHTMLAttributes<HTMLInputElement>) {
  return (
    <input
      className={cn(
        "h-10 w-full rounded-lg border border-border bg-surface px-3 text-sm text-fg placeholder:text-subtle",
        "transition-colors hover:border-border-strong focus:border-ring focus:outline-none focus:ring-2 focus:ring-ring/30",
        "aria-[invalid=true]:border-danger",
        className,
      )}
      {...rest}
    />
  );
}

export function Field({ label, htmlFor, hint, children, action }: {
  label: string;
  htmlFor: string;
  hint?: string;
  action?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-baseline justify-between">
        <label htmlFor={htmlFor} className="text-[13px] font-medium text-fg">{label}</label>
        {action}
      </div>
      {children}
      {hint && <p className="text-xs text-muted">{hint}</p>}
    </div>
  );
}
