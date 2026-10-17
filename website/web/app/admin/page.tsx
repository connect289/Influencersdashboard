import { Suspense } from "react";
import { AdminShell, Card, Stat } from "@/components/admin/AdminShell";
import { requireAdmin } from "@/lib/server/admin";
import { rpc } from "@/lib/server/db";

export const metadata = { title: "Dashboard" };

interface Overview {
  leads_today: number;
  leads_7d: number;
  applications_7d: number;
  chats_7d: number;
  outbox_dead: number;
  outbox_pending: number;
  unmapped: number;
  needs_review: number;
  privacy_requests_open: number;
}

async function Dashboard({ searchParams }: { searchParams: Promise<{ denied?: string }> }) {
  const [s, sp] = await Promise.all([requireAdmin("viewer"), searchParams]);
  const o = await rpc<Overview>("web_admin_overview");
  return (
    <AdminShell session={s} title="Website admin">
      {sp.denied ? (
        <p role="alert" className="text-danger text-sm">
          Your role cannot open that page.
        </p>
      ) : null}
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-4">
        <Stat label="Verified leads today" value={o.leads_today} href="/admin/insights" />
        <Stat label="Verified leads, 7 days" value={o.leads_7d} href="/admin/insights" />
        <Stat label="Application requests, 7 days" value={o.applications_7d} href="/admin/insights" />
        <Stat label="Witty conversations, 7 days" value={o.chats_7d} href="/admin/insights" />
        <Stat label="Outbox: dead letters" value={o.outbox_dead} href="/admin/outbox?status=dead" />
        <Stat label="Outbox: pending" value={o.outbox_pending} href="/admin/outbox" />
        <Stat label="Offerings without a mapping" value={o.unmapped + o.needs_review} href="/admin/taxonomy" />
        <Stat label="Open privacy requests" value={o.privacy_requests_open} href="/admin/privacy" />
      </div>
      <Card title="What you can do here">
        <p className="text-muted text-sm">
          Edit content, curated finder views, SEO overrides and redirects; switch features on or off; map catalogue rows to the
          taxonomy; watch the lead funnels, Witty&apos;s answers and the outbox. Programme data (fees, approvals, eligibility) is
          managed in the shared catalogue, not here. Every change is recorded in the audit log.
        </p>
      </Card>
    </AdminShell>
  );
}

export default function AdminHome({ searchParams }: { searchParams: Promise<{ denied?: string }> }) {
  return (
    <Suspense fallback={<div className="skeleton m-8 h-24" />}>
      <Dashboard searchParams={searchParams} />
    </Suspense>
  );
}
