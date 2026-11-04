import { type Metadata } from "next";
import { AcceptBaselineButton, AckPrivilegeButton } from "@/components/settings/admin-forms.tsx";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { ist } from "@/lib/format.ts";
import { requireUser } from "@/lib/session.ts";
import { ui } from "@/lib/ui/api.ts";
import { privilegesSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Privileges" };

const baselineText: Record<string, string> = {
  lead_intake_md5: "public.lead_intake()'s source (PLAT-08)",
  student_leads_columns: "student_leads' columns (INT-06)",
  security_definer_views: "views the API roles read with their owner's rights (PLAT-06)",
};

export default async function PrivilegesPage() {
  const me = await requireUser("/settings/privileges");
  let data;
  try {
    data = await ui("ui_privileges", privilegesSchema);
  } catch (e) {
    return <PageError error={e} />;
  }
  const open = data.functions.filter((f) => !f.acknowledged);
  return (
    <>
      <PageHeader
        title="Privileges and baselines"
        description="SECURITY DEFINER functions the API roles can execute (PLAT-07), the baselines the integrity checks compare against, and the Vault secret names Eduwit One can see (names only)."
      />
      <Card>
        <CardHeader
          title={`To acknowledge (${open.length})`}
          description={
            me.role === "owner"
              ? "New since the baseline: read what each does before acknowledging."
              : "New since the baseline. The owner reads what each does and acknowledges it (D-110)."
          }
        />
        {open.length === 0 ? (
          <Empty title="Nothing new" />
        ) : (
          <ul className="divide-y divide-border text-sm">
            {open.map((f) => (
              <li key={f.fn} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2">
                <span>
                  <code className="text-xs">{f.fn}</code> <span className="text-fg-muted">→ {f.roles.join(", ")}</span>
                </span>
                {me.role === "owner" ? <AckPrivilegeButton fn={f.fn} /> : null}
              </li>
            ))}
          </ul>
        )}
      </Card>
      <Card>
        <CardHeader title="Baselines" />
        {data.baselines.length === 0 ? (
          <Empty title="Not captured yet">The nightly run captures them.</Empty>
        ) : (
          <ul className="divide-y divide-border text-sm">
            {data.baselines.map((b) => (
              <li key={b.key} className="flex flex-wrap items-center justify-between gap-2 px-4 py-2">
                <span>
                  {baselineText[b.key] ?? b.key}
                  <span className="block text-xs text-fg-muted">
                    captured {ist(b.captured_at)}
                    {b.acknowledged_by ? ` · accepted by ${b.acknowledged_by}` : ""}
                  </span>
                </span>
                {me.role === "owner" && baselineText[b.key] ? <AcceptBaselineButton name={b.key} /> : null}
              </li>
            ))}
          </ul>
        )}
      </Card>
      <Card>
        <CardHeader title="Vault secret names" description="Values are never shown." />
        <CardBody className="flex flex-wrap gap-2">
          {data.vault.length ? (
            data.vault.map((v) => <Badge key={v}>{v}</Badge>)
          ) : (
            <span className="text-sm text-fg-muted">None visible.</span>
          )}
        </CardBody>
      </Card>
      <Card>
        <CardHeader title={`Acknowledged (${data.functions.length - open.length})`} />
        <details className="px-4 py-3 text-sm">
          <summary className="cursor-pointer">Show</summary>
          <ul className="mt-2 grid gap-1">
            {data.functions
              .filter((f) => f.acknowledged)
              .map((f) => (
                <li key={f.fn}>
                  <code className="text-xs">{f.fn}</code>{" "}
                  <span className="text-fg-muted">
                    → {f.roles.join(", ")} · {f.acknowledged_by}
                  </span>
                </li>
              ))}
          </ul>
        </details>
      </Card>
    </>
  );
}
