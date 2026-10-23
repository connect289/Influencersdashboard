import { type Metadata } from "next";
import { RevokeDevicesButton, UserForm } from "@/components/settings/admin-forms.tsx";
import { Badge, StatusBadge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { PageHeader } from "@/components/ui/state.tsx";
import { ago, ist } from "@/lib/format.ts";
import { ui } from "@/lib/ui/api.ts";
import { usersSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Users" };

export default async function UsersPage() {
  let data;
  try {
    data = await ui("ui_users", usersSchema);
  } catch (e) {
    return <PageError error={e} />;
  }
  return (
    <>
      <PageHeader
        title="Users and roles"
        description="Owners do everything; engineers do everything except approve proposals that touch money or allocation, change alert recipients, fixes, privacy or users. A person must already have a Supabase account (created with the CRM owner's agreement, runbook S-21)."
      />
      <Card>
        <CardHeader title="Add a person" />
        <CardBody>
          <UserForm />
        </CardBody>
      </Card>
      <Card>
        <CardHeader title="People" />
        <ul className="divide-y divide-border">
          {data.users.map((u) => (
            <li key={u.user_id} className="grid gap-2 px-4 py-3">
              <span className="flex flex-wrap items-center gap-2 text-sm">
                <Badge>{u.role}</Badge>
                {u.is_active ? null : <Badge tone="off">inactive</Badge>}
                <span className="text-fg-muted">
                  last sign-in {ago(u.last_sign_in)} · {u.devices} trusted browser{u.devices === 1 ? "" : "s"}
                </span>
              </span>
              <UserForm email={u.email} role={u.role} active={u.is_active} />
              <RevokeDevicesButton userId={u.user_id} />
            </li>
          ))}
        </ul>
      </Card>
      <Card>
        <CardHeader title="Recent sign-ins" />
        <ul className="divide-y divide-border text-sm">
          {data.sign_ins.map((s, n) => (
            <li key={n} className="flex flex-wrap items-center gap-2 px-4 py-2">
              <StatusBadge status={s.outcome === "success" ? "ok" : s.outcome} />
              <span>{s.email ?? "unknown"}</span>
              <span className="text-xs text-fg-muted">
                {s.method} · {ist(s.at)}
              </span>
            </li>
          ))}
        </ul>
      </Card>
    </>
  );
}
