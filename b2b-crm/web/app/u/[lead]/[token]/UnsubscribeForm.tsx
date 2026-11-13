"use client";
import { useActionState, useEffect, useRef } from "react";
import { CircleCheck } from "lucide-react";
import { Notice } from "@/components/ui/Notice";
import { SubmitButton } from "@/components/ui/SubmitButton";
import { confirmUnsubscribe } from "./actions";

/**
 * The confirm step. Opening the link changes nothing (mail scanners open links); only this button does. The same
 * "done" screen follows a valid link, a link already used and a link that is not valid, and it names nobody.
 */
export function UnsubscribeForm({ lead, token }: { lead: string; token: string }) {
  const [state, action] = useActionState(confirmUnsubscribe, undefined);
  const done = state?.status === "done";
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => { if (done) heading.current?.focus(); }, [done]);

  if (done) {
    return (
      <div role="status">
        <CircleCheck className="size-9 text-success" aria-hidden />
        <h1 ref={heading} tabIndex={-1} className="mt-4 text-xl font-semibold tracking-tight text-fg outline-none">You are unsubscribed</h1>
        <p className="mt-2 text-[15px] leading-6 text-muted">You will no longer receive emails about your enquiry from Eduwit. You can close this page.</p>
      </div>
    );
  }

  return (
    <div>
      <h1 className="text-xl font-semibold tracking-tight text-fg">Stop emails from Eduwit?</h1>
      <p className="mt-2 text-[15px] leading-6 text-muted">Press the button and you will no longer receive emails about your enquiry from Eduwit.</p>
      <form action={action} className="mt-6 space-y-4">
        <input type="hidden" name="lead" value={lead} />
        <input type="hidden" name="token" value={token} />
        {state?.status === "error" && <Notice tone="error">{state.message}</Notice>}
        <SubmitButton size="lg" className="w-full justify-center" pendingLabel="Unsubscribing…">Unsubscribe</SubmitButton>
      </form>
    </div>
  );
}
