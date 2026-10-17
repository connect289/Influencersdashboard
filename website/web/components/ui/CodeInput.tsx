"use client";

import { unstable_OneTimePasswordField as Otp } from "radix-ui";
import { cn } from "@/lib/utils";

/**
 * 6-digit verification code, entered inline (spec 7.2). Supports paste, SMS/email autofill (autocomplete=one-time-code),
 * numeric keyboard, and arrow-key navigation. `onComplete` fires when all digits are filled.
 */
export function CodeInput({
  value,
  onValueChange,
  onComplete,
  invalid,
  disabled,
  length = 6,
  label = "Verification code",
}: {
  value: string;
  onValueChange: (v: string) => void;
  onComplete?: (v: string) => void;
  invalid?: boolean;
  disabled?: boolean;
  length?: number;
  label?: string;
}) {
  return (
    <Otp.Root
      value={value}
      onValueChange={onValueChange}
      autoSubmit={!!onComplete}
      onAutoSubmit={onComplete}
      validationType="numeric"
      autoComplete="one-time-code"
      disabled={disabled}
      aria-label={label}
      className="flex gap-2"
    >
      {Array.from({ length }, (_, i) => (
        <Otp.Input
          key={i}
          aria-invalid={invalid || undefined}
          className={cn(
            "tabular border-border bg-bg-elev/70 font-display text-text focus:border-focus aria-[invalid=true]:border-danger h-14 w-11 rounded-[var(--radius-md)] border text-center text-2xl transition-[border,box-shadow] outline-none focus:shadow-[0_0_0_3px_color-mix(in_oklab,var(--focus)_25%,transparent)] sm:w-12",
          )}
        />
      ))}
      <Otp.HiddenInput />
    </Otp.Root>
  );
}
