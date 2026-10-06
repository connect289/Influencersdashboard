"use client";
import { startTransition, useActionState, type FormEvent } from "react";

/**
 * A server action bound to a form without React's automatic form reset (which would wipe the Admin's input when the
 * action returns validation errors). Returns the action state, an onSubmit handler and the pending flag.
 */
export function useFormAction<S>(action: (prev: Awaited<S>, form: FormData) => Promise<S>, initial: Awaited<S>) {
  const [state, dispatch, pending] = useActionState<S, FormData>(action, initial);
  const onSubmit = (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    const data = new FormData(e.currentTarget);
    startTransition(() => dispatch(data));
  };
  return [state, onSubmit, pending] as const;
}
