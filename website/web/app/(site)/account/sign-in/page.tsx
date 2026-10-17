import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { Suspense } from "react";
import { safeLocalPath } from "@/lib/security/paths";
import { currentStudent } from "@/lib/server/student-session";
import { SignInForm } from "./SignInForm";

export const metadata: Metadata = { title: "Sign in", robots: { index: false, follow: false } };

const safeNext = (n?: string) => safeLocalPath(n, "/account");

async function Body({ searchParams }: { searchParams: Promise<{ next?: string; signed_out?: string }> }) {
  const sp = await searchParams;
  const next = safeNext(sp.next);
  if (await currentStudent()) redirect(next);
  return (
    <>
      {sp.signed_out ? (
        <p role="status" className="text-success text-sm">
          You&apos;re signed out.
        </p>
      ) : null}
      <SignInForm next={next} />
    </>
  );
}

/** /account/sign-in — students sign in with an email code; no passwords. */
export default function SignInPage({ searchParams }: PageProps<"/account/sign-in">) {
  return (
    <main id="main" className="container-site grid place-items-center py-12 sm:py-20">
      <div className="glass hairline-lumen grid w-full max-w-md gap-6 rounded-[var(--radius-xl)] p-6 sm:p-8">
        <div>
          <h1 className="font-display text-text text-2xl font-semibold">Sign in to Eduwit</h1>
          <p className="text-muted mt-1 text-sm">See your applications, shortlist and saved comparisons. We&apos;ll email you a 6-digit code.</p>
        </div>
        <Suspense fallback={<div className="h-40" />}>
          <Body searchParams={searchParams as Promise<{ next?: string; signed_out?: string }>} />
        </Suspense>
      </div>
    </main>
  );
}
