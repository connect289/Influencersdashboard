"use client";

import Link from "next/link";
import { useActionState, useEffect, useState } from "react";
import { deletionRequestAction, syncShortlistAction, withdrawConsentAction, type AccountActionState } from "@/app/actions/account";
import { saved, useSaved } from "@/lib/client/saved-store";

/** Merges this device's shortlist with the account's, then mirrors the result locally (spec 12 shortlist). */
export function ShortlistSync({ showSummary = false }: { showSummary?: boolean }) {
  const ids = useSaved("shortlist");
  const [synced, setSynced] = useState<number | null>(null);
  useEffect(() => {
    let live = true;
    syncShortlistAction(saved.get("shortlist"))
      .then((merged) => {
        if (live && merged) {
          saved.set("shortlist", merged);
          setSynced(merged.length);
        }
      })
      .catch(() => undefined);
    return () => {
      live = false;
    };
  }, []);
  if (!showSummary) return null;
  const n = synced ?? ids.length;
  return (
    <p className="text-muted text-sm">
      {n === 0 ? (
        <>Nothing saved yet. Tap the heart on any programme in the <Link href="/programmes" className="text-accent underline underline-offset-4">programme finder</Link>.</>
      ) : (
        <>
          {n} saved {n === 1 ? "programme" : "programmes"}, synced to your account.{" "}
          <Link href="/shortlist" className="text-accent underline underline-offset-4">Open your shortlist</Link>
        </>
      )}
    </p>
  );
}

function Result({ s }: { s: AccountActionState }) {
  if (!s) return null;
  return (
    <p role={s.error ? "alert" : "status"} className={s.error ? "text-danger text-sm" : "text-success text-sm"}>
      {s.error ?? s.ok}
    </p>
  );
}

export function ConsentControls({ marketing, contact }: { marketing: boolean; contact: boolean }) {
  const [state, action, pending] = useActionState(withdrawConsentAction, null);
  return (
    <form action={action} className="grid gap-3">
      <div className="flex flex-wrap gap-2">
        {marketing ? (
          <button name="purpose" value="marketing" disabled={pending} className="border-border hover:bg-surface-hover h-10 rounded-full border px-4 text-sm font-medium">
            Stop programme updates
          </button>
        ) : null}
        {contact ? (
          <button name="purpose" value="contact" disabled={pending} className="border-border hover:bg-surface-hover h-10 rounded-full border px-4 text-sm font-medium">
            Withdraw consent to be contacted
          </button>
        ) : null}
      </div>
      <Result s={state} />
    </form>
  );
}

export function PrivacyRequests() {
  const [state, action, pending] = useActionState(deletionRequestAction, null);
  return (
    <form action={action} className="grid gap-3">
      <div className="flex flex-wrap gap-2">
        <button name="kind" value="export" disabled={pending} className="border-border hover:bg-surface-hover h-10 rounded-full border px-4 text-sm font-medium">
          Email me a copy of my data
        </button>
        <button name="kind" value="opt_out" disabled={pending} className="border-border hover:bg-surface-hover h-10 rounded-full border px-4 text-sm font-medium">
          Opt out of all contact
        </button>
        <button name="kind" value="delete" disabled={pending} className="border-danger text-danger hover:bg-surface-hover h-10 rounded-full border px-4 text-sm font-medium">
          Delete my data
        </button>
      </div>
      <Result s={state} />
    </form>
  );
}
