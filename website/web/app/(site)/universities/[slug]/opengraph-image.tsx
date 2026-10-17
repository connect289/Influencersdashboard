import { ogCard, OG_SIZE } from "@/lib/og/card";
import { universityDetails } from "@/lib/server/search";

export const alt = "University on Eduwit";
export const size = OG_SIZE;
export const contentType = "image/png";

export default async function Image({ params }: { params: Promise<{ slug: string }> }) {
  const { slug } = await params;
  const u = await universityDetails(slug);
  return ogCard({
    eyebrow: "University",
    title: u ? u.name : "University",
    footer: u ? `${u.offerings} online and distance options · full fees · eligibility` : undefined,
  });
}
