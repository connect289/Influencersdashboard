import { Suspense } from "react";
import { Logo } from "@/components/brand/Logo";
import { requireAdmin } from "@/lib/server/admin";
import { signOutAdmin } from "./actions";

export const metadata = { title: "Dashboard" };

async function Dashboard() {
  const s = await requireAdmin("viewer");
  return (
    <div className="grid gap-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-semibold">Website admin</h1>
          <p className="text-muted text-sm">
            Signed in as {s.email} · {s.role.replace("_", " ")}
          </p>
        </div>
        <form action={signOutAdmin}>
          <button type="submit" className="border-border h-10 rounded-full border px-4 text-sm">
            Sign out
          </button>
        </form>
      </div>
      <p className="border-border-strong text-muted rounded-[var(--radius-lg)] border border-dashed p-5">
        Content, curated views, taxonomy, data quality, advisor insights, outbox and SEO tools arrive in Phases 10–11.
      </p>
    </div>
  );
}

export default function AdminHome() {
  return (
    <main id="main" className="container-site grid gap-8 py-8">
      <Logo height={28} />
      <Suspense fallback={<div className="skeleton h-24" />}>
        <Dashboard />
      </Suspense>
    </main>
  );
}
