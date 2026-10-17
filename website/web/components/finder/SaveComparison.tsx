"use client";

import Link from "next/link";
import { useState } from "react";
import { Bookmark } from "lucide-react";
import { saveComparisonAction } from "@/app/actions/account";

/** Saves the current comparison to the student's account (spec 12 "saved comparisons"). */
export function SaveComparison({ ids }: { ids: number[] }) {
  const [state, setState] = useState<"idle" | "busy" | "saved" | "signin">("idle");
  const [message, setMessage] = useState<string | null>(null);
  if (state === "signin")
    return (
      <p className="text-muted text-sm" role="status">
        <Link href={`/account/sign-in?next=${encodeURIComponent(`/compare?ids=${ids.join(",")}`)}`} className="text-accent underline underline-offset-4">
          Sign in
        </Link>{" "}
        to save this comparison.
      </p>
    );
  return (
    <div className="flex items-center gap-3">
      <button
        type="button"
        disabled={state === "busy" || state === "saved"}
        onClick={async () => {
          setState("busy");
          const r = await saveComparisonAction(ids);
          if (r.ok) setState("saved");
          else if (r.message?.startsWith("Sign in")) setState("signin");
          else {
            setMessage(r.message ?? "Couldn't save.");
            setState("idle");
          }
        }}
        className="border-border hover:bg-surface-hover inline-flex h-10 items-center gap-2 rounded-full border px-4 text-sm font-medium disabled:opacity-70"
      >
        <Bookmark className="size-4" aria-hidden fill={state === "saved" ? "currentColor" : "none"} />
        {state === "saved" ? "Saved to your account" : "Save comparison"}
      </button>
      {message ? <span role="alert" className="text-danger text-sm">{message}</span> : null}
    </div>
  );
}
