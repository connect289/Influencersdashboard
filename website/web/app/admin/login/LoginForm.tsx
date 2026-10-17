"use client";

import { useActionState } from "react";
import { Button } from "@/components/ui/Button";
import { Field } from "@/components/ui/Field";
import { Input } from "@/components/ui/Input";
import { signInWithGoogle, signInWithPassword, type ActionState } from "../actions";

export function LoginForm({ googleError }: { googleError?: boolean }) {
  const [state, action, pending] = useActionState<ActionState, FormData>(
    signInWithPassword,
    googleError ? { error: "Google sign-in failed. Try again." } : null,
  );
  return (
    <div className="grid gap-5">
      <form action={signInWithGoogle}>
        <Button type="submit" variant="secondary" className="w-full">
          Continue with Google
        </Button>
      </form>
      <p className="text-subtle text-center text-xs">or</p>
      <form action={action} className="grid gap-4">
        <Field label="Work email">
          {(p) => <Input id={p.id} name="email" type="email" autoComplete="username" required />}
        </Field>
        <Field label="Password">
          {(p) => (
            <Input id={p.id} name="password" type="password" autoComplete="current-password" required minLength={8} />
          )}
        </Field>
        {state?.error ? (
          <p role="alert" className="text-danger text-sm font-medium">
            {state.error}
          </p>
        ) : null}
        <Button type="submit" disabled={pending}>
          {pending ? "Signing in…" : "Sign in"}
        </Button>
      </form>
    </div>
  );
}
