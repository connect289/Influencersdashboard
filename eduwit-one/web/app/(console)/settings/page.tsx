import { type Metadata } from "next";
import Link from "next/link";
import { Badge } from "@/components/ui/badge.tsx";
import { Card } from "@/components/ui/card.tsx";
import { PageHeader } from "@/components/ui/state.tsx";
import { requireUser } from "@/lib/session.ts";

export const metadata: Metadata = { title: "Settings" };

const sections: Array<{ href: string; title: string; text: string; owner?: boolean }> = [
  {
    href: "/settings/setup",
    title: "Setup",
    text: "Every credential and identity still to fill in, with a validate button each (spec §15).",
  },
  {
    href: "/settings/checks",
    title: "Checks and thresholds",
    text: "Switch checks on or off, change severity and cadence, per check; the shared thresholds.",
  },
  {
    href: "/settings/alerts",
    title: "Alert routing",
    text: "Recipients (owner), escalation timing, the P2 digest hour, storm limits.",
  },
  {
    href: "/settings/fixes",
    title: "Fixes",
    text: "Each auto-fix's switch, with its dry-run history beside it.",
    owner: true,
  },
  { href: "/settings/ai", title: "AI models", text: "Model routing per task and tier, daily caps." },
  {
    href: "/settings/events",
    title: "Privacy (PII)",
    text: "The keys removed from every copied event and AI input.",
    owner: true,
  },
  {
    href: "/settings/test_identities",
    title: "Test identities",
    text: "The test number, mailbox, preview URL, partner and creator the synthetic tests use.",
  },
  {
    href: "/settings/maintenance",
    title: "Mutes and maintenance",
    text: "Mute a check or open a maintenance window on an app.",
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
  { href: "/settings/hosts", title: "Hosts", text: "The apps' addresses Eduwit One probes and links to." },
  { href: "/settings/access", title: "Sign-in", text: "Owners, trusted-device days, idle sign-out.", owner: true },
];

export default async function SettingsPage() {
  const me = await requireUser("/settings");
  return (
    <>
      <PageHeader
        title="Settings"
        description="Every change is versioned with a reason and takes effect within a minute, without a deploy."
      />
      <div className="grid gap-3 sm:grid-cols-2 xl:grid-cols-3">
        {sections.map((s) => (
          <Card key={s.href}>
            <Link href={s.href} className="grid gap-1 p-4 hover:bg-surface-2">
              <span className="flex items-center justify-between gap-2 font-medium">
                {s.title}
                {s.owner ? <Badge tone={me.role === "owner" ? "neutral" : "off"}>owner</Badge> : null}
              </span>
              <span className="text-sm text-fg-muted">{s.text}</span>
            </Link>
          </Card>
        ))}
      </div>
    </>
  );
}
