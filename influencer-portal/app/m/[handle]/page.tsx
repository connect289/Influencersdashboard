import Link from "next/link";
import { notFound } from "next/navigation";
import { Download } from "lucide-react";
import { getTranslations } from "next-intl/server";
import { Logo } from "@/components/brand/logo";
import { MediaKitView } from "@/components/media-kit/media-kit-view";
import { Button } from "@/components/ui/button";
import { publicEnv } from "@/lib/env-public";
import { avatarUrl, mediaKitSchema, type MediaKit } from "@/lib/media-kit/data";
import { createClient } from "@/lib/supabase/server";

export const revalidate = 300;

async function load(handle: string): Promise<MediaKit | null> {
  if (!/^[a-z0-9._]{3,30}$/i.test(handle)) return null;
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("media_kit_public", { p_handle: handle });
  if (error) return null;
  const kit = mediaKitSchema.safeParse(data);
  return kit.success ? kit.data : null;
}

export async function generateMetadata({ params }: { params: Promise<{ handle: string }> }) {
  const t = await getTranslations();
  const kit = await load((await params).handle);
  if (!kit) return { title: t("mediaKit.notFound"), robots: { index: false } };
  return {
    title: t("mediaKit.publicTitle", { name: kit.display_name }),
    description: kit.bio?.slice(0, 160) ?? undefined,
  };
}

/** Public creator page and media kit (only when the creator turned it on). */
export default async function PublicMediaKit({ params }: { params: Promise<{ handle: string }> }) {
  const { handle } = await params;
  const t = await getTranslations();
  const kit = await load(handle);
  if (!kit) notFound();
  return (
    <main className="mx-auto w-full max-w-2xl px-4 py-6">
      <div className="mb-6 flex items-center justify-between gap-3">
        <Link href="/">
          <Logo label={t("app.tagline")} />
        </Link>
        <Button asChild size="sm" variant="secondary">
          <a href={`/m/${kit.handle}/pdf`}>
            <Download /> {t("mediaKit.pdf")}
          </a>
        </Button>
      </div>
      <MediaKitView kit={kit} avatar={avatarUrl(publicEnv.supabaseUrl, kit.avatar_path)} />
      <p className="mt-8 text-center text-xs text-muted">{t("mediaKit.publicFooter")}</p>
    </main>
  );
}
