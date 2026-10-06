"use client";
import { useTransition } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/Button";
import { signOutOtherDevices } from "./actions";

export function SignOutOthers({ disabled }: { disabled: boolean }) {
  const [pending, start] = useTransition();
  return (
    <Button
      variant="secondary"
      size="sm"
      disabled={disabled || pending}
      onClick={() =>
        start(async () => {
          const { ok } = await signOutOtherDevices();
          if (ok) toast.success("Signed out of every other device.");
          else toast.error("Could not sign out other devices. Try again.");
        })
      }
    >
      {pending ? "Signing out…" : "Sign out other devices"}
    </Button>
  );
}
