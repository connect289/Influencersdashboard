import { CommandPalette } from "@/components/shell/CommandPalette";
import { BottomNav, SideNav, type NavItem } from "@/components/shell/Nav";
import { UserBox } from "@/components/shell/UserBox";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { ROLE_LABEL } from "@/lib/labels";

type Counts = { not_worked: number; overdue: number; unread_alerts: number; unread_inbox: number };

/** The Sales app (spec B15): phone first, a sidebar on a laptop. Counsellors, the sales head and the Admin. */
export default async function SalesLayout({ children }: { children: React.ReactNode }) {
  const me = await requireUser("sales", "/s");
  const c = await rpc<Counts>("nav_counts").catch(() => ({ not_worked: 0, overdue: 0, unread_alerts: 0, unread_inbox: 0 }));
  const urgent = (c.not_worked ?? 0) + (c.overdue ?? 0);
  const items: NavItem[] = [
    { href: "/s", label: "Today", icon: "home", phone: true, count: c.unread_alerts || undefined },
    { href: "/s/leads", label: "Leads", icon: "leads", phone: true },
    { href: "/s/followups", label: "Follow-ups", icon: "followups", phone: true, count: urgent || undefined },
    { href: "/s/inbox", label: "Inbox", icon: "inbox", phone: true, count: c.unread_inbox || undefined },
    { href: "/s/pipeline", label: "Pipeline", icon: "pipeline" },
    { href: "/s/programmes", label: "Programmes", icon: "programmes", group: "More" },
    { href: "/s/money", label: "My money", icon: "money", group: "More" },
    { href: "/s/analytics", label: "Analytics", icon: "analytics", group: "More" },
    ...(me.role === "sales_head" || me.role === "admin" ? [{ href: "/s/team", label: "My team", icon: "team", group: "More" } as NavItem] : []),
    { href: "/s/me", label: "Me", icon: "me", phone: true, group: "You" },
    { href: "/s/alerts", label: "Alerts", icon: "alerts", group: "You", count: c.unread_alerts || undefined },
    { href: "/s/support", label: "Support", icon: "support", group: "You" },
    ...(me.role === "admin" ? [{ href: "/w", label: "Workspace", icon: "switch", group: "You" } as NavItem] : []),
  ];
  const pages = items.map((i) => ({ href: i.href, label: i.label }));
  return (
    <div className="desk-shell">
      <SideNav items={items} root="/s" product="Sales" tools={<CommandPalette pages={pages} base="/s" />}
        who={<UserBox name={me.full_name} email={me.email} role={ROLE_LABEL[me.role ?? ""] ?? ""} />} />
      <div className="main" style={{ minHeight: "100dvh", display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, minWidth: 0 }}>{children}</div>
        <BottomNav items={items} root="/s" />
      </div>
    </div>
  );
}
