"use client";
// Last-resort boundary that replaces the root layout, so the i18n provider is not available here. It shows a
// language-neutral symbol plus a retry; every other screen takes its text from messages/.
export default function GlobalError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="en">
      <body style={{ fontFamily: "system-ui, sans-serif", display: "grid", placeItems: "center", minHeight: "100dvh", margin: 0, background: "#f2f4f7", color: "#0e2240" }}>
        <main style={{ textAlign: "center" }}>
          <p style={{ fontSize: 48, margin: 0 }} aria-hidden>
            ⚠
          </p>
          <button type="button" onClick={reset} style={{ marginTop: 16, padding: "10px 18px", borderRadius: 12, border: 0, background: "#0b2f5e", color: "#fff", fontSize: 15 }}>
            ↻
          </button>
        </main>
      </body>
    </html>
  );
}
