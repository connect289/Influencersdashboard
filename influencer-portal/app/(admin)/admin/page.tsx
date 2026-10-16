import Link from "next/link";
import { CheckCircle2, Circle } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { env } from "@/lib/env";

interface Check {
  key: string;
  done: boolean;
  label: string;
  hint: string;
  href?: string;
}

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.overview") };
}

export default async function AdminOverview() {
  const { supabase, me } = await requireStaff();
  const t = await getTranslations();
  const canSettings = me.permissions.has("settings.read");
  const canSystem = me.permissions.has("system.read");

  const [settings, signatories, terms, status] = await Promise.all([
    canSettings ? supabase.rpc("settings_list") : Promise.resolve({ data: null, error: null }),
    supabase.from("staff_profiles").select("user_id", { count: "exact", head: true }).eq("is_signatory", true).eq("status", "active"),
    supabase.from("terms_versions").select("kind").in("kind", ["platform_terms", "privacy"]),
    canSystem ? supabase.rpc("system_status") : Promise.resolve({ data: null, error: null }),
  ]);
  const failed = settings.error ?? signatories.error ?? terms.error ?? status.error;

  const rows = (settings.data ?? []) as { key: string; value: Record<string, unknown>; needs_confirmation: string | null; confirmed_at: string | null; label: string }[];
  const org = rows.find((r) => r.key === "organisation.profile")?.value ?? {};
  const termKinds = new Set(((terms.data ?? []) as { kind: string }[]).map((r) => r.kind));
  const e = env();
  const checks: Check[] = [];
  if (canSettings) {
    checks.push({ key: "org", done: Boolean(org.gstin) && Boolean(org.pan), label: t("overview.checks.org"), hint: t("overview.checks.orgHint"), href: "/admin/settings#organisation.profile" });
    for (const r of rows.filter((x) => x.needs_confirmation && !x.confirmed_at)) {
      checks.push({ key: `confirm:${r.key}`, done: false, label: t("overview.checks.confirm", { setting: r.label }), hint: r.needs_confirmation ?? "", href: `/admin/settings#${r.key}` });
    }
  }
  checks.push({ key: "signatory", done: (signatories.count ?? 0) > 0, label: t("overview.checks.signatory"), hint: t("overview.checks.signatoryHint"), href: me.permissions.has("staff.manage") ? "/admin/staff" : undefined });
  checks.push({ key: "terms", done: termKinds.has("platform_terms") && termKinds.has("privacy"), label: t("overview.checks.terms"), hint: t("overview.checks.termsHint") });
  checks.push({ key: "email", done: e.EMAIL_PROVIDER !== "mock", label: t("overview.checks.email"), hint: t("overview.checks.emailHint", { provider: e.EMAIL_PROVIDER }) });
  checks.push({ key: "whatsapp", done: e.WHATSAPP_PROVIDER !== "mock", label: t("overview.checks.whatsapp"), hint: t("overview.checks.whatsappHint") });
  checks.push({ key: "live", done: e.LIVE_MODE === "on", label: t("overview.checks.live"), hint: t("overview.checks.liveHint") });

  const jobs = (status.data as { jobs?: { due: number; dead: number; failed: number } } | null)?.jobs;
  const remaining = checks.filter((c) => !c.done).length;

  return (
    <>
      <PageHeader title={t("overview.title", { name: me.fullName.split(" ")[0] ?? me.fullName })} description={t("overview.subtitle")} />
      {failed ? <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} /> : null}
      <div className="grid gap-4 lg:grid-cols-3">
        <Card className="lg:col-span-2">
          <CardHeader title={t("overview.setupTitle")} description={remaining === 0 ? t("overview.setupDone") : t("overview.setupRemaining", { count: remaining })} />
          <ul className="flex flex-col gap-1">
            {checks.map((c) => (
              <li key={c.key} className="flex items-start gap-3 rounded-xl px-2 py-2">
                {c.done ? <CheckCircle2 className="mt-0.5 size-5 shrink-0 text-success" aria-label={t("overview.done")} /> : <Circle className="mt-0.5 size-5 shrink-0 text-faint" aria-label={t("overview.todo")} />}
                <div className="min-w-0">
                  {c.href && !c.done ? (
                    <Link href={c.href} className="text-sm font-medium text-primary underline-offset-4 hover:underline">
                      {c.label}
                    </Link>
                  ) : (
                    <p className="text-sm font-medium">{c.label}</p>
                  )}
                  {!c.done ? <p className="text-xs text-muted">{c.hint}</p> : null}
                </div>
              </li>
            ))}
          </ul>
        </Card>
        {jobs ? (
          <Card>
            <CardHeader title={t("overview.systemTitle")} description={t("overview.systemSubtitle")} />
            <dl className="grid grid-cols-3 gap-3 text-center">
              <div>
                <dt className="text-xs text-muted">{t("system.jobs.due")}</dt>
                <dd className="text-2xl font-semibold tabular">{jobs.due}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted">{t("system.jobs.failed")}</dt>
                <dd className="text-2xl font-semibold tabular">{jobs.failed}</dd>
              </div>
              <div>
                <dt className="text-xs text-muted">{t("system.jobs.dead")}</dt>
                <dd className={`text-2xl font-semibold tabular ${jobs.dead > 0 ? "text-danger" : ""}`}>{jobs.dead}</dd>
              </div>
            </dl>
            <Link href="/admin/system" className="mt-4 inline-block text-sm font-medium text-primary underline-offset-4 hover:underline">
              {t("overview.systemLink")}
            </Link>
          </Card>
        ) : null}
      </div>
    </>
  );
}
