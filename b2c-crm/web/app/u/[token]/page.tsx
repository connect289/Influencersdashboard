import type { Metadata } from "next";
import { adminClient } from "@/lib/supabase/admin";
import { decodeLink } from "@/lib/tokens";

export const metadata: Metadata = { title: "Unsubscribe", robots: { index: false } };
export const dynamic = "force-dynamic";

async function unsubscribe(form: FormData) {
  "use server";
  const l = decodeLink(String(form.get("token") ?? ""));
  if (!l || l.kind !== "unsubscribe") return;
  const all = form.get("what") === "all";
  await adminClient().rpc("opt_out", { p_lead: l.lead, p_channels: all ? null : ["email"], p_source: "unsubscribe_link", p_note: all ? "all channels" : "email" });
  const { redirect } = await import("next/navigation");
  redirect(`/thanks?unsubscribed=${all ? "all" : "email"}`);
}

/** The unsubscribe page (spec B9.6): no sign-in, a signed link per student; email only, or every message. */
export default async function UnsubscribePage({ params }: { params: Promise<{ token: string }> }) {
  const token = (await params).token;
  const l = decodeLink(token);
  return (
    <main className="auth">
      <div className="card">
        <h1>Unsubscribe</h1>
        {!l || l.kind !== "unsubscribe" ? (
          <p className="muted">This link is not valid. Reply STOP to any Eduwit message and we will stop at once.</p>
        ) : (
          <form action={unsubscribe} className="stack">
            <input type="hidden" name="token" value={token} />
            <p className="muted">Choose what Eduwit should stop sending you.</p>
            <button className="btn primary block" name="what" value="email" type="submit">Stop emails</button>
            <button className="btn ghost block" name="what" value="all" type="submit">Stop all messages (email and WhatsApp)</button>
          </form>
        )}
      </div>
    </main>
  );
}
