"use client";
import { useActionState } from "react";
import { Button } from "@/components/ui/button.tsx";
import { Field, Input } from "@/components/ui/field.tsx";
import { Banner } from "@/components/ui/state.tsx";
import { sendCode, verifyCode, type FormState } from "../actions.ts";

export function VerifyForm({ next }: { next: string }) {
  const [sent, send, sending] = useActionState<FormState, FormData>(sendCode, undefined);
  const [checked, verify, verifying] = useActionState<FormState, FormData>(verifyCode, undefined);
  const message = checked?.error ?? sent?.error;
  return (
    <div className="grid gap-4">
      {message ? <Banner tone="p1">{message}</Banner> : null}
      {sent?.notice && !checked?.error ? <Banner tone="p3">{sent.notice}</Banner> : null}
      <form action={send}>
        <Button type="submit" variant={sent?.notice ? "secondary" : "primary"} disabled={sending} className="w-full">
          {sending ? "Sending…" : sent?.notice ? "Send a new code" : "Email me a code"}
        </Button>
      </form>
      <form action={verify} className="grid gap-3">
        <input type="hidden" name="next" value={next} />
        <Field label="Code from the email">
          <Input
            name="code"
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9 ]{6,7}"
            maxLength={7}
            required
          />
        </Field>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" name="trust" className="size-4" />
          Trust this browser for 30 days
        </label>
        <Button type="submit" disabled={verifying}>
          {verifying ? "Checking…" : "Continue"}
        </Button>
      </form>
    </div>
  );
}
