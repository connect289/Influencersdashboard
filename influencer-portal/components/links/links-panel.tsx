// Links for one creator: the builder (when the viewer may make links) and the list.
import { getTranslations } from "next-intl/server";
import { Card, CardHeader } from "@/components/ui/card";
import { ErrorState } from "@/components/ui/states";
import { shortLinkBase } from "@/lib/attribution/short-link";
import { loadLinkOptions, loadLinks } from "@/lib/leads/data";
import type { ServerSupabase } from "@/lib/supabase/server";
import { LinkBuilder } from "./link-builder";
import { LinkList } from "./link-list";

export async function LinksPanel({
  supabase,
  creatorId,
  canCreate,
  staff,
}: {
  supabase: ServerSupabase;
  creatorId: string;
  canCreate: boolean;
  staff: boolean;
}) {
  const t = await getTranslations();
  const [links, options, base] = await Promise.all([
    loadLinks(supabase, creatorId).catch(() => null),
    canCreate ? loadLinkOptions(supabase, creatorId).catch(() => []) : Promise.resolve([]),
    shortLinkBase(supabase),
  ]);
  return (
    <div className="flex flex-col gap-4">
      {canCreate ? (
        options.length || staff ? (
          <LinkBuilder creatorId={creatorId} options={options} staff={staff} />
        ) : (
          <Card>
            <CardHeader title={t("links.builder.title")} description={t("links.needsDeal")} />
          </Card>
        )
      ) : null}
      {links === null ? (
        <ErrorState title={t("errors.loadFailed")} />
      ) : (
        <LinkList links={links} base={base} canEdit={canCreate} />
      )}
    </div>
  );
}
