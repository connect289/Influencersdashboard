import { type Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";
import { SettingEditor } from "@/components/settings/setting-editor.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Banner, Code, PageHeader } from "@/components/ui/state.tsx";
import { ago, ist, json } from "@/lib/format.ts";
import { requireUser } from "@/lib/session.ts";
import { ui } from "@/lib/ui/api.ts";
import { settingsSchema, versionsSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Setting" };

const about: Record<string, { title: string; text: string }> = {
  alerts: {
    title: "Alert routing",
    text: "Recipients (p1.email, escalation.second_contact, developer_email, email_from) are the owner's to change; timing, the digest hour and storm limits are anyone's.",
  },
  ai: { title: "AI models", text: "provider and models per tier, routing per task kind, daily caps in rupees." },
  events: {
    title: "Privacy (PII)",
    text: 'pii_columns: key patterns ("*" is a wildcard) removed from every copied event, alert and AI input. It cannot be emptied.',
  },
  test_identities: {
    title: "Test identities",
    text: "The identities the synthetic tests use; a test runs only on these (spec §17.9).",
  },
  hosts: { title: "Hosts", text: "The apps' addresses: probes, health checks and deep links read them each minute." },
  access: { title: "Sign-in", text: "owners (seeded on install), trusted_days, idle_hours, code_minutes." },
  thresholds: {
    title: "Thresholds",
    text: "The numbers the SQL checks compare against, by name (docs/CHECKS.md lists which check reads which).",
  },
};

export default async function SettingPage({
  params,
  searchParams,
}: {
  params: Promise<{ key: string }>;
  searchParams: Promise<{ from?: string }>;
}) {
  const key = (await params).key;
  const from = Number((await searchParams).from);
  if (!/^[a-z_]{2,40}$/.test(key)) notFound();
  const me = await requireUser(`/settings/${key}`);
  let all;
  let versions;
  try {
    [all, versions] = await Promise.all([
      ui("ui_settings", settingsSchema),
      ui("ui_setting_versions", versionsSchema, { p_key: key, p_limit: 20 }),
    ]);
  } catch (e) {
    return <PageError error={e} />;
  }
  const s = all[key];
  if (!s) notFound();
  const info = about[key] ?? { title: key, text: "A setting read by Eduwit One at runtime." };
  // Restoring is saving an earlier version's value again, as a new version with its own reason.
  const restoring = versions.find((v) => v.version === from && v.version !== s.version);
  return (
    <>
      <PageHeader
        title={info.title}
        description={`${info.text} Version ${s.version}, changed ${ago(s.updated_at)} by ${s.actor}.`}
      />
      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardBody>
            {restoring ? (
              <div className="mb-3">
                <Banner tone="p3">
                  The editor holds version {restoring.version}. Saving makes it version {s.version + 1}; give the
                  reason.{" "}
                  <Link href={`/settings/${key}`} className="underline">
                    Back to the current value
                  </Link>
                </Banner>
              </div>
            ) : null}
            <SettingEditor
              key={restoring ? `v${restoring.version}` : "current"}
              name={key}
              value={JSON.stringify(restoring ? restoring.value : s.value, null, 2)}
              readOnly={s.owner_only && me.role !== "owner"}
            />
          </CardBody>
        </Card>
        <Card>
          <CardHeader title="Versions" description="Newest first; each with who changed it and why." />
          <ul className="divide-y divide-border text-sm">
            {versions.map((v) => (
              <li key={v.version} className="grid gap-1 px-4 py-2">
                <span className="font-medium">
                  v{v.version} · {v.actor}
                </span>
                <span className="text-xs text-fg-muted">
                  {ist(v.at)}
                  {v.reason ? ` · ${v.reason}` : ""}
                </span>
                <details>
                  <summary className="cursor-pointer text-xs">value</summary>
                  <Code className="mt-1">{json(v.value)}</Code>
                </details>
                {v.version !== s.version && !(s.owner_only && me.role !== "owner") ? (
                  <Link href={`/settings/${key}?from=${v.version}`} className="text-xs underline">
                    Restore this version
                  </Link>
                ) : null}
              </li>
            ))}
          </ul>
        </Card>
      </div>
    </>
  );
}
