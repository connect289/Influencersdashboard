import { AlertCircle } from "lucide-react";
import { useId, type ReactNode } from "react";
import { cn } from "@/lib/utils";

/** Label + control + hint + error, wired with ids for screen readers (aria-describedby / aria-invalid). */
export function Field({
  label,
  hint,
  error,
  optional,
  children,
  className,
}: {
  label: ReactNode;
  hint?: ReactNode;
  error?: string | null;
  optional?: boolean;
  className?: string;
  children: (ids: { id: string; describedBy: string | undefined; invalid: boolean }) => ReactNode;
}) {
  const id = useId();
  const hintId = hint ? `${id}-hint` : undefined;
  const errId = error ? `${id}-err` : undefined;
  return (
    <div className={cn("grid gap-1.5", className)}>
      <label htmlFor={id} className="text-text text-sm font-medium">
        {label}
        {optional ? <span className="text-subtle ml-1 font-normal">(optional)</span> : null}
      </label>
      {children({ id, describedBy: [hintId, errId].filter(Boolean).join(" ") || undefined, invalid: !!error })}
      {hint && !error ? (
        <p id={hintId} className="text-subtle text-xs">
          {hint}
        </p>
      ) : null}
      {error ? (
        <p id={errId} role="alert" className="text-danger flex items-center gap-1 text-xs font-medium">
          <AlertCircle className="size-3.5" aria-hidden />
          {error}
        </p>
      ) : null}
    </div>
  );
}
