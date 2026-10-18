import Link from "next/link";
import { Plus } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { AnnouncementForm } from "@/components/communication/announcement-form";
import { AnnouncementList } from "@/components/communication/announcement-list";
import { CommNav } from "@/components/communication/comm-nav";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireStaff } from "@/lib/auth/guards";
import { loadAnnouncements, loadSegmentOptions } from "@/lib/communication/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("communication.sections.announcements") };
}

/** Announcements to creators (spec 14): all or a segment, now or scheduled; ?new=1 or ?edit=<id> opens the form. */
export default async function AnnouncementsPage({
  searchParams,
}: {
  searchParams: Promise<{ new?: string; edit?: string }>;
}) {
  const { supabase, me } = await requireStaff("announcement.write");
  const t = await getTranslations();
  const sp = await searchParams;
  const rows = await loadAnnouncements(supabase).catch(() => null);
  const editing = sp.edit
    ? (rows?.find((r) => r.id === sp.edit && ["draft", "scheduled"].includes(r.status)) ?? null)
    : null;
  const formOpen = sp.new === "1" || editing !== null;
  const options = formOpen ? await loadSegmentOptions(supabase) : null;
  return (
    <>
      <PageHeader
        title={t("communication.title")}
        description={t("communication.announcements.subtitle")}
        help="/admin/help/influencer-manager#announcements"
        actions={
          formOpen ? null : (
            <Button asChild size="sm">
              <Link href="/admin/communication/announcements?new=1">
                <Plus /> {t("communication.announcements.new")}
              </Link>
            </Button>
          )
        }
      />
      <CommNav current="announcements" permissions={me.permissions} />
      {formOpen && options ? (
        <>
          <Link
            href="/admin/communication/announcements"
            className="mb-3 inline-block text-sm text-muted hover:text-ink"
          >
            {t("common.cancel")}
          </Link>
          <AnnouncementForm
            key={editing?.id ?? "new"}
            initial={editing}
            tiers={options.tiers}
            campaigns={options.campaigns}
          />
        </>
      ) : rows ? (
        <AnnouncementList rows={rows} />
      ) : (
        <Card>
          <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
        </Card>
      )}
    </>
  );
}
