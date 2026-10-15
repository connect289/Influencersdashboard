"use client";
import { useState, type ReactNode } from "react";

export type LeadTab = { id: string; label: string; content: ReactNode };

/**
 * The lead screen's body: tabs on the left, the activity rail (follow-ups, nurture, timeline) always beside them on a
 * laptop. On a phone the rail becomes one more tab, "Activity", so one thing is on screen at a time.
 */
export function LeadTabs({ tabs, aside, initial }: { tabs: LeadTab[]; aside: ReactNode; initial?: string }) {
  const first = tabs[0]?.id ?? "overview";
  const [active, setActive] = useState(initial && tabs.some((t) => t.id === initial) ? initial : first);
  const shown = (id: string) => active === id || (active === "activity" && id === first); // a laptop never hides the rail, so "activity" falls back to the first tab
  return (
    <div className="lead-layout" data-tab={active}>
      <div className="lead-main">
        <div className="tabbar" role="tablist" aria-label="Lead sections">
          {tabs.map((t) => (
            <button key={t.id} type="button" role="tab" id={`tab-${t.id}`} aria-selected={active === t.id} aria-controls={`panel-${t.id}`} onClick={() => setActive(t.id)}>{t.label}</button>
          ))}
          <button type="button" role="tab" className="tab-activity" aria-selected={active === "activity"} onClick={() => setActive("activity")}>Activity</button>
        </div>
        {tabs.map((t) => (
          <div key={t.id} role="tabpanel" id={`panel-${t.id}`} aria-labelledby={`tab-${t.id}`} hidden={!shown(t.id)} className="stack">{t.content}</div>
        ))}
      </div>
      <aside className="lead-aside" aria-label="Activity">{aside}</aside>
    </div>
  );
}
