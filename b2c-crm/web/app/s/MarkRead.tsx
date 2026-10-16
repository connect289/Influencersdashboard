"use client";
import { useTransition } from "react";
import { useRouter } from "next/navigation";
import { notificationsRead } from "./actions";

export function MarkRead() {
  const router = useRouter();
  const [busy, start] = useTransition();
  return (
    <button type="button" className="btn quiet sm" disabled={busy} onClick={() => start(async () => { await notificationsRead(); router.refresh(); })}>
      Mark all read
    </button>
  );
}
