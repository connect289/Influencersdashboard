"use client";
import { useActionState, type ReactNode } from "react";
import type { Action, ActionResult } from "@/lib/actions/act.ts";
import { cn } from "@/lib/cn.ts";

/** Runs a server action from a form and shows its result in place (role="status" or "alert"). */
export function ActionForm({
  action,
  children,
  className,
}: {
  action: Action;
  children: ReactNode;
  className?: string;
}) {
  const [state, run, pending] = useActionState<ActionResult | undefined, FormData>(action, undefined);
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
