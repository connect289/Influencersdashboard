"use client";
import { useRouter } from "next/navigation";
import { type FormEvent, type ReactNode, useRef, useState } from "react";
import type { Action, ActionResult } from "@/lib/actions/act.ts";
import { cn } from "@/lib/cn.ts";

/**
 * Runs a server action from a form and shows its result in place (role="status" or "alert"), then refreshes the page's
 * data. The action is called from the submit handler and its result kept in plain state, not through a form action and
 * useActionState: in the click-through, a resolved form action's result sometimes never committed and the form stayed
 * pending (D-074). On success the form is cleared, as a form action would, and the refresh runs after the answer.
 */
export function ActionForm({
  action,
  children,
  className,
}: {
  action: Action;
  children: ReactNode;
  className?: string;
}) {
  const router = useRouter();
  const [state, setState] = useState<ActionResult | undefined>(undefined);
  const [pending, setPending] = useState(false);
  const busy = useRef(false);

  async function submit(e: FormEvent<HTMLFormElement>) {
    e.preventDefault();
    if (busy.current) return;
    busy.current = true;
    const form = e.currentTarget;
    const data = new FormData(form, (e.nativeEvent as SubmitEvent).submitter);
    setPending(true);
    try {
      const result = await action(state, data);
      setState(result);
      if (result.ok) {
        form.reset();
        router.refresh();
      }
    } catch {
      setState({ ok: false, error: "That did not work. Try again." });
    } finally {
      busy.current = false;
      setPending(false);
    }
  }

  return (
    <form onSubmit={submit} className={cn("grid gap-2", className)} aria-busy={pending}>
      <fieldset disabled={pending} className="contents">
        {children}
      </fieldset>
      {state ? (
        state.ok ? (
          <p role="status" className="text-sm text-ok">
            {state.message ?? "Done."}
          </p>
        ) : (
          <p role="alert" className="text-sm text-p1">
            {state.error}
          </p>
        )
      ) : null}
    </form>
  );
}
