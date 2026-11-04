"use client";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { IconRefresh } from "@/components/icons.tsx";

/**
 * Live pages by polling (D-060): the page's server data is fetched again while the tab is visible.
 * Realtime would need schema one's tables in the shared supabase_realtime publication and read policies for the API
 * roles, both of which the RPC-only design rules out.
 *  - Pages that run the apps' own aggregates (Apps, Marketing, Analytics) refresh every 5 minutes, not every 15 s, so
 *    an open tab does not keep heavy reads running on the shared database.
 *  - Polling stops once nobody has touched the page for the idle limit, so a console left open still signs out
 *    (the refresh would otherwise keep the session's last-seen time fresh).
 *  - A tick is skipped while a form's action is pending (ActionForm sets aria-busy) or right after a click or key: a
 *    refresh that lands during a server action can leave the form waiting for an answer that never comes.
 */
export function LiveRefresh({ idleSeconds }: { idleSeconds: number }) {
  const router = useRouter();
  const path = usePathname();
  const heavy = /^\/(apps|marketing|analytics)(\/|$)/.test(path);
  const seconds = heavy ? 300 : 15;
  const lastTouch = useRef(Date.now());
  const [at, setAt] = useState<Date | null>(null);
  const [paused, setPaused] = useState(false);

  useEffect(() => {
    const touch = () => {
      lastTouch.current = Date.now();
      setPaused(false);
    };
    const events = ["pointerdown", "keydown", "wheel", "touchstart"] as const;
    for (const e of events) window.addEventListener(e, touch, { passive: true });
    return () => {
      for (const e of events) window.removeEventListener(e, touch);
    };
  }, []);

  useEffect(() => {
    setAt(new Date());
    const timer = setInterval(() => {
      if (Date.now() - lastTouch.current > idleSeconds * 1000) {
        setPaused(true);
        return;
      }
      const busy = document.querySelector('form[aria-busy="true"]') !== null;
      if (busy || Date.now() - lastTouch.current < 5000) return;
      if (document.visibilityState === "visible") {
        router.refresh();
        setAt(new Date());
      }
    }, seconds * 1000);
    return () => clearInterval(timer);
  }, [router, seconds, idleSeconds]);

  return (
    <span className="inline-flex items-center gap-1 text-xs text-fg-muted" aria-live="off">
      <IconRefresh size={12} />
      {paused
        ? "Paused: no activity. Click anywhere to resume."
        : `Live, every ${heavy ? "5 min" : `${seconds} s`}${at ? ` · ${at.toLocaleTimeString("en-IN", { hour: "numeric", minute: "2-digit", second: "2-digit" })}` : ""}`}
    </span>
  );
}
