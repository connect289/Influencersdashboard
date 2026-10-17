import { getTranslations } from "next-intl/server";
import { AvatarUpload } from "@/components/media-kit/avatar-upload";
import { MediaKitSettings } from "@/components/media-kit/media-kit-settings";
import { MediaKitView } from "@/components/media-kit/media-kit-view";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { onboardingState } from "@/lib/creators/onboarding";
import { env } from "@/lib/env";
import { publicEnv } from "@/lib/env-public";
import { avatarUrl, mediaKitSchema } from "@/lib/media-kit/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.mediaKit") };
}

export default async function CreatorMediaKitPage() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const [kitRes, state] = await Promise.all([
    supabase.rpc("media_kit", { p_creator: me.creatorId }),
    supabase.rpc("onboarding_state"),
  ]);
  const kit = kitRes.error ? null : mediaKitSchema.safeParse(kitRes.data);
  const approved = onboardingState.safeParse(state.data).data?.approved === true;
  if (!kit?.success)
    return <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />;
  const avatar = avatarUrl(publicEnv.supabaseUrl, kit.data.avatar_path);
  return (
    <>
      <PageHeader title={t("nav.creator.mediaKit")} description={t("mediaKit.subtitle")} />
      <div className="flex flex-col gap-4">
        <Card>
          <CardHeader title={t("mediaKit.photo")} description={t("mediaKit.photoHint")} />
          <AvatarUpload creatorId={me.creatorId} current={avatar} name={kit.data.display_name} />
        </Card>
        <MediaKitSettings
          creatorId={me.creatorId}
          handle={kit.data.handle}
          publicPage={kit.data.public_page_enabled}
          showRates={kit.data.show_rates}
          siteUrl={env().NEXT_PUBLIC_SITE_URL}
          approved={approved}
        />
        <h2 className="mt-2 text-sm font-semibold text-muted">{t("mediaKit.preview")}</h2>
        <MediaKitView kit={kit.data} avatar={avatar} />
      </div>
    </>
  );
}
