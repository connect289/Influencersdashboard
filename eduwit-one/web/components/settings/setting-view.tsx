import Link from "next/link";
import { notFound } from "next/navigation";
import { SettingEditor } from "@/components/settings/setting-editor.tsx";
import { Card, CardBody, CardHeader } from "@/components/ui/card.tsx";
import { PageError } from "@/components/ui/page-error.tsx";
import { Banner, Code, PageHeader } from "@/components/ui/state.tsx";
import { ago, ist, json } from "@/lib/format.ts";
import { requireUser } from "@/lib/session.ts";
import { settingAbout } from "@/lib/settings/about.ts";
import { ui } from "@/lib/ui/api.ts";
import { settingsSchema, versionsSchema } from "@/lib/ui/schemas.ts";

/**
 * One setting: its JSON editor (read-only for an engineer on an owner key), its versions, and restoring one as a new
 * version. Used by /settings/[key] and, for the check runner's key, by /settings/checks (whose route shadows it).
 */
export async function SettingView({ name, from, base, id }: { name: string; from: number; base: string; id?: string }) {
  const key = name;
  const me = await requireUser(base);
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
  const info = settingAbout[key] ?? { title: key, text: "A setting read by Eduwit One at runtime." };
  // Restoring is saving an earlier version's value again, as a new version with its own reason.
  const restoring = versions.find((v) => v.version === from && v.version !== s.version);
  return (
    <section id={id ?? "editor"} className="grid gap-4">
      <PageHeader
        title={info.title}
        description={`${info.text} Version ${s.version}, changed ${ago(s.updated_at)} by ${s.actor}.`}
      />
      <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardBody>
            {restoring ? (
              <div className="mb-3">
                <Banner tone="p3">
                  The editor holds version {restoring.version}. Saving makes it version {s.version + 1}; give the
                  reason.{" "}
                  <Link href={base} className="underline">
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
                  <Link href={`${base}?from=${v.version}#${id ?? "editor"}`} className="text-xs underline">
                    Restore this version
                  </Link>
                ) : null}
              </li>
            ))}
          </ul>
        </Card>
      </div>
    </section>
  );
}
