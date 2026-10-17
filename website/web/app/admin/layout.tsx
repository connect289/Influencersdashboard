import type { Metadata } from "next";
import { connection } from "next/server";

export const metadata: Metadata = {
  title: { default: "Admin", template: "%s · Eduwit admin" },
  robots: { index: false, follow: false },
};

// The admin area renders per request so Next can stamp the CSP nonce on every script (D-025); never cached.
export const instant = false;

export default async function AdminLayout({ children }: { children: React.ReactNode }) {
  await connection();
  return <div className="bg-bg text-text min-h-dvh">{children}</div>;
}
