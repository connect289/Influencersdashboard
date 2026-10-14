/* eslint-disable @next/next/no-img-element */
export default function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <main className="auth">
      <div className="card">
        <div className="brand">
          <img src="/logo.jpg" alt="" width={36} height={36} />
          <span>Eduwit CRM</span>
        </div>
        {children}
      </div>
    </main>
  );
}
