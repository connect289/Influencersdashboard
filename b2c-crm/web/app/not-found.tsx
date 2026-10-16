import Link from "next/link";

export default function NotFound() {
  return (
    <main className="auth">
      <div className="card">
        <h1>Not found</h1>
        <p className="muted">This page or lead does not exist, or it is not yours to see.</p>
        <Link className="btn primary" href="/">Go to your home</Link>
      </div>
    </main>
  );
}
