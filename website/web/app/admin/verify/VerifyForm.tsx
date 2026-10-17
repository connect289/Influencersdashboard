"use client";

import { useActionState, useState, useTransition } from "react";
import { Button } from "@/components/ui/Button";
import { CodeInput } from "@/components/ui/CodeInput";
import { sendAdminCode, verifyAdminCode, type ActionState } from "../actions";

export function VerifyForm({ email }: { email: string }) {
  const [code, setCode] = useState("");
  const [sent, setSent] = useState<ActionState>(null);
  const [sending, startSend] = useTransition();
  const [state, action, pending] = useActionState<ActionState, FormData>(verifyAdminCode, null);
  return (
    <div className="grid gap-4">
      <p className="text-muted text-sm">We&apos;ll email a 6-digit code to {email}.</p>
      <Button
        type="button"
        variant="secondary"
        disabled={sending}
        onClick={() => startSend(async () => setSent(await sendAdminCode()))}
      >
        {sending ? "Sending…" : sent?.info ? "Send a new code" : "Send code"}
      </Button>
      {sent?.info ? <p className="text-success text-sm">{sent.info} Check spam if it doesn&apos;t arrive.</p> : null}
      {sent?.error ? (
        <p role="alert" className="text-danger text-sm">
          {sent.error}
        </p>
      ) : null}
      <form action={action} className="grid gap-4">
        <CodeInput value={code} onValueChange={setCode} invalid={!!state?.error} />
        <input type="hidden" name="code" value={code} />
        <label className="text-muted flex items-center gap-2 text-sm">
          <input type="checkbox" name="trust" className="size-4 accent-[var(--primary)]" /> Trust this device for 30
          days
        </label>
        {state?.error ? (
          <p role="alert" className="text-danger text-sm font-medium">
            {state.error}
          </p>
        ) : null}
        <Button type="submit" disabled={pending || code.length !== 6}>
          {pending ? "Checking…" : "Verify"}
        </Button>
      </form>
    </div>
  );
}
