"use client";
import { useFormStatus } from "react-dom";
import { LoaderCircle } from "lucide-react";
import { Button, type ButtonProps } from "./Button";

/** Submit button that disables itself and shows a spinner while its form's server action runs. */
export function SubmitButton({ children, pendingLabel, ...rest }: ButtonProps & { pendingLabel?: string }) {
  const { pending } = useFormStatus();
  return (
    <Button type="submit" disabled={pending || rest.disabled} aria-busy={pending} {...rest}>
      {pending && <LoaderCircle className="size-4 animate-spin" aria-hidden />}
      {pending && pendingLabel ? pendingLabel : children}
    </Button>
  );
}
