import { HelpButton } from "@/components/guide/HelpButton";

/** A screen's title bar and body. On a phone the title bar is compact; the body scrolls with the page. */
export function Page({ title, actions, sub, children, back }: { title: React.ReactNode; actions?: React.ReactNode; sub?: React.ReactNode; children: React.ReactNode; back?: React.ReactNode }) {
  return (
    <>
      <header className="topbar">
        {back}
        <div className="grow" style={{ minWidth: 0 }}>
          <h1 className="ellipsis">{title}</h1>
          {sub ? <div className="small muted">{sub}</div> : null}
        </div>
        {actions}
        <HelpButton />
      </header>
      <div className="content">{children}</div>
    </>
  );
}

export function Empty({ children }: { children: React.ReactNode }) {
  return <div className="empty">{children}</div>;
}

export function SetupError({ error }: { error: unknown }) {
  const msg = error instanceof Error ? error.message : String(error);
  return <div className="banner danger" role="alert">This screen could not load: {msg}</div>;
}
