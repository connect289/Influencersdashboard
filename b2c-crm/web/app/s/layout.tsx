import { BottomNav, SideNav, type NavItem } from "@/components/shell/Nav";
import { UserBox } from "@/components/shell/UserBox";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import { ROLE_LABEL } from "@/lib/labels";

/** The Sales app (spec B4): phone first, a sidebar on a desktop. Counsellors, the sales head and the Admin. */
export default async function SalesLayout({ children }: { children: React.ReactNode }) {
  const me = await requireUser("sales", "/s");
  const [counts, unread] = await Promise.all([
    rpc<{ not_worked: number; overdue: number }>("followup_counts", { p_user: me.user_id }).catch(() => ({ not_worked: 0, overdue: 0 })),
    rpc<{ unread: number }>("notifications_mine", { p_limit: 1 }).catch(() => ({ unread: 0 })),
  ]);
  const urgent = (counts.not_worked ?? 0) + (counts.overdue ?? 0);
  const items: NavItem[] = [
    { href: "/s", label: "Today", icon: "home", phone: true, count: unread.unread || undefined },
    { href: "/s/leads", label: "Leads", icon: "leads", phone: true },
    { href: "/s/pipeline", label: "Pipeline", icon: "pipeline" },
    { href: "/s/followups", label: "Follow-ups", icon: "followups", phone: true, count: urgent || undefined },
    { href: "/s/inbox", label: "Inbox", icon: "inbox", phone: true },
    { href: "/s/programmes", label: "Programmes", icon: "programmes" },
    { href: "/s/money", label: "My money", icon: "money" },
    { href: "/s/analytics", label: "Analytics", icon: "analytics" },
    ...(me.role === "sales_head" || me.role === "admin" ? [{ href: "/s/team", label: "My team", icon: "team" } as NavItem] : []),
    { href: "/s/me", label: "Me", icon: "me", phone: true },
  ];
  return (
    <div className="desk-shell">
      <SideNav items={items} root="/s" who={<UserBox name={me.full_name} email={me.email} role={ROLE_LABEL[me.role ?? ""] ?? ""} />} />
      <div className="main" style={{ minHeight: "100dvh", display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, minWidth: 0 }}>{children}</div>
        <BottomNav items={items} root="/s" />
      </div>
    </div>
  );
}
