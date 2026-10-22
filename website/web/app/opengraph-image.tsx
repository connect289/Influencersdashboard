import { ogCard, OG_SIZE } from "@/lib/og/card";

export const alt = "Eduwit — compare online, distance and on-campus degrees";
export const size = OG_SIZE;
export const contentType = "image/png";

export default function Image() {
  return ogCard({ eyebrow: "Choose your education wisely", title: "Compare online, distance and on-campus degrees, with full fees and eligibility" });
}
