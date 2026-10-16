"use client";

/** Any unexpected error: say so plainly and offer a retry. The detail stays in the server log. */
export default function ErrorPage({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <main className="auth">
      <div className="card">
        <h1>Something went wrong</h1>
        <p className="muted">The page could not load. Try again; if it keeps happening, tell the Admin.</p>
        <button type="button" className="btn primary" onClick={reset}>Try again</button>
      </div>
    </main>
  );
}
