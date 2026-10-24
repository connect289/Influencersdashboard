import { type Metadata } from "next";
import Link from "next/link";
import { ActionRows } from "@/components/fixes/action-rows.tsx";
import { appNames } from "@/components/ui/labels.ts";
import { buttonClass } from "@/components/ui/button.tsx";
import { Card } from "@/components/ui/card.tsx";
import { Filters, FilterSelect } from "@/components/ui/filters.tsx";
import { Input } from "@/components/ui/field.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Empty, PageHeader } from "@/components/ui/state.tsx";
import { ui } from "@/lib/ui/api.ts";
import { actionsSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Actions" };

export default async function ActionsPage({
  searchParams,
}: {
  searchParams: Promise<{ fix?: string; app?: string; day?: string; before?: string }>;
}) {
  const p = await searchParams;
  const day = p.day && /^\d{4}-\d{2}-\d{2}$/.test(p.day) ? p.day : null;
  let data;
  try {
    data = await ui("ui_actions", actionsSchema, {
      p_fix: p.fix || null,
      p_app: p.app || null,
      p_day: day,
      p_limit: 100,
      p_before: p.before ? Number(p.before) : null,
    });
  } catch (e) {
    return <PageError error={e} />;
  }
  const fixIds = Object.keys(data.fixes).filter((k) => k.startsWith("FIX-"));
  return (
    <>
      <PageHeader
        title="Actions"
        description="Every auto-fix run and every approved execution, as it happens: dry runs, the row before and after each act, what was skipped and why, and whether it held. All fixes ship switched off and run as dry runs during the observation window."
      />
      <Filters reset="/actions">
        <FilterSelect
          name="fix"
          label="Fix"
          value={p.fix}
          options={[["", "Any"], ...fixIds.map((f): [string, string] => [f, f])]}
        />
        <FilterSelect name="app" label="App" value={p.app} options={[["", "Any"], ...Object.entries(appNames)]} />
        <label className="grid gap-1 text-xs text-fg-muted">
          Day (IST)
          <Input type="date" name="day" defaultValue={day ?? ""} className="min-h-9 py-1" />
        </label>
      </Filters>
      <Card>
        {data.rows.length === 0 ? (
          <Empty title="No actions">
            No fix has run{p.fix ? ` for ${p.fix}` : ""}. Fixes are off until switched on under Settings → Fixes.
          </Empty>
        ) : (
          <ActionRows rows={data.rows} showFix />
        )}
      </Card>
      {data.next_before ? (
        <div>
          <Link
            href={`/actions?${new URLSearchParams({ ...(p.fix ? { fix: p.fix } : {}), ...(p.app ? { app: p.app } : {}), ...(day ? { day } : {}), before: String(data.next_before) })}`}
            className={buttonClass("secondary")}
          >
            Older actions
          </Link>
        </div>
      ) : null}
    </>
  );
}
