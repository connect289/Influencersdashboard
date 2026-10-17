"use client";
import { Bell } from "lucide-react";
import { useTranslations } from "next-intl";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { fetchUnreadCounts } from "@/lib/messaging/client";
import { createClient } from "@/lib/supabase/browser";

/** Fallback check while the tab is visible, in case the Realtime connection drops. */
const POLL_MS = 5 * 60_000;
/** Fired by screens that mark notifications read, so the bell re-reads its count at once. */
export const NOTIFICATIONS_CHANGED = "inf:notifications-changed";

/**
 * The header bell: unread count, updated live through Realtime on the person's own notifications (RLS limits the
 * stream to their rows), re-checked on navigation, when the tab comes back and every few minutes. Opens the centre.
 */
export function NotificationBell({ href, userId, initial }: { href: string; userId: string; initial: number }) {
  const t = useTranslations();
  const [count, setCount] = useState(initial);
  const pathname = usePathname();

  // A server refresh (e.g. after "Mark all read") brings a new count from the layout.
  const [seen, setSeen] = useState(initial);
  if (seen !== initial) {
    setSeen(initial);
    setCount(initial);
  }

  useEffect(() => {
    let alive = true;
    const check = () => {
      if (document.visibilityState !== "visible") return;
      void fetchUnreadCounts().then((c) => {
        if (alive && c) setCount(c.notifications);
      });
    };
    check();
    const id = window.setInterval(check, POLL_MS);
    document.addEventListener("visibilitychange", check);
    window.addEventListener(NOTIFICATIONS_CHANGED, check);
    return () => {
      alive = false;
      window.clearInterval(id);
      document.removeEventListener("visibilitychange", check);
      window.removeEventListener(NOTIFICATIONS_CHANGED, check);
    };
  }, [pathname]);

  useEffect(() => {
    const supabase = createClient();
    let timer: ReturnType<typeof setTimeout> | null = null;
    const channel = supabase
      .channel(`notifications:${userId}`)
      .on(
        "postgres_changes",
        { event: "*", schema: "inf", table: "notifications", filter: `user_id=eq.${userId}` },
        () => {
          if (timer) clearTimeout(timer);
          timer = setTimeout(() => {
            void fetchUnreadCounts().then((c) => c && setCount(c.notifications));
          }, 500);
        },
      )
      .subscribe();
    return () => {
      if (timer) clearTimeout(timer);
      void supabase.removeChannel(channel);
    };
  }, [userId]);

  const shown = count > 99 ? "99+" : String(count);
  return (
    <Link
      href={href}
      className="relative inline-flex size-10 items-center justify-center rounded-xl text-muted hover:bg-surface-2 hover:text-ink"
      aria-label={count > 0 ? t("notifications.bellUnread", { count }) : t("notifications.bell")}
    >
      <Bell className="size-5" aria-hidden />
      {count > 0 ? (
        <span
          aria-hidden
          className="absolute top-1 right-1 min-w-[18px] rounded-full bg-danger px-1 text-center text-[11px] leading-[18px] font-semibold text-white"
        >
          {shown}
        </span>
      ) : null}
    </Link>
  );
}
