import {
  ArrowLeftRight,
  Bell, BookOpen, Building2, ChartColumn, FileText, GitMerge, IndianRupee, Inbox, LayoutDashboard, Plug, Radio,
  Route, Settings, Sparkles, Target, Users,
} from "lucide-react";

export type NavItem = {
  href: string;
  label: string;
  icon: React.ComponentType<{ className?: string }>;
  /** Two-key shortcut after "g", e.g. "l" for g l. */
  key?: string;
  /** What the screen will do, shown until it is built. */
  summary: string;
  phase?: 1 | 2 | 3 | 4;
  keywords?: string;
};

export type NavGroup = { label: string; items: NavItem[] };

export const NAV: NavGroup[] = [
  {
    label: "Overview",
    items: [
      { href: "/", label: "Command Center", icon: LayoutDashboard, key: "c", summary: "Live KPIs, routing flow, partner health and alerts.", keywords: "home dashboard kpi" },
    ],
  },
  {
    label: "Leads",
    items: [
      { href: "/leads", label: "Leads", icon: Users, key: "l", summary: "Every lead from every source: search, filter, the Witty chat, soft delete with a recycle bin, and export.", keywords: "students master table recycle bin export" },
      { href: "/pool", label: "Pre-routing pool", icon: Inbox, summary: "Leads with no destination yet, grouped by why they wait (still chatting, routing off, too old), with their age and where each will go.", keywords: "waiting not ready" },
      { href: "/intake", label: "Intake", icon: Plug, summary: "Sources (Witty, website agent, Meta, Google, the API, imports) with volume and errors, the Excel/CSV import wizard, per-form field mapping, manual entry and connections.", keywords: "import csv meta google" },
    ],
  },
  {
    label: "Partners",
    items: [
      { href: "/partners", label: "Partners", icon: Building2, key: "p", summary: "Every partner edtech with its CRM, duplicate handling, caps, SLAs, working hours, go-live checklist and live switch.", keywords: "edtech add partner live switch" },
      { href: "/programmes", label: "Programme Repository", icon: BookOpen, summary: "Each partner's programme file (Excel or CSV): versions, catalogue matching, review, change preview, publish and roll back, plus catalogue coverage.", keywords: "catalogue courses sheet excel upload" },
      { href: "/mapping", label: "Mapping studio", icon: GitMerge, summary: "Map every partner stage, field and picklist to Eduwit's model and back, with coverage gates, tests and the unmapped queue.", keywords: "stages fields" },
    ],
  },
  {
    label: "Routing",
    items: [
      { href: "/routing", label: "Routing", icon: Route, key: "r", summary: "Automatic routing switch, lead simulator, rules (to partners or B2C), commission rates, hand-off rules, engine settings, the review queue and the decision log.", keywords: "engine allocation rules simulate commission rates decisions b2c nurture paid junk mismatch" },
      { href: "/ai", label: "AI Optimiser", icon: Sparkles, key: "a", summary: "Claude's recommendations with evidence and simulated impact (approve, edit, reject, roll back), AI-steered against holdout, the run log with cost, and the per-lead model registry.", keywords: "claude ml model optimiser recommendations holdout uplift" },
    ],
  },
  {
    label: "Money",
    items: [
      { href: "/money", label: "Commission & Finance", icon: IndianRupee, key: "m", summary: "Enrollment verification, earnings ledger, GST invoices, receipts, statement reconciliation and tier watch.", keywords: "invoices earnings gst receipts tds statement" },
    ],
  },
  {
    label: "Outreach",
    items: [
      { href: "/notifications", label: "Notifications", icon: Bell, summary: "What students hear once a partner accepts their lead: WhatsApp and email switches, templates per language with a preview per partner, providers and the send log.", keywords: "whatsapp email templates" },
      { href: "/capi", label: "Conversions (CAPI)", icon: Target, summary: "Lead milestones reported back to Meta and Google: stage-to-event map, the event log, match quality and a per-lead check.", keywords: "meta google ads" },
    ],
  },
  {
    label: "Insights",
    items: [
      { href: "/dashboards", label: "Dashboards", icon: ChartColumn, key: "d", summary: "Nine built-in dashboards and a builder: KPIs, charts, funnels, Sankey, cohorts, leaderboards, the India map, SLA timers; every number drills down to its leads; calculated metrics, metric alerts and scheduled e-mail.", keywords: "analytics charts metrics alerts schedule kpi" },
      { href: "/reports", label: "Reports", icon: FileText, summary: "Tabular, summary and matrix reports; save, schedule and export CSV.", keywords: "export csv summary matrix" },
    ],
  },
  {
    label: "System",
    items: [
      { href: "/b2c", label: "B2C CRM link", icon: ArrowLeftRight, summary: "The B2C CRM's only way to Eduwit's lead data: real-time sync of the leads it holds, its writes back with the counsellor who made them, which fields it may change, and a per-lead inspector.", keywords: "b2c crm sync counsellors in-house api webhook" },
      { href: "/system", label: "System health", icon: Radio, summary: "Background jobs, webhook endpoints and deliveries, API keys, events from the B2C CRM and erasure requests.", keywords: "outbox queue api keys webhooks b2c jobs cron" },
      { href: "/settings/security", label: "Settings", icon: Settings, key: "s", summary: "Your sign-in security: two-step verification, active sessions and sign-in history.", keywords: "security sessions account" },
    ],
  },
];

export const NAV_ITEMS: NavItem[] = NAV.flatMap((g) => g.items);

/** Placeholder screens rendered by app/(app)/[section]: every top-level path with a phase. */
export const SECTION_BY_SLUG: Record<string, NavItem> = Object.fromEntries(
  NAV_ITEMS.filter((i) => i.phase && /^\/[a-z]+$/.test(i.href)).map((i) => [i.href.slice(1), i]),
);

export function isActive(pathname: string, href: string): boolean {
  if (href === "/") return pathname === "/";
  const base = href.split("/").slice(0, 2).join("/");
  return pathname === href || pathname.startsWith(base + "/") || pathname === base;
}
