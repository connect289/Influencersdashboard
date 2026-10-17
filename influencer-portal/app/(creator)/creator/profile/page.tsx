import { getTranslations } from "next-intl/server";
import { PlatformsCard } from "@/components/creator-profile/platforms-card";
import { ProfileForm } from "@/components/creator-profile/profile-form";
import {
  ContactsCard,
  PortfolioCard,
  RateCardCard,
} from "@/components/creator-profile/profile-lists";
import { AvatarUpload } from "@/components/media-kit/avatar-upload";
import { Card, CardHeader } from "@/components/ui/card";
import { PageHeader } from "@/components/ui/page-header";
import { ErrorState } from "@/components/ui/states";
import { requireCreator } from "@/lib/auth/guards";
import { loadCreatorProfile } from "@/lib/creators/load";
import { publicEnv } from "@/lib/env-public";
import { avatarUrl } from "@/lib/media-kit/data";

export async function generateMetadata() {
  const t = await getTranslations();
  return { title: t("nav.creator.profile") };
}

export default async function CreatorProfilePage() {
  const { supabase, me } = await requireCreator();
  const t = await getTranslations();
  const { data } = await loadCreatorProfile(supabase, me.creatorId);
  return (
    <>
      <PageHeader title={t("profile.title")} description={t("profile.subtitle")} />
      {!data ? (
        <ErrorState title={t("errors.loadFailed")} description={t("errors.tryAgain")} />
      ) : (
        <div className="flex flex-col gap-4">
          <Card>
            <CardHeader title={t("mediaKit.photo")} description={t("mediaKit.photoHint")} />
            <AvatarUpload
              creatorId={me.creatorId}
              current={avatarUrl(publicEnv.supabaseUrl, data.creator.avatar_path)}
              name={data.creator.display_name}
            />
          </Card>
          <ProfileForm creator={data.creator} canEdit />
          <PlatformsCard creatorId={me.creatorId} platforms={data.platforms} canEdit />
          <RateCardCard creatorId={me.creatorId} rates={data.rates} canEdit />
          <PortfolioCard creatorId={me.creatorId} items={data.portfolio} canEdit />
          <ContactsCard creatorId={me.creatorId} contacts={data.contacts} canEdit />
        </div>
      )}
    </>
  );
}
