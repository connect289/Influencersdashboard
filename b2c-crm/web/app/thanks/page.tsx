import type { Metadata } from "next";

export const metadata: Metadata = { title: "Eduwit", robots: { index: false } };

/** Where "I'm interested, call me" and the unsubscribe page land. */
export default async function Thanks({ searchParams }: { searchParams: Promise<{ unsubscribed?: string; link?: string }> }) {
  const sp = await searchParams;
  const [title, body] = sp.unsubscribed
    ? ["You are unsubscribed", sp.unsubscribed === "all" ? "Eduwit will not message you again. If you change your mind, write to us on WhatsApp." : "You will not get Eduwit emails any more."]
    : sp.link ? ["This link has expired", "Reply to the email or write to us on WhatsApp and a counsellor will help."]
    : ["Thank you", "A counsellor will call you soon, in working hours (10 am to 7 pm)."];
  return (
    <main className="auth">
      <div className="card">
        <h1>{title}</h1>
        <p className="muted">{body}</p>
      </div>
    </main>
  );
}
