"use client";
import { useRouter } from "next/navigation";
import { useEffect } from "react";
import { createClient } from "@/lib/supabase/browser";

/** Refreshes the page when the creator's lead feed changes (Realtime on the creator-safe projection only, S-6). */
export function RealtimeRefresh({ creatorId }: { creatorId: string }) {
  const router = useRouter();
  useEffect(() => {
    const supabase = createClient();
    let timer: ReturnType<typeof setTimeout> | null = null;
    const channel = supabase
      .channel(`leads:${creatorId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "inf",
          table: "creator_lead_feed",
          filter: `creator_id=eq.${creatorId}`,
        },
        () => {
          if (timer) clearTimeout(timer);
          timer = setTimeout(() => router.refresh(), 800);
        },
      )
      .subscribe();
    return () => {
      if (timer) clearTimeout(timer);
      void supabase.removeChannel(channel);
    };
  }, [creatorId, router]);
  return null;
}
