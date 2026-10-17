import { Suspense } from "react";
import { Logo } from "@/components/brand/Logo";
import { LoginForm } from "./LoginForm";

export const metadata = { title: "Sign in" };

async function Form({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const sp = await searchParams;
  return <LoginForm googleError={sp.error === "google"} />;
}

export default function AdminLogin({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  return (
    <main id="main" className="grid min-h-dvh place-items-center px-4">
      <div className="glass hairline-lumen grid w-full max-w-sm gap-6 rounded-[var(--radius-xl)] p-6">
        <Logo height={30} />
        <div>
          <h1 className="text-xl font-semibold">Website admin</h1>
          <p className="text-muted mt-1 text-sm">Staff only. You will confirm a code sent to your email.</p>
        </div>
        <Suspense fallback={null}>
          <Form searchParams={searchParams} />
        </Suspense>
      </div>
    </main>
  );
}
