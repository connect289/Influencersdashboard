import type { Metadata } from "next";
import { isQuestion, type QuestionKey } from "@/lib/qualify";
import { adminClient } from "@/lib/supabase/admin";
import { QualifyForm } from "./QualifyForm";

export const metadata: Metadata = { title: "A few quick questions", robots: { index: false, follow: false } };
export const dynamic = "force-dynamic";

type Form = { status: "open" | "unknown" | "answered" | "closed" | "expired"; first_name?: string | null; questions?: string[]; known?: Partial<Record<QuestionKey, string>> };

/** The qualification form (spec B6.3): no sign-in, the link in the student's WhatsApp or email is the only key (b2c.qualify_form). */
export default async function QualifyPage({ params }: { params: Promise<{ token: string }> }) {
  const token = (await params).token;
  let f: Form = { status: "unknown" };
  if (/^[0-9a-f]{64}$/.test(token)) {
    const { data, error } = await adminClient().rpc("qualify_form", { p_token: token });
    if (error) console.error("qualify_form failed", error.code);
    else f = data as Form;
  }
  const questions = (f.questions ?? []).filter(isQuestion);
  return (
    <main className="auth">
      <div className="card">
        {f.status === "open" && questions.length > 0 ? (
          <>
            <h1>{f.first_name ? `Hi ${f.first_name}` : "Hello"}</h1>
            <p className="muted">Answer {questions.length === 1 ? "one quick question" : `${questions.length} quick questions`} and we will suggest programmes that fit you.</p>
            <QualifyForm token={token} questions={questions} known={f.known ?? {}} />
          </>
        ) : f.status === "answered" ? (
          <><h1>Thank you</h1><p className="muted">We already have your answers. A counsellor will be in touch.</p></>
        ) : (
          <><h1>This link is no longer open</h1><p className="muted">Reply to our WhatsApp message or email and a counsellor will help you.</p></>
        )}
      </div>
    </main>
  );
}
