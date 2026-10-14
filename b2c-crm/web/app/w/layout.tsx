import { BottomNav, SideNav, type NavItem } from "@/components/shell/Nav";
import { UserBox } from "@/components/shell/UserBox";
import { requireUser } from "@/lib/auth";
import { ROLE_LABEL } from "@/lib/labels";

/** The workspace (spec B12–B14): the Admin's console; Marketing reads it in Phase 1 (its own tools come in Phase 2). */
export default async function WorkspaceLayout({ children }: { children: React.ReactNode }) {
  const me = await requireUser("workspace", "/w");
  const admin = me.role === "admin";
  const items: NavItem[] = [
    { href: "/w", label: "Home", icon: "dashboard", phone: true },
    { href: "/w/leads", label: "Leads", icon: "leads", group: "Sales", phone: true },
    { href: "/w/pipeline", label: "Pipeline", icon: "pipeline", group: "Sales" },
    { href: "/w/allocation", label: "Lead Allocation", icon: "allocation", group: "Sales", phone: admin },
    { href: "/w/teams", label: "Teams", icon: "teams", group: "Sales" },
    { href: "/w/enrollments", label: "Enrolments", icon: "enrollments", group: "Sales", phone: true },
    ...(admin || me.role === "marketing" ? [
      { href: "/w/nurture", label: "Nurture", icon: "nurture", group: "Marketing", phone: me.role === "marketing" } as NavItem,
      { href: "/w/templates", label: "Templates", icon: "templates", group: "Marketing" } as NavItem,
    ] : []),
    { href: "/w/connectors", label: "Connectors", icon: "connectors", group: "Company" },
    ...(admin ? [{ href: "/w/settings", label: "Settings", icon: "settings", group: "Company" } as NavItem] : []),
    { href: "/w/guide", label: "Guide", icon: "guide", group: "Company", phone: true },
  ];
  return (
    <div className="desk-shell">
      <SideNav items={items} root="/w" who={<UserBox name={me.full_name} email={me.email} role={ROLE_LABEL[me.role ?? ""] ?? ""} />} />
      <div className="main" style={{ minHeight: "100dvh", display: "flex", flexDirection: "column" }}>
        <div style={{ flex: 1, minWidth: 0 }}>{children}</div>
        <BottomNav items={items} root="/w" />
      </div>
    </div>
  );
}
