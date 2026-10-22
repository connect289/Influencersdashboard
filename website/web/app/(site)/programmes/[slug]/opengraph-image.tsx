import { ogCard, OG_SIZE } from "@/lib/og/card";
import { curatedView } from "@/lib/server/search";

export const alt = "Programmes on Eduwit";
export const size = OG_SIZE;
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const v = await curatedView(slug);
  return ogCard({ eyebrow: "Compare programmes", title: v?.title ?? "Online, distance and on-campus programmes" });
}
