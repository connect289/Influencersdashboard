"use client";

/** Last-resort boundary when the root layout itself fails. Plain HTML, inline styles (no app CSS may be available). */
export default function GlobalError({ error, reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="en-IN">
      <body
        style={{
          margin: 0,
          fontFamily: "system-ui, sans-serif",
          background: "#030913",
          color: "#eaf1fb",
          display: "grid",
          minHeight: "100vh",
          placeItems: "center",
          padding: 24,
        }}
      >
        <main style={{ maxWidth: 520 }}>
          <h1 style={{ fontSize: 28 }}>Eduwit is temporarily unavailable</h1>
          <p style={{ color: "#a6b6cc" }}>
            Please try again in a moment, or call +91-9650683269 / email connect@eduwit.in.
          </p>
          <button
            type="button"
            onClick={reset}
            style={{
              marginTop: 16,
              height: 44,
              padding: "0 20px",
              borderRadius: 999,
              border: 0,
              background: "#f3a503",
              color: "#1a1200",
              fontWeight: 600,
            }}
          >
            Try again
          </button>
          {error.digest ? <p style={{ fontSize: 12, color: "#8597b0" }}>Reference: {error.digest}</p> : null}
        </main>
      </body>
    </html>
  );
}
