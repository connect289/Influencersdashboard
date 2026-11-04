import { type Metadata } from "next";
import Link from "next/link";
import { Badge } from "@/components/ui/badge.tsx";
import { Card, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { PageHeader } from "@/components/ui/state.tsx";
import { ago } from "@/lib/format.ts";
import { requireUser } from "@/lib/session.ts";
import { settingAbout, settingHref } from "@/lib/settings/about.ts";
import { ui } from "@/lib/ui/api.ts";
import { settingsSchema } from "@/lib/ui/schemas.ts";

export const metadata: Metadata = { title: "Settings" };

// The pages of their own; every settings key is listed below them, from the database.
const pages: Array<{ href: string; title: string; text: string; owner?: boolean }> = [
  {
    href: "/settings/setup",
    title: "Setup",
    text: "Every credential and identity still to fill in, with a validate button each (spec §15). Secrets are the owner's.",
  },
  {
    href: "/settings/checks",
    title: "Checks and the runner",
    text: "Switch checks, change severity and cadence (P1, security and integrity checks stay on unless the owner says); the runner's timeouts.",
  },
  {
    href: "/settings/maintenance",
    title: "Mutes and maintenance",
    text: "Mute a check or open a maintenance window on an app.",
  },
  {
    href: "/settings/fixes",
    title: "Fixes",
    text: "Each auto-fix's switch, with its dry-run history beside it.",
    owner: true,
  },
  {
    href: "/settings/users",
    title: "Users and roles",
    text: "Who may sign in, as owner or engineer; trusted browsers.",
    owner: true,
  },
  {
    href: "/settings/privileges",
    title: "Privileges and baselines",
    text: "API-executable functions to acknowledge; integrity baselines; Vault secret names.",
  },
];

export default async function SettingsPage() {
  const me = await requireUser("/settings");
  let all;
  try {
    all = await ui("ui_settings", settingsSchema);
  } catch (e) {
    return <PageError error={e} />;
  }
  const keys = Object.entries(all)
    .filter(([k]) => !["setup", "setup_catalog", "fixes"].includes(k))
    .sort(([a], [b]) => (settingAbout[a]?.title ?? a).localeCompare(settingAbout[b]?.title ?? b));
  const ownerBadge = (owner: boolean | undefined) =>
    owner ? <Badge tone={me.role === "owner" ? "neutral" : "off"}>owner</Badge> : null;
  return (
    <>
      <PageHeader
        title="Settings"
        description="Every change is versioned with a reason and takes effect within a minute, without a deploy. Engineers tune thresholds, checks, tests and the funnel; everything that decides where a credential, an alert or a code goes is the owner's."
      />
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {pages.map((s) => (
          <Card key={s.href}>
            <Link href={s.href} className="grid gap-1 p-4 hover:bg-surface-2">
              <span className="flex items-center justify-between gap-2 font-medium">
                {s.title}
                {ownerBadge(s.owner)}
              </span>
              <span className="text-sm text-fg-muted">{s.text}</span>
            </Link>
          </Card>
        ))}
      </div>
      <Card>
        <CardHeader title="Every setting" description="Each one.settings key, its version and who changed it last." />
        <ul className="divide-y divide-border">
          {keys.map(([k, v]) => (
            <li key={k}>
              <Link
                href={settingHref(k)}
                className="grid gap-0.5 px-4 py-3 hover:bg-surface-2 sm:grid-cols-[14rem_1fr_auto] sm:items-center sm:gap-4"
              >
                <span className="font-medium">
                  {settingAbout[k]?.title ?? k} <span className="font-mono text-xs text-fg-muted">{k}</span>
                </span>
                <span className="text-sm text-fg-muted">
                  {settingAbout[k]?.text ?? "A setting read by Eduwit One at runtime."}
                </span>
                <span className="flex items-center gap-2 text-xs text-fg-muted">
                  v{v.version} · {ago(v.updated_at)} {ownerBadge(v.owner_only)}
                </span>
              </Link>
            </li>
          ))}
        </ul>
      </Card>
    </>
  );
}
