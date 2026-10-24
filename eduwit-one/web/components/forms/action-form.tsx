"use client";
import { useRouter } from "next/navigation";
import { useActionState, useEffect, type ReactNode } from "react";
import type { Action, ActionResult } from "@/lib/actions/act.ts";
import { cn } from "@/lib/cn.ts";

/**
 * Runs a server action from a form and shows its result in place (role="status" or "alert"), then refreshes the page's
 * data. The refresh runs after the answer is shown and outside the action, so a slow refresh can delay fresh data but
 * never the answer (actions do not revalidate; lib/actions/act.ts).
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
  const [state, run, pending] = useActionState<ActionResult | undefined, FormData>(action, undefined);
  useEffect(() => {
    if (state?.ok) router.refresh();
  }, [state, router]);
  return (
    <form action={run} className={cn("grid gap-2", className)} aria-busy={pending}>
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
