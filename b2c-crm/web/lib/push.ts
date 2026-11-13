import "server-only";
import webpush from "web-push";
import { handBack, JobBudget, whileTime } from "@/lib/job-budget";
import { adminClient } from "@/lib/supabase/admin";

type Sub = { endpoint: string; keys: { p256dh: string; auth: string } };
type Item = { id: number; user_id: string; kind: string; title: string; body: string | null; link: string | null; subscriptions: Sub[] };

export function pushConfig(): { publicKey: string; privateKey: string; subject: string } | null {
  const publicKey = process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY;
  const privateKey = process.env.VAPID_PRIVATE_KEY;
  if (!publicKey || !privateKey) return null;
  return { publicKey, privateKey, subject: process.env.VAPID_SUBJECT ?? "mailto:connect@eduwit.in" };
}

/**
 * Every minute (with the urgent sync): new notifications to each of the person's devices. Gone devices are dropped.
 * When the job's time is up (lib/job-budget.ts) the notifications not started are handed back for the next run.
 */
export async function runPush(budget: JobBudget = new JobBudget()): Promise<{ pushed: number; failed: number; gone: number; released?: number }> {
  const out: { pushed: number; failed: number; gone: number; released?: number } = { pushed: 0, failed: 0, gone: 0 };
  const cfg = pushConfig();
  if (!cfg) return out;
  const db = adminClient();
  const { data, error } = await db.rpc("push_take", { p_limit: 200 });
  if (error) throw new Error(`push_take: ${error.message}`);
  const unstarted = await whileTime(budget, (data ?? []) as Item[], async (n) => {
    const link = n.link && n.link.startsWith("/") && !n.link.startsWith("//") ? n.link : "/";
    const payload = JSON.stringify({ title: n.title.slice(0, 120), body: (n.body ?? "").slice(0, 300), link, tag: `${n.kind}-${n.id}` });
    for (const s of n.subscriptions ?? []) {
      try {
        await webpush.sendNotification(s, payload, { vapidDetails: cfg, TTL: 3600, urgency: n.kind === "reminder" ? "high" : "normal", timeout: 10_000 });
        out.pushed++;
      } catch (e) {
        const status = (e as { statusCode?: number }).statusCode;
        if (status === 404 || status === 410) {
          out.gone++;
          await db.rpc("push_gone", { p_user: n.user_id, p_endpoint: s.endpoint });
        } else out.failed++;
      }
    }
  });
  const released = await handBack(db, budget, "push", "push", unstarted.map((n) => n.id));
  if (released) out.released = released;
  return out;
}
