import type { Metadata } from "next";
import { safeNext } from "@/lib/security";
import { AUTH_ERRORS, AUTH_REASONS } from "../messages";
import { LoginForm } from "./LoginForm";

export const metadata: Metadata = { title: "Sign in" };

export default async function LoginPage({ searchParams }: { searchParams: Promise<Record<string, string | undefined>> }) {
  const sp = await searchParams;
  return (
    <LoginForm
      next={safeNext(sp.next)}
      error={sp.error ? (AUTH_ERRORS[sp.error] ?? null) : null}
      notice={sp.reason ? (AUTH_REASONS[sp.reason] ?? null) : null}
    />
  );
}
