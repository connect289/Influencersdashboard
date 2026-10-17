import type { Metadata } from "next";

export const metadata: Metadata = { robots: { index: false, follow: false }, title: "Design concepts" };

export default function ConceptsLayout({ children }: { children: React.ReactNode }) {
  return children;
}
