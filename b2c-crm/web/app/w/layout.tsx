import { CommandPalette } from "@/components/shell/CommandPalette";
import { BottomNav, SideNav, type NavItem } from "@/components/shell/Nav";
import { UserBox } from "@/components/shell/UserBox";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { ROLE_LABEL } from "@/lib/labels";

type Counts = { unread_inbox: number };

/** The workspace (spec B15): the Admin's console; Marketing sees the same shell with its own tools. */
export default async function WorkspaceLayout({ children }: { children: React.ReactNode }) {
  const me = await requireUser("workspace", "/w");
  const admin = me.role === "admin";
  const c = await rpc<Counts>("nav_counts").catch(() => ({ unread_inbox: 0 }));
  const items: NavItem[] = [
    { href: "/w", label: "Home", icon: "dashboard", phone: true },
    { href: "/w/leads", label: "Leads", icon: "leads", group: "Sales", phone: true },
    { href: "/w/pipeline", label: "Pipeline", icon: "pipeline", group: "Sales" },
    { href: "/w/inbox", label: "Inbox", icon: "inbox", group: "Sales" },
    { href: "/w/allocation", label: "Lead Allocation", icon: "allocation", group: "Sales", phone: admin },
    { href: "/w/teams", label: "Teams", icon: "teams", group: "Sales" },
    { href: "/w/enrollments", label: "Enrolments", icon: "enrollments", group: "Sales", phone: true },
    { href: "/w/team", label: "Team performance", icon: "team", group: "Sales" },
    ...(admin || me.role === "marketing" ? [
      { href: "/w/nurture", label: "Nurture", icon: "nurture", group: "Marketing", phone: me.role === "marketing", count: c.unread_inbox || undefined } as NavItem,
      { href: "/w/templates", label: "Templates", icon: "templates", group: "Marketing" } as NavItem,
      { href: "/w/programmes", label: "Programmes", icon: "programmes", group: "Marketing" } as NavItem,
    ] : []),
    { href: "/w/analytics", label: "Analytics", icon: "analytics", group: "Numbers" },
    { href: "/w/money", label: "Money", icon: "money", group: "Numbers" },
    { href: "/w/connectors", label: "Connectors", icon: "connectors", group: "Company" },
    ...(admin ? [{ href: "/w/settings", label: "Settings", icon: "settings", group: "Company" } as NavItem] : []),
    { href: "/w/guide", label: "Guide", icon: "guide", group: "Company", phone: true },
    { href: "/w/support", label: "Support", icon: "support", group: "Company" },
    ...(admin ? [{ href: "/s", label: "Sales app", icon: "switch", group: "Company" } as NavItem] : []),
  ];
  const pages = [
    ...items.map((i) => ({ href: i.href, label: i.label })),
    { href: "/w/allocation?tab=rules", label: "Allocation rules", hint: "Lead Allocation" }, { href: "/w/allocation?tab=queues", label: "Unassigned queue", hint: "Lead Allocation" },
    { href: "/w/allocation?tab=calendar", label: "Hours and leave", hint: "Lead Allocation" }, { href: "/w/nurture?tab=pool", label: "Nurture pool", hint: "Nurture" },
    { href: "/w/nurture?tab=journeys", label: "Journeys", hint: "Nurture" }, { href: "/w/nurture?tab=campaigns", label: "Campaigns", hint: "Nurture" },
    { href: "/w/nurture?tab=replies", label: "Replies", hint: "Nurture" }, { href: "/w/money?tab=commission", label: "Counsellor commission", hint: "Money" },
    { href: "/w/money?tab=universities", label: "Universities", hint: "Money" }, { href: "/w/money?tab=ads", label: "Ad spend", hint: "Money" },
    { href: "/w/teams", label: "Phone numbers", hint: "Teams" }, { href: "/w/leads/duplicates", label: "Duplicate suspects", hint: "Leads" },
    ...(admin ? [{ href: "/w/qualify", label: "To qualify", hint: "Leads" }, { href: "/w/leads/flagged", label: "Flagged leads", hint: "Leads" },
      { href: "/w/leads?exports=1", label: "Exports", hint: "Leads" }, { href: "/w/leads?deleted=1", label: "Background jobs", hint: "Leads" }] : []),
    { href: "/w/allocation?tab=capacity", label: "Capacity", hint: "Lead Allocation" },
    ...(admin ? [{ href: "/w/settings?tab=stages", label: "Stages and sub-stages", hint: "Settings" }, { href: "/w/settings?tab=checklists", label: "Document checklists", hint: "Settings" },
      { href: "/w/settings?tab=fields", label: "Custom fields", hint: "Settings" }, { href: "/w/settings?tab=sla", label: "SLA by source", hint: "Settings" }] : []),
    ...(admin ? [{ href: "/w/settings?tab=health", label: "System health", hint: "Settings" }, { href: "/w/settings?tab=audit", label: "Audit log", hint: "Settings" }, { href: "/w/settings?tab=signins", label: "Sign-ins", hint: "Settings" }] : []),
  ];
  return (
    <div className="desk-shell">
      <SideNav items={items} root="/w" product={admin ? "Admin" : "Marketing"} tools={<CommandPalette pages={pages} base="/w" />}
        who={<UserBox name={me.full_name} email={me.email} role={ROLE_LABEL[me.role ?? ""] ?? ""} />} />
      <div className="main" style={{ minHeight: "100dvh", display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, minWidth: 0 }}>{children}</div>
        <BottomNav items={items} root="/w" />
      </div>
    </div>
  );
}
