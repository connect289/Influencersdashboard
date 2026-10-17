import { ogCard, OG_SIZE } from "@/lib/og/card";
import { resource } from "@/lib/server/content";

export const alt = "Guide on Eduwit";
export const size = OG_SIZE;
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const r = await resource(slug);
  return ogCard({ eyebrow: "Guide", title: r?.title ?? "Guides for online learners", footer: r ? `By ${r.author.name} · reviewed by ${r.reviewer.name}` : undefined });
}
