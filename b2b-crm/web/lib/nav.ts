import {
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
      { href: "/pool", label: "Pre-routing pool", icon: Inbox, phase: 1, summary: "Leads that cannot route yet, grouped by what is missing (consent, course, verified phone) with their age.", keywords: "waiting not ready" },
      { href: "/intake", label: "Intake", icon: Plug, phase: 2, summary: "Sources (Witty, website agent, Meta, Google, imports) with volume and errors, the Excel/CSV import wizard and per-form field mapping.", keywords: "import csv meta google" },
    ],
  },
  {
    label: "Partners",
    items: [
      { href: "/partners", label: "Partners", icon: Building2, key: "p", phase: 1, summary: "Every partner edtech with status, health and this month's net commission per lead. Caps, SLAs, working hours and the live switch.", keywords: "edtech" },
      { href: "/programmes", label: "Programme Repository", icon: BookOpen, phase: 1, summary: "Each partner's programme file (Excel or Google Sheet): versions, catalogue matching, change and routing-impact preview, publish and roll back, plus the coverage matrix.", keywords: "catalogue courses sheet" },
      { href: "/mapping", label: "Mapping studio", icon: GitMerge, phase: 2, summary: "Map every partner stage, field and picklist to Eduwit's model and back, with coverage gates, tests and the unmapped queue.", keywords: "stages fields" },
    ],
  },
  {
    label: "Routing",
    items: [
      { href: "/routing", label: "Routing", icon: Route, key: "r", phase: 1, summary: "Segment explorer, rules builder, decision log and versioned engine settings. Commission-first now; performance mode as data matures.", keywords: "engine allocation rules" },
      { href: "/ai", label: "AI Optimiser", icon: Sparkles, phase: 3, summary: "Claude's recommendations with evidence and simulated impact, the holdout comparison and the model registry.", keywords: "claude ml" },
    ],
  },
  {
    label: "Money",
    items: [
      { href: "/money", label: "Commission & Finance", icon: IndianRupee, key: "m", phase: 3, summary: "Enrollment verification, earnings ledger, GST invoices, receipts, statement reconciliation and tier watch.", keywords: "invoices earnings gst" },
    ],
  },
  {
    label: "Outreach",
    items: [
      { href: "/notifications", label: "Notifications", icon: Bell, phase: 1, summary: "WhatsApp and email templates per language with a live preview per partner, and the send log with delivery status.", keywords: "whatsapp email templates" },
      { href: "/capi", label: "Conversions (CAPI)", icon: Target, phase: 2, summary: "Stage-to-event map for Meta and Google, the event log and match quality.", keywords: "meta google ads" },
    ],
  },
  {
    label: "Insights",
    items: [
      { href: "/dashboards", label: "Dashboards", icon: ChartColumn, key: "d", phase: 4, summary: "Default dashboards and a builder: KPIs, funnels, Sankey, cohorts, leaderboards and alerts, all drilling down to leads.", keywords: "analytics charts" },
      { href: "/reports", label: "Reports", icon: FileText, phase: 4, summary: "Tabular, summary and matrix reports; save, schedule and export.", keywords: "export" },
    ],
  },
  {
    label: "System",
    items: [
      { href: "/system", label: "System health", icon: Radio, phase: 2, summary: "Queues, sync lag, outbox and dead letters, API keys and webhooks.", keywords: "outbox queue api keys" },
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
