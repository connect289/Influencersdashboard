"use client";
import { useFormStatus } from "react-dom";

/** Submit button that disables itself while its form's server action runs. */
export function SubmitButton({
  children,
  pendingLabel,
  className = "btn primary",
  disabled,
  name,
  value,
}: {
  children: React.ReactNode;
  pendingLabel?: string;
  className?: string;
  disabled?: boolean;
  name?: string;
  value?: string;
}) {
  const { pending } = useFormStatus();
  return (
    <button type="submit" className={className} disabled={pending || disabled} aria-busy={pending} name={name} value={value}>
      {pending && pendingLabel ? pendingLabel : children}
    </button>
  );
}
