import Link from "next/link";
import { notFound } from "next/navigation";
import { ArrowLeft } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { z } from "zod";
import { GrantBadges } from "@/components/agency/grant-badges";
import { KycReview } from "@/components/creator-profile/kyc-review";
import { PlatformsCard } from "@/components/creator-profile/platforms-card";
import { ProfileForm } from "@/components/creator-profile/profile-form";
import { ContactsCard, PortfolioCard, RateCardCard } from "@/components/creator-profile/profile-lists";
import { CreatorActions } from "@/components/creators/creator-actions";
import { CreatorDialog } from "@/components/creators/creator-dialog";
import { OutreachPanel, type OutreachRow } from "@/components/creators/outreach-panel";
import { InviteButton } from "@/components/onboarding/invite-button";
import { ReviewActions } from "@/components/onboarding/review-actions";
import { TaskList } from "@/components/creators/tasks";
import { Badge, StatusBadge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { EmptyState, ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import type { CreatorStatus, PipelineStage } from "@/lib/creators/crm";
import { loadCreatorProfile, loadKyc } from "@/lib/creators/load";
import { loadPickers } from "@/lib/creators/staff-data";
import { loadTasks } from "@/lib/creators/tasks-data";
import { formatCompact, formatDate, formatDateTime, formatRelative } from "@/lib/format";
import { cn } from "@/lib/utils";

const TABS = ["overview", "profile", "kyc", "outreach", "tasks", "agencies", "history"] as const;
type Tab = (typeof TABS)[number];

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.admin.creators") };
}

/** Creator 360°: everything about one creator that exists so far. Later phases add deals, contracts, leads, money. */
export default async function Creator360({
  params,
  searchParams,
}: {
  params: Promise<{ creatorId: string }>;
  searchParams: Promise<{ tab?: string }>;
}) {
  const { creatorId } = await params;
  if (!z.uuid().safeParse(creatorId).success) notFound();
  const { supabase, me } = await requireStaff("creator.read");
  const t = await getTranslations();
  const p = me.permissions;
  const visible = TABS.filter(
    (x) =>
      (x !== "kyc" || p.has("kyc.read_masked")) &&
      (x !== "history" || p.has("audit.read")) &&
      (x !== "tasks" || p.has("task.write")),
  );
  const requested = (await searchParams).tab as Tab | undefined;
  const tab: Tab = requested && visible.includes(requested) ? requested : "overview";

  const { data, error } = await loadCreatorProfile(supabase, creatorId);
  if (!error && !data) notFound();
  if (!data) return <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />;
  const c = data.creator;
  const canWrite = p.has("creator.write");
  const pickers = await loadPickers(supabase);
  const owner = pickers.owners.find((o) => o.id === c.owner_id)?.name;
  const tier = pickers.tiers.find((o) => o.id === c.tier_id)?.name;
  const account = await supabase
    .from("creator_accounts")
    .select("creator_id")
    .eq("creator_id", creatorId)
    .maybeSingle();
  const hasAccount = Boolean(account.data);

  const header = (
    <PageHeader
      title={c.display_name}
      description={`@${c.handle}${c.city ? ` · ${c.city}` : ""}`}
      actions={
        canWrite ? (
          <>
            <CreatorDialog
              owners={pickers.owners}
              tiers={pickers.tiers}
              initial={{
                id: c.id,
                displayName: c.display_name,
                legalName: c.legal_name ?? "",
                handle: c.handle,
                email: c.email ?? "",
                phone: c.phone_e164 ?? "",
                city: c.city ?? "",
                state: c.state ?? "",
                languages: c.languages.join(", "),
                niches: c.niches.join(", "),
                tags: c.tags.join(", "),
                ownerId: c.owner_id ?? "",
                tierId: c.tier_id ?? "",
                source: c.source ?? "",
                bio: c.bio ?? "",
              }}
              trigger={
                <Button variant="secondary" size="sm">
                  {t("common.edit")}
                </Button>
              }
            />
            {p.has("creator.import") &&
            c.email &&
            !hasAccount &&
            !c.is_blocked &&
            ["prospect", "invited"].includes(c.status) ? (
              <InviteButton creatorId={c.id} name={c.display_name} email={c.email} resend={c.status === "invited"} />
            ) : null}
            <CreatorActions
              creatorId={c.id}
              name={c.display_name}
              stage={c.pipeline_stage}
              isBlocked={c.is_blocked}
              canDelete={p.has("creator.delete_draft") && c.status === "prospect" && !hasAccount}
            />
          </>
        ) : null
      }
    />
  );

  let body: React.ReactNode = null;
  if (tab === "overview") {
    const [follow, openTasks] = await Promise.all([
      supabase
        .from("outreach_activities")
        .select("next_follow_up_at")
        .eq("creator_id", creatorId)
        .is("follow_up_done_at", null)
        .not("next_follow_up_at", "is", null)
        .order("next_follow_up_at")
        .limit(1)
        .maybeSingle(),
      p.has("task.write")
        ? loadTasks(supabase, { creatorId, status: "open", limit: 5 })
        : Promise.resolve({ tasks: [], error: false }),
    ]);
    const facts: [string, React.ReactNode][] = [
      [
        t("creators.table.stage"),
        <StatusBadge
          key="s"
          status={c.pipeline_stage}
          label={t(`creators.stages.${c.pipeline_stage as PipelineStage}`)}
        />,
      ],
      [
        t("creators.fields.status"),
        <StatusBadge key="st" status={c.status} label={t(`creators.statuses.${c.status as CreatorStatus}`)} />,
      ],
      [t("creators.fields.owner"), owner ?? "—"],
      [t("creators.fields.tier"), tier ?? "—"],
      [t("creators.fields.source"), c.source ?? "—"],
      [t("creators.fields.account"), hasAccount ? t("creators.accountLinked") : t("creators.noAccount")],
      [t("creators.fields.email"), c.email ?? "—"],
      [t("profile.fields.phone"), c.phone_e164 ?? "—"],
      [t("creators.fields.added"), formatDate(c.created_at)],
      [t("creators.table.lastActivity"), c.last_activity_at ? formatRelative(c.last_activity_at) : "—"],
      [t("creators.fields.lastContacted"), c.last_contacted_at ? formatRelative(c.last_contacted_at) : "—"],
      [
        t("creators.table.followUp"),
        follow.data?.next_follow_up_at ? formatDateTime(follow.data.next_follow_up_at) : "—",
      ],
    ];
    const followers = data.platforms.reduce((s, x) => s + (x.followers ?? 0), 0);
    body = (
      <div className="grid gap-4 lg:grid-cols-[1fr_320px]">
        <div className="flex flex-col gap-4">
          {c.onboarding_submitted_at && !c.approved_at && c.status !== "archived" ? (
            <Card className="bg-accent-soft">
              <CardHeader
                title={t("onboarding.review.panelTitle")}
                description={t("onboarding.review.panelHint", { date: formatDateTime(c.onboarding_submitted_at) })}
              />
              {canWrite ? <ReviewActions creatorId={c.id} name={c.display_name} /> : null}
            </Card>
          ) : null}
          {c.is_blocked ? (
            <Card className="bg-danger-soft">
              <p className="text-sm font-medium text-danger">
                {t("creators.blockedBanner", { reason: c.blocked_reason ?? "" })}
              </p>
            </Card>
          ) : null}
          <Card>
            <CardHeader title={t("creators.overview.facts")} />
            <dl className="grid grid-cols-1 gap-x-6 gap-y-2 text-sm sm:grid-cols-2">
              {facts.map(([k, v]) => (
                <div key={k} className="flex justify-between gap-3 border-b border-line py-1.5">
                  <dt className="text-muted">{k}</dt>
                  <dd className="text-right font-medium">{v}</dd>
                </div>
              ))}
            </dl>
            {c.tags.length || c.niches.length ? (
              <div className="mt-3 flex flex-wrap gap-1">
                {c.niches.map((n) => (
                  <Badge key={`n-${n}`} family="progress">
                    {n}
                  </Badge>
                ))}
                {c.tags.map((x) => (
                  <Badge key={`t-${x}`}>{x}</Badge>
                ))}
              </div>
            ) : null}
            {c.bio ? <p className="mt-3 text-sm whitespace-pre-line text-muted">{c.bio}</p> : null}
          </Card>
          <PlatformsCard creatorId={c.id} platforms={data.platforms} canEdit={canWrite} />
        </div>
        <div className="flex flex-col gap-4">
          <Card>
            <CardHeader title={t("creators.overview.reach")} />
            <p className="text-3xl font-semibold tabular-nums">{formatCompact(followers)}</p>
            <p className="text-sm text-muted">{t("creators.overview.reachHint", { count: data.platforms.length })}</p>
          </Card>
          {p.has("task.write") ? (
            <Card>
              <CardHeader
                title={t("creators.overview.openTasks")}
                actions={
                  <Button asChild variant="link" size="sm">
                    <Link href={`?tab=tasks`}>{t("creators.followUps.viewAll")}</Link>
                  </Button>
                }
              />
              <TaskList tasks={openTasks.tasks} owners={pickers.owners} canWrite={false} showRelated={false} />
            </Card>
          ) : null}
        </div>
      </div>
    );
  } else if (tab === "profile") {
    body = (
      <div className="flex flex-col gap-4">
        <ProfileForm creator={c} canEdit={canWrite} />
        <PlatformsCard creatorId={c.id} platforms={data.platforms} canEdit={canWrite} />
        <RateCardCard creatorId={c.id} rates={data.rates} canEdit={canWrite} />
        <PortfolioCard creatorId={c.id} items={data.portfolio} canEdit={canWrite} />
        <ContactsCard creatorId={c.id} contacts={data.contacts} canEdit={canWrite} />
      </div>
    );
  } else if (tab === "kyc") {
    const kyc = await loadKyc(supabase, creatorId);
    body = kyc ? (
      <KycReview creatorId={c.id} kyc={kyc} canReveal={p.has("kyc.reveal")} canVerify={p.has("kyc.verify")} />
    ) : (
      <ErrorState title={t("errors.loadFailed")} />
    );
  } else if (tab === "outreach") {
    const { data: rows } = await supabase
      .from("outreach_activities")
      .select("id, channel, direction, outcome, notes, next_follow_up_at, follow_up_done_at, created_at, created_by")
      .eq("creator_id", creatorId)
      .order("created_at", { ascending: false })
      .limit(100);
    const names = new Map(pickers.owners.map((o) => [o.id, o.name]));
    const list: OutreachRow[] = (rows ?? []).map((r) => ({ ...r, author: names.get(r.created_by) ?? null }));
    body = <OutreachPanel creatorId={c.id} rows={list} canWrite={p.has("outreach.write")} />;
  } else if (tab === "tasks") {
    const { tasks } = await loadTasks(supabase, { creatorId });
    body = (
      <Card>
        <TaskList
          tasks={tasks}
          owners={pickers.owners}
          canWrite
          related={{ type: "creator", id: c.id }}
          showRelated={false}
        />
      </Card>
    );
  } else if (tab === "agencies") {
    const { data: links } = await supabase
      .from("agency_creator_links")
      .select("id, status, can_view, can_act_deliverables, can_negotiate_sign, can_view_earnings, agencies(id, name)")
      .eq("creator_id", creatorId)
      .in("status", ["pending", "active"]);
    body = (
      <Card>
        <CardHeader title={t("agencies.linkedCreators")} />
        {!links?.length ? (
          <EmptyState title={t("creators.noAgency")} />
        ) : (
          <ul className="flex flex-col divide-y divide-line">
            {links.map((l) => (
              <li key={l.id} className="flex flex-wrap items-center gap-3 py-3">
                <div className="min-w-0 flex-1">
                  {p.has("agency.manage") ? (
                    <Link
                      href={`/admin/agencies/${l.agencies.id}`}
                      className="text-sm font-medium text-primary hover:underline"
                    >
                      {l.agencies.name}
                    </Link>
                  ) : (
                    <p className="text-sm font-medium">{l.agencies.name}</p>
                  )}
                  {l.status === "active" ? <GrantBadges grants={l} /> : null}
                </div>
                <StatusBadge status={l.status} label={t(`agencies.links.status.${l.status as "pending" | "active"}`)} />
              </li>
            ))}
          </ul>
        )}
      </Card>
    );
  } else {
    const { data: rows } = await supabase
      .from("audit_log")
      .select("id, at, actor_id, actor_role, entity_type, action, after")
      .in("entity_type", ["creator", "creator_kyc", "creator_account"])
      .eq("entity_id", creatorId)
      .order("id", { ascending: false })
      .limit(100);
    const names = new Map(pickers.owners.map((o) => [o.id, o.name]));
    body = (
      <Card>
        <CardHeader title={t("creators.history.title")} description={t("creators.history.hint")} />
        {!rows?.length ? (
          <EmptyState title={t("creators.history.empty")} />
        ) : (
          <ol className="flex flex-col divide-y divide-line">
            {rows.map((r) => (
              <li key={r.id} className="py-2.5 text-sm">
                <p>
                  <span className="font-medium">{r.entity_type}</span> · {r.action}
                  <span className="ml-2 text-xs text-muted">
                    {formatDateTime(r.at)} · {(r.actor_id && names.get(r.actor_id)) ?? r.actor_role ?? "system"}
                  </span>
                </p>
                {r.after && typeof r.after === "object" ? (
                  <p className="truncate text-xs text-muted">{Object.keys(r.after).join(", ")}</p>
                ) : null}
              </li>
            ))}
          </ol>
        )}
      </Card>
    );
  }

  return (
    <>
      <Link href="/admin/creators" className="mb-2 inline-flex items-center gap-1 text-sm text-muted hover:text-ink">
        <ArrowLeft className="size-4" aria-hidden /> {t("nav.admin.creators")}
      </Link>
      {header}
      <nav
        className="-mx-4 mb-4 flex gap-1 overflow-x-auto border-b border-line px-4 md:mx-0 md:px-0"
        aria-label={t("creators.tabs.label")}
      >
        {visible.map((x) => (
          <Link
            key={x}
            href={x === "overview" ? `/admin/creators/${creatorId}` : `/admin/creators/${creatorId}?tab=${x}`}
            aria-current={tab === x ? "page" : undefined}
            className={cn(
              "-mb-px border-b-2 px-3 py-2 text-sm whitespace-nowrap",
              tab === x ? "border-primary font-medium text-primary" : "border-transparent text-muted hover:text-ink",
            )}
          >
            {t(`creators.tabs.${x}`)}
          </Link>
        ))}
      </nav>
      {body}
    </>
  );
}
