"use client";
import { useTransition } from "react";
import { toast } from "sonner";
import type { ActionResult } from "@/lib/actions/result";

/** Runs a server action in a transition, toasts its message or error, and calls `onOk` with its data on success. */
export function useAction() {
  const [pending, start] = useTransition();
  function run<T>(fn: () => Promise<ActionResult<T>>, onOk?: (data: T | undefined) => void) {
    start(async () => {
      const r = await fn();
      if (r.ok) {
        if (r.message) toast.success(r.message);
        onOk?.(r.data);
      } else toast.error(r.error);
    });
  }
  return { pending, run };
}
