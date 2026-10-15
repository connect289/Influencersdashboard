import type { Metadata } from "next";
import { Guide } from "@/components/guide/Guide";
import { Page, SetupError } from "@/components/shell/Page";
import { requireUser } from "@/lib/auth";
import { rpc } from "@/lib/data";
import type { Article, Reader } from "@/app/guide-actions";
import { guideImages } from "@/lib/guide-images";

export const metadata: Metadata = { title: "Guide" };

/** The Admin's and Marketing's guide (spec B16). The Admin sees all three guides, edits them and sees who has read them. */
export default async function GuidePage({ searchParams }: { searchParams: Promise<{ archived?: string }> }) {
  const me = await requireUser("workspace", "/w/guide");
  const admin = me.role === "admin";
  const archived = admin && (await searchParams).archived === "1";
  let articles: Article[];
  let readers: Reader[] | undefined;
  let images: Awaited<ReturnType<typeof guideImages>> = {};
  try {
    [articles, readers] = await Promise.all([
      rpc<Article[]>("guides", { p_role: null, p_archived: archived }),
      admin ? rpc<Reader[]>("guide_readers") : Promise.resolve(undefined),
    ]);
    // screenshots of the articles b2c.guides allowed (it does not return them itself)
    images = await guideImages(articles.map((a) => a.id)).catch(() => ({}));
  } catch (e) {
    return <Page title="Guide"><SetupError error={e} /></Page>;
  }
  return (
    <Page title="Guide" sub={admin ? "All three guides. Edit any article; a changed one shows as new to everyone." : "The Marketing guide."}
      actions={admin ? <a className="btn quiet sm" href={archived ? "/w/guide" : "/w/guide?archived=1"}>{archived ? "Hide archived" : "Show archived"}</a> : undefined}>
      <Guide articles={articles} admin={admin} readers={readers} images={images} />
    </Page>
  );
}
