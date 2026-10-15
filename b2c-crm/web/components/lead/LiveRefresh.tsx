"use client";
import { useCallback, useEffect, useRef, useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { RefreshCw } from "lucide-react";
import { time } from "@/lib/format";

/**
 * Live updates (spec B10.1): the page's data is fetched again every minute while the tab is visible, and on return to
 * the tab. Skipped while rows are ticked or a sheet is open, so nothing the person is doing changes under them.
 */
export function LiveRefresh({ every = 60 }: { every?: number }) {
  const router = useRouter();
  const [busy, start] = useTransition();
  const [at, setAt] = useState<string | null>(null);
  const last = useRef(0);
  const refresh = useCallback((force = false) => {
    if (!force && (document.visibilityState !== "visible" || document.querySelector('input[name="lead"]:checked, .scrim'))) return;
    last.current = Date.now();
    start(() => router.refresh());
    setAt(new Date().toISOString());
  }, [router]);
  useEffect(() => {
    last.current = Date.now();
    const t = setInterval(() => refresh(), every * 1000);
    const onVisible = () => { if (document.visibilityState === "visible" && Date.now() - last.current > every * 1000) refresh(); };
    document.addEventListener("visibilitychange", onVisible);
    return () => { clearInterval(t); document.removeEventListener("visibilitychange", onVisible); };
  }, [every, refresh]);
  return (
    <button type="button" className="btn quiet sm" onClick={() => refresh(true)} disabled={busy} title={at ? `Updated ${time(at)}` : "Updates every minute"}>
      <RefreshCw className="icon s" aria-hidden />{busy ? "Updating…" : "Refresh"}
    </button>
  );
}
