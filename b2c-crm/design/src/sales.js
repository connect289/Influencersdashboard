/* Sales app: counsellors. Phone-first; the desktop layout reuses the same screens with a sidebar. */
const SN = [
  ['today', 'Today', 'home'], ['leads', 'Leads', 'users'], ['followups', 'Follow-ups', 'cal'], ['inbox', 'Inbox', 'inbox'], ['me', 'Me', 'user'],
];
const myLeads = () => D.leads.filter(l => l.owner === D.me.id);
const go = (route, extra = {}) => { Object.assign(S.sales, { route }, extra); S.sheet = null; render(); };
A.go = v => go(v);
A.lead = v => { S.sales.back = S.sales.route === 'lead' ? S.sales.back : S.sales.route; go('lead', { lead: +v, leadTab: 'overview' }); };
A.back = () => go(S.sales.back || 'today');
A.fu = v => { S.sales.fu = v; render(); };
A.view = v => { S.sales.leadsView = v; render(); };
A.leadTab = v => { S.sales.leadTab = v; render(); };
A.meTab = v => { S.sales.meTab = v; render(); };
A.convo = v => { S.sales.convo = +v; S.sales.tplPick = null; if (S.sales.route !== 'inbox') S.sales.route = 'inbox'; render(); };
A.convoBack = () => { S.sales.convo = null; render(); };
A.tpl = v => { S.sales.tplPick = v; render(); };
A.sendTpl = () => { const c = D.conversations.find(c => c.lead === S.sales.convo); const t = D.salesTemplates.find(t => t.name === S.sales.tplPick); if (c && t) { c.msgs.push({ dir: 'out', tpl: t.name, text: fillTpl(t.text, D.lead(c.lead)), at: 'now', status: 'Sent' }); c.last = 'Sent: ' + t.name; } S.sales.tplPick = null; toast('Template sent from the Eduwit B2C number'); };
A.sendFree = () => { const box = document.getElementById('free-text'); const c = D.conversations.find(c => c.lead === S.sales.convo); if (c && box && box.value.trim()) { c.msgs.push({ dir: 'out', text: box.value.trim(), at: 'now', status: 'Sent' }); c.last = box.value.trim(); render(); } };
A.call = v => { S.sheet = { kind: 'dial', lead: +v }; render(); };
A.logCall = v => { S.sheet = { kind: 'log', lead: +v, outcome: null, next: null }; render(); };
A.outcome = v => { S.sheet.outcome = v; S.sheet.next = S.sheet.next || ({ 'No answer': 'In 3 hours', Busy: 'In 3 hours', 'Switched off': 'In 3 hours', 'Call back': 'Today 18:00', Connected: 'Tomorrow 10:00', 'Wrong number': null })[v]; render(); };
A.nextFu = v => { S.sheet.next = v; render(); };
A.saveLog = () => {
  const l = D.lead(S.sheet.lead); const o = S.sheet.outcome;
  if (['No answer', 'Busy', 'Switched off'].includes(o) && l.stage === 0) { l.stage = 1; l.sub = o; }
  if (o === 'Connected' && l.stage <= 1) { l.stage = 2; l.sub = 'Spoke briefly'; }
  l.sla = { kind: 'met' }; l.next = 'Follow-up call'; l.nextAt = S.sheet.next;
  (D.timeline[l.id] = D.timeline[l.id] || []).unshift({ t: '11:26', kind: 'call', text: `Call logged: ${o}, about 4 min. Next: ${S.sheet.next}.` });
  S.sheet = null; toast('Call logged. Syncs to the master lead table within 15 minutes');
};
A.stage = v => { const l = D.lead(v); S.sheet = { kind: 'stage', lead: +v, stage: l.stage < 0 ? 0 : l.stage, sub: null }; render(); };
A.pickStage = v => { S.sheet.stage = +v; S.sheet.sub = null; render(); };
A.pickSub = v => { S.sheet.sub = v; render(); };
A.saveStage = () => { const l = D.lead(S.sheet.lead); l.stage = S.sheet.stage; l.sub = S.sheet.sub; S.sheet = null; toast(`Stage saved: ${D.STAGES[l.stage].name} · ${l.sub}`); };
A.addContact = v => { S.sheet = { kind: 'contact', lead: +v }; render(); };
A.crossSell = v => { S.sheet = { kind: 'cross', lead: +v }; render(); };
A.filters = () => { S.sheet = { kind: 'viewbuilder' }; render(); };
A.newLead = () => { S.sheet = { kind: 'newlead' }; render(); };
A.lookup = () => { S.sheet.found = true; render(); };

const fillTpl = (t, l) => t.replace('{{first_name}}', l.name.split(' ')[0]).replace('{{counsellor}}', D.me.first).replace('{{programme}}', l.course).replace('{{university}}', l.uni || 'the university').replace('{{when}}', 'today at 4 pm').replace('{{documents}}', 'your 12th marksheet and a photo').replace('{{fee}}', '₹1,96,000').replace('{{emi}}', '₹8,166');

/* ---------- shells ---------- */
function salesApp() {
  const r = S.sales.route;
  if (r === 'lead') return `<div class="sales">${leadScreen(D.lead(S.sales.lead), 'phone')}</div>${sheet('phone')}`;
  if (r === 'inbox' && S.sales.convo) return `<div class="sales">${threadScreen('phone')}</div>${sheet('phone')}`;
  const [title, body, action] = salesScreen(r, 'phone');
  const nav = SN.map(([k, label, icn]) => `<button data-a="go" data-v="${k}" aria-current="${r === k || (k === 'leads' && ['pipeline', 'programmes'].includes(r)) || (k === 'me' && r === 'templates') ? 'page' : 'false'}">${ic(icn)}${label}${k === 'inbox' ? '<span class="badge-dot">1</span>' : k === 'followups' ? '<span class="badge-dot">3</span>' : ''}</button>`).join('');
  return `<div class="sales"><div class="s-head"><h1 class="grow">${title}</h1>${action || ''}</div><div class="s-body">${body}</div><nav class="bottom-nav" aria-label="Sales app">${nav}</nav></div>${sheet('phone')}`;
}
function salesDesk() {
  const r = S.sales.route;
  const items = [['today', 'Today', 'home'], ['leads', 'Leads', 'users'], ['pipeline', 'Pipeline', 'kanban'], ['followups', 'Follow-ups', 'cal'], ['inbox', 'Inbox', 'inbox'], ['programmes', 'Programmes', 'book'], ['me', 'Me', 'user']];
  const nav = items.map(([k, label, icn]) => `<button class="nav" data-a="go" data-v="${k}" aria-current="${r === k ? 'page' : 'false'}">${ic(icn)}${label}${k === 'followups' ? '<span class="count">3</span>' : k === 'inbox' ? '<span class="count">1</span>' : ''}</button>`).join('');
  let main;
  if (r === 'lead') main = `<div class="content">${leadScreen(D.lead(S.sales.lead), 'desk')}</div>`;
  else if (r === 'inbox') main = `<div class="topbar"><h1>Inbox</h1><span class="note">Your leads' WhatsApp on the Eduwit B2C number</span></div><div class="content">${inboxDesk()}</div>`;
  else { const [title, body, action] = salesScreen(r, 'desk'); main = `<div class="topbar"><h1>${title}</h1>${action || ''}</div><div class="content sales-desk">${body}</div>`; }
  return `<div class="desk-shell"><aside class="side"><div class="who"><span class="avatar">${D.me.initials}</span><div><b>${D.me.name}</b><div class="small muted">Counsellor · Working till 19:00</div></div></div>${nav}</aside><main class="main" style="position:relative">${main}</main></div>${sheet('desk')}`;
}

function salesScreen(r, mode) {
  switch (r) {
    case 'today': return ['Today', todayScreen(mode), `<span class="chip ok">${ic('check', 's')}Working</span>`];
    case 'leads': return ['Leads', leadsScreen(mode), `<button class="btn ghost sm" data-a="newLead">${ic('plus', 's')}New lead</button>`];
    case 'pipeline': return ['Pipeline', pipelineScreen(), ''];
    case 'followups': return ['Follow-ups', followupsScreen(mode), `<button class="btn quiet sm" data-a="toast" data-v="Calendar view: day and week">${ic('cal', 's')}Calendar</button>`];
    case 'inbox': return ['Inbox', inboxList(), ''];
    case 'programmes': return ['Programmes', programmesScreen(mode, false), ''];
    case 'me': return ['Me', meScreen(mode), ''];
    default: return ['Today', todayScreen(mode), ''];
  }
}

/* ---------- Today ---------- */
function todayScreen(mode) {
  const queue = [
    ['Overdue follow-up', 4799], ['New, not worked', 4766], ['New, not worked', 4812], ['Due today', 4807], ['Due today', 4790],
  ];
  const cards = queue.map(([why, id]) => {
    const l = D.lead(id);
    const breach = l.sla && l.sla.kind === 'breach';
    return `<div class="qcard ${breach ? 'breach' : ''}"><span class="avatar">${initials(l.name)}</span>
      <button class="grow plain" data-a="lead" data-v="${l.id}"><span class="name">${l.name}</span> ${tempChip(l.temp)}<div class="small muted ellipsis">${why} · ${l.course}</div></button>
      <button class="btn call sm" data-a="call" data-v="${l.id}" aria-label="Call ${l.name}">${ic('phone', 's')}Call</button>
      <div class="sub">${l.sla && l.sla.kind !== 'met' ? slaChip(l.sla) + ' ' : ''}${l.next} · ${l.nextAt}</div></div>`;
  }).join('');
  const k = [['Calls logged', 23, 40], ['Connected', 11, 20], ['Counselled', 4, 6]];
  const kpis = k.map(([n, v, t]) => `<div class="kpi"><span class="small muted">${n}</span><b>${v}<span class="muted" style="font-size:13px">/${t}</span></b><div class="bar-track"><div class="bar-fill ${v / t >= .5 ? '' : 'amber'}" style="width:${Math.min(100, v / t * 100)}%"></div></div></div>`).join('');
  const k2 = `<div class="kpis"><div class="kpi"><span class="small muted">Applications</span><b>1<span class="muted" style="font-size:13px">/2</span></b><div class="bar-track"><div class="bar-fill" style="width:50%"></div></div></div><div class="kpi"><span class="small muted">Enrolled (Oct)</span><b>4<span class="muted" style="font-size:13px">/6</span></b><div class="bar-track"><div class="bar-fill" style="width:66%"></div></div></div><div class="kpi"><span class="small muted">Owed to Eduwit</span><b style="font-size:15px">${inr(141300)}</b><span class="small muted">Oct, provisional</span></div></div>`;
  const fu = fuCards();
  const inner = `<div class="banner danger">${ic('alert')}<div><b>Neha Gupta re-engaged 27 min ago and has not been called.</b> First-contact SLA breached; the Admin has been alerted.</div></div>
    <div class="sec-title"><h2>Work next</h2><span class="note">In queue order</span></div><div class="stack" style="gap:8px">${cards}</div>
    <div class="sec-title"><h2>Follow-ups</h2><button class="btn quiet sm" data-a="go" data-v="followups">Open ${ic('next', 's')}</button></div>${fu}
    <div class="sec-title"><h2>Today against target</h2><span class="note">Wed 14 Oct</span></div><div class="kpis">${kpis}</div>${k2}`;
  if (mode === 'desk') return `<div class="grid g-lead"><div class="stack">${inner.split('<div class="sec-title"><h2>Follow-ups')[0]}</div><div class="stack"><div class="sec-title"><h2>Follow-ups</h2><button class="btn quiet sm" data-a="go" data-v="followups">Open ${ic('next', 's')}</button></div>${fu}<div class="sec-title"><h2>Today against target</h2></div><div class="kpis">${kpis}</div>${k2}</div></div>`;
  return `<p class="muted">Good morning, Priya. 2 new leads, 1 overdue follow-up.</p>${inner}`;
}
function fuCards(active) {
  const b = [['notworked', 'Not worked yet', 2], ['overdue', 'Overdue', 1], ['today', 'Due today', 3], ['upcoming', 'Upcoming', 3]];
  return `<div class="fu-cards">${b.map(([k, n, c]) => `<button class="fu-card ${k === 'overdue' || k === 'notworked' ? 'alert' : ''}" data-a="${active ? 'fu' : 'go'}" data-v="${active ? k : 'followups'}" ${active ? `aria-pressed="${active === k}"` : ''}><b>${c}</b><span>${n}</span></button>`).join('')}</div>`;
}

/* ---------- Leads ---------- */
function leadsScreen(mode) {
  const views = ['Due now', 'New for me', 'Hot', 'Applicants', 'Waiting for documents', 'All mine', 'Not worked yet'];
  const pick = S.sales.leadsView;
  let rows = myLeads();
  if (pick === 'Hot') rows = rows.filter(l => l.temp === 'hot');
  if (pick === 'Applicants') rows = rows.filter(l => l.stage === 6 || l.stage === 7);
  if (pick === 'New for me' || pick === 'Not worked yet') rows = rows.filter(l => l.stage === 0);
  if (pick === 'Due now') rows = rows.filter(l => l.sla.kind !== 'met' || l.overdue || l.id === 4807);
  if (pick === 'Waiting for documents') rows = rows.filter(l => l.id === 4786 || l.id === 4771);
  const pills = views.map(v => `<button class="pill" data-a="view" data-v="${v}" aria-pressed="${v === pick}">${v}</button>`).join('') + `<button class="pill" data-a="view" data-v="MBA hot from Meta" aria-pressed="${pick === 'MBA hot from Meta'}">★ MBA hot from Meta</button>`;
  const head = `<div class="row"><label class="search grow">${ic('search', 's')}<input id="lead-search" placeholder="Name, any phone, email, application ID" aria-label="Search leads"></label><button class="btn ghost sm" data-a="filters">${ic('sliders', 's')}Filters</button>${mode === 'phone' ? `<button class="btn ghost sm" data-a="go" data-v="pipeline" aria-label="Pipeline">${ic('kanban', 's')}</button>` : ''}</div><div class="hscroll">${pills}</div>`;
  if (mode === 'desk') {
    return `${head}<div class="table-wrap"><table><thead><tr><th>Student</th><th>Programme</th><th>Stage · sub-stage</th><th>Why with us</th><th>Next follow-up</th><th>SLA</th><th>Score</th><th></th></tr></thead><tbody>${rows.map(l => `<tr class="click" data-a="lead" data-v="${l.id}"><td><b>${l.name}</b><div class="small muted mono">${l.phone}</div></td><td>${l.course}<div class="small muted">${l.uni}</div></td><td>${stageName(l)}<div class="small muted">${l.sub}</div></td><td class="small">${l.reasonText} ${barChip(l)}</td><td class="small">${l.next}<div class="${l.overdue ? '' : 'muted'}">${l.nextAt}</div></td><td>${slaChip(l.sla)}</td><td class="num">${l.score} ${tempChip(l.temp)}</td><td><button class="btn call sm" data-a="call" data-v="${l.id}">${ic('phone', 's')}</button></td></tr>`).join('')}</tbody></table></div><p class="note">${rows.length} leads in "${pick}". Columns, sort, group-by and kanban come from the view; save it as your own or (Admin) publish it to everyone.</p>`;
  }
  return `${head}<div class="list">${rows.map(l => `<button class="li" data-a="lead" data-v="${l.id}"><span class="avatar">${initials(l.name)}</span><span class="t ellipsis">${l.name}</span><span>${tempChip(l.temp)}</span><span class="s">${stageName(l)} · ${l.sub} · next: ${l.nextAt}</span></button>`).join('') || '<p class="muted" style="padding:16px">No leads in this view.</p>'}</div><p class="note">${rows.length} of your ${myLeads().length} leads · swipe a row to call, WhatsApp or snooze</p>`;
}
function pipelineScreen() {
  const cols = D.STAGES.map((s, i) => {
    const ls = myLeads().filter(l => l.stage === i);
    const value = ls.reduce((a, l) => a + (D.programmes.find(p => p.name === l.course)?.owed || 0), 0);
    return `<section class="kcol"><header><span>${s.name}</span><span class="muted num">${ls.length}${value ? ' · ' + inr(value) : ''}</span></header>${ls.map(l => `<button class="kcard" data-a="lead" data-v="${l.id}"><b>${l.name}</b><span class="muted">${l.sub}</span><span class="row wrap" style="gap:4px">${tempChip(l.temp)}${l.sla.kind !== 'met' ? slaChip(l.sla) : ''}</span></button>`).join('')}</section>`;
  }).join('');
  return `<p class="note">Drag a card to change its stage; you are asked for the sub-stage, an optional comment and the next follow-up. Column value is the commission at stake.</p><div class="kanban">${cols}</div>`;
}

/* ---------- Follow-ups ---------- */
function followupsScreen(mode) {
  const k = S.sales.fu;
  const rows = D.followups.filter(f => f.bucket === k);
  const list = rows.map(f => { const l = D.lead(f.lead); return `<div class="li" style="grid-template-columns:auto 1fr auto"><span class="avatar">${ic(f.type === 'Call' ? 'phone' : f.type === 'WhatsApp' ? 'wa' : 'doc', 's')}</span><button class="plain" data-a="lead" data-v="${l.id}"><span class="t">${l.name}</span> <span class="small muted">· ${l.course}</span><div class="small muted">${f.note}</div></button><span class="num small ${k === 'overdue' || f.sla?.startsWith('Breached') ? '' : 'muted'}" style="${k === 'overdue' || f.sla?.startsWith('Breached') ? 'color:var(--red);font-weight:600' : ''}">${f.sla || f.when}</span><span class="s row" style="gap:6px;margin-top:6px"><button class="btn call sm" data-a="call" data-v="${l.id}">${ic('phone', 's')}Call</button><button class="btn ghost sm" data-a="convo" data-v="${l.id}">${ic('wa', 's')}</button><button class="btn ghost sm" data-a="logCall" data-v="${l.id}">${ic('check', 's')}Done</button><button class="btn quiet sm" data-a="toast" data-v="Snoozed 1 hour">Snooze</button></span></div>`; }).join('');
  const grouped = k === 'upcoming' ? `<p class="eyebrow">Thu 15 Oct and later</p>` : '';
  return `${fuCards(k)}${grouped}<div class="list">${list || '<p class="muted" style="padding:16px">Nothing here.</p>'}</div><div class="banner info">${ic('clock')}<div>Reminders arrive 10 minutes before each follow-up, with a link straight to the lead. Missed follow-ups go to the Admin after 2 hours.</div></div>`;
}

/* ---------- Inbox ---------- */
function inboxList() {
  return `<label class="search">${ic('search', 's')}<input placeholder="Name, number, text or template" aria-label="Search conversations"></label><div class="hscroll"><button class="pill" aria-pressed="true">All mine</button><button class="pill">Unread</button><button class="pill">Window open</button><button class="pill">Awaiting reply</button></div>
  <div class="list">${D.conversations.map(c => { const l = D.lead(c.lead); return `<button class="li" data-a="convo" data-v="${c.lead}"><span class="avatar">${initials(l.name)}</span><span class="t ellipsis">${l.name}</span><span class="small muted num">${c.at}</span><span class="s ellipsis">${c.unread ? '<b style="color:var(--ink)">● </b>' : ''}${esc(c.last)}</span><span class="s">${c.window.open ? `<span class="chip ok">Window open · ${c.window.left}</span>` : '<span class="chip soft">Template needed</span>'}</span></button>`; }).join('')}</div>`;
}
function threadBody() {
  const c = D.conversations.find(c => c.lead === S.sales.convo); const l = D.lead(c.lead);
  const msgs = c.msgs.map(m => `<div class="msg ${m.dir}">${m.tpl ? `<span class="tpl">Template · ${m.tpl}</span>` : ''}<span>${esc(m.text)}</span><span class="meta">${m.at}${m.status ? ' · ' + m.status : ''}</span></div>`).join('');
  let composer;
  if (c.window.open) composer = `<div class="window" style="color:var(--green)">${ic('clock', 's')}Free text allowed for ${c.window.left} (Sneha replied at 10:31)</div><div class="row"><input class="input grow" id="free-text" placeholder="Type a message" aria-label="Message"><button class="btn primary" data-a="sendFree" aria-label="Send">${ic('send', 's')}</button></div><div class="hscroll"><button class="pill" data-a="toast" data-v="Brochure attached from the Programme page">Brochure</button><button class="pill" data-a="toast" data-v="Comparison of 3 programmes attached">Comparison</button><button class="pill" data-a="toast" data-v="Snippet inserted">No-cost EMI snippet</button></div>`;
  else {
    const t = D.salesTemplates.map(t => `<button class="tpl-card" data-a="tpl" data-v="${t.name}" aria-pressed="${S.sales.tplPick === t.name}"><span class="row between"><b>${t.cat}</b><code>${t.name} · ${t.lang}</code></span><span class="small">${esc(fillTpl(t.text, l))}</span></button>`).join('');
    composer = `<div class="window" style="color:var(--amber-ink)">${ic('lock', 's')}The 24-hour window is closed. Start with an approved sales template.</div><div class="stack" style="gap:6px;max-height:230px;overflow-y:auto">${t}</div><button class="btn primary block" data-a="sendTpl" ${S.sales.tplPick ? '' : 'disabled'}>${ic('send', 's')}Send template</button>`;
  }
  return { c, l, msgs, composer };
}
function threadScreen() {
  const { l, msgs, composer } = threadBody();
  return `<div class="s-head"><button class="btn quiet sm" data-a="convoBack" aria-label="Back">${ic('back')}</button><div class="grow"><b>${l.name}</b><div class="small muted">${l.course} · ${stageName(l)}</div></div><button class="btn ghost sm" data-a="lead" data-v="${l.id}">Lead</button></div><div class="s-body"><div class="thread">${msgs}</div></div><div class="composer">${composer}</div>`;
}
function inboxDesk() {
  if (!S.sales.convo) S.sales.convo = D.conversations[0].lead;
  const { l, msgs, composer } = threadBody();
  return `<div class="grid" style="grid-template-columns:minmax(260px,340px) minmax(0,1fr);align-items:start"><div class="stack">${inboxList()}</div><div class="card" style="display:flex;flex-direction:column;min-height:520px"><div class="s-head"><div class="grow"><b>${l.name}</b><div class="small muted">${l.phone} · ${l.course} · ${stageName(l)}</div></div><button class="btn ghost sm" data-a="lead" data-v="${l.id}">Open lead</button></div><div class="s-body" style="flex:1"><div class="thread">${msgs}</div></div><div class="composer">${composer}</div></div></div>`;
}

/* ---------- Lead screen ---------- */
function leadScreen(l, mode) {
  const head = `<div class="lead-head">
    <div class="row"><span class="avatar lg">${initials(l.name)}</span><div class="grow"><h1 style="font-size:20px">${l.name}</h1><div class="small muted"><span class="mono">${l.phone}</span> · ${l.city} · ${l.lang}</div></div>${tempChip(l.temp)}<span class="chip line num">Score ${l.score}</span></div>
    <div class="row wrap" style="gap:6px"><button class="chip soft" style="border:0" data-a="stage" data-v="${l.id}">${stageName(l)} · ${l.sub} ▾</button>${slaChip(l.sla)}${barChip(l)}</div>
    <p class="small"><span class="muted">Why with us:</span> ${l.reasonText}</p>
    ${l.providers ? `<div class="banner">${ic('users')}<div><b>Already with other providers.</b> ${l.providers.map(p => `${p[0]} (since ${p[1]})`).join(' · ')}. Open with the neutral-adviser line: "Eduwit can help you compare options."</div></div>` : ''}
    <div class="lead-actions"><button class="btn call" data-a="call" data-v="${l.id}">${ic('phone')}Call</button><button class="btn ghost" data-a="convo" data-v="${l.id}">${ic('wa')}WhatsApp</button><button class="btn ghost" data-a="toast" data-v="Email opens from your own Gmail (priya@eduwit.in)">${ic('mail')}Email</button></div>
    <div class="row small"><span class="muted">Next:</span><b>${l.next}</b><span class="${l.overdue ? '' : 'muted'}" style="${l.overdue ? 'color:var(--red);font-weight:600' : ''}">${l.nextAt}</span></div></div>`;
  const brief = `<section class="brief"><div class="row between"><span class="eyebrow">Brief before you call</span><span class="small muted">${ic('spark', 's')} written by Claude · no phone or email sent</span></div><ul>
    <li>${l.exp.includes('years') ? 'Working professional' : 'Student'} (${l.exp}); ${l.qual}.</li>
    <li>Wants ${l.course}${l.spec ? ' (' + l.spec + ')' : ''}${l.uni && l.uni !== 'Any' ? ', looked at ' + l.uni : ''}; budget ${l.budget}; ${l.timeline}.</li>
    <li>${l.id === 4812 ? 'Told Witty she needs a weekend batch and asked about EMI twice.' : 'Asked about fees and EMI in the last chat.'}</li>
    ${l.providers ? '<li>Two partners already called her: do not pitch one university; compare options.</li>' : ''}</ul></section>`;
  const contacts = `<section class="panel"><header><h3>Contact details</h3><button class="btn quiet sm" data-a="addContact" data-v="${l.id}">${ic('plus', 's')}Add</button></header><div class="body">
    <div class="contact">${ic('phone', 's')}<span class="mono">${l.phone}</span><span class="row" style="gap:4px"><span class="chip ok">Primary call · WA</span>${ic('lock', 's')}</span><span class="lbl">WhatsApp number from intake · locked</span></div>
    ${l.email ? `<div class="contact">${ic('mail', 's')}<span class="ellipsis">${l.email}</span><span class="row" style="gap:4px"><span class="chip ok">Primary email</span>${ic('lock', 's')}</span><span class="lbl">From intake · locked</span></div>` : ''}
    ${l.id === 4812 ? `<div class="contact">${ic('phone', 's')}<span class="mono">+91 90000 00031</span><button class="btn quiet sm" data-a="toast" data-v="Set as primary for calls">Make primary</button><span class="lbl">Parent · added by Priya, 11:18</span></div>` : ''}
    <p class="note">You can add numbers and emails and choose the primary. Only the Admin can edit or delete one that exists.</p></div></section>`;
  const interest = `<section class="panel"><header><h3>Interest</h3><button class="btn quiet sm" data-a="crossSell" data-v="${l.id}">Change</button></header><div class="body"><dl class="kv"><dt>Programme</dt><dd>${l.course}${l.spec ? ' · ' + l.spec : ''}</dd><dt>University</dt><dd>${l.uni || '—'}</dd><dt>Level · mode</dt><dd>${l.level} · ${l.mode}</dd></dl></div></section>`;
  const profile = `<section class="panel"><header><h3>Profile</h3><button class="btn quiet sm" data-a="toast" data-v="Edits are kept in field history">Edit</button></header><div class="body"><dl class="kv"><dt>Education</dt><dd>${l.qual}</dd><dt>Experience</dt><dd>${l.exp}</dd><dt>Budget</dt><dd>${l.budget}</dd><dt>Timeline</dt><dd>${l.timeline}</dd><dt>Source</dt><dd>${l.source}${l.campaign && l.campaign !== '—' ? ' · ' + l.campaign : ''}</dd><dt>Assigned</dt><dd>${l.assigned}</dd></dl></div></section>`;
  const fit = D.programmes.filter(p => p.name === l.course || (l.course.includes('MBA') && p.name.includes('MBA'))).slice(0, 3);
  const fitP = `<section class="panel"><header><h3>Programme fit</h3><button class="btn quiet sm" data-a="toast" data-v="Comparison of ${fit.length} programmes sent on WhatsApp">Share comparison</button></header><div class="body">${fit.map(p => `<div class="row between small"><div class="grow"><b>${p.uni}</b> · ${p.name}<div class="muted">${p.elig} · ${p.dur} · ${p.intake}</div></div><div class="num" style="text-align:right">${inr(p.fee)}<div class="muted">EMI ${inr(p.emi)}/mo</div></div></div>`).join('<div class="divider"></div>') || '<p class="muted small">No programme matches yet.</p>'}</div></section>`;
  const tl = (D.timeline[l.id] || [{ t: 'Mon', kind: 'call', text: 'Call logged: no answer.' }, { t: 'Mon', kind: 'assign', text: 'Assigned to Priya by the catch-all rule (round robin).' }, { t: 'Mon', kind: 'handoff', text: 'Handed to B2C: ' + l.reasonText + '.' }]);
  const timeline = `<section class="panel"><header><h3>Timeline</h3><span class="small muted">All · calls · WhatsApp · email · Witty</span></header><div class="body"><div class="tl">${tl.map(t => `<div class="tl-item"><time>${t.t}</time><div><div class="tl-kind">${({ assign: 'Assignment', wa: 'WhatsApp', handoff: 'Hand-off', witty: 'Witty chat', source: 'Source', call: 'Call' })[t.kind] || t.kind}</div>${esc(t.text)}</div></div>`).join('')}</div></div></section>`;
  const apps = `<section class="panel"><header><h3>Applications</h3><button class="btn quiet sm" data-a="toast" data-v="Application form opened">${ic('plus', 's')}Add</button></header><div class="body">${l.appId ? `<div class="small"><b>${l.uni}</b> · ${l.course} · <span class="mono">${l.appId}</span></div><div class="pills"><span class="chip ok">${ic('check', 's')}Graduation marksheet</span><span class="chip ok">${ic('check', 's')}ID proof</span><span class="chip risk">12th marksheet</span><span class="chip risk">Photo</span></div>` : '<p class="muted small">No application yet. Recording one moves the lead to Applicant.</p>'}</div></section>`;
  const tasks = `<section class="panel"><header><h3>Tasks</h3><button class="btn quiet sm" data-a="toast" data-v="Follow-up added">${ic('plus', 's')}Add</button></header><div class="body small"><div class="row between"><span>${ic('phone', 's')} ${l.next}</span><span class="${l.overdue ? '' : 'muted'}">${l.nextAt}</span></div></div></section>`;
  const back = mode === 'phone' ? `<div class="s-head"><button class="btn quiet sm" data-a="back" aria-label="Back">${ic('back')}</button><span class="grow small muted">Lead #${l.id}</span><button class="btn quiet sm" data-a="toast" data-v="Hand back to the rules, with a reason">Hand back</button></div>` : `<div class="row"><button class="btn quiet sm" data-a="back">${ic('back', 's')}Back</button><span class="small muted">Lead #${l.id}</span></div>`;
  if (mode === 'desk') return `${back}<div class="grid g-lead"><div class="stack">${head}${brief}${l.script === 'neutral' ? '' : ''}<div class="grid g2">${contacts}${interest}</div>${fitP}${profile}${apps}</div><div class="stack">${tasks}${timeline}</div></div>`;
  const tabs = ['overview', 'timeline', 'applications', 'tasks'];
  const t = S.sales.leadTab;
  const body = t === 'timeline' ? timeline : t === 'applications' ? apps : t === 'tasks' ? tasks : `${brief}${contacts}${interest}${fitP}${profile}`;
  return `${back}<div class="s-body">${head}<div class="tabs" role="tablist">${tabs.map(x => `<button role="tab" aria-selected="${t === x}" data-a="leadTab" data-v="${x}">${x[0].toUpperCase() + x.slice(1)}</button>`).join('')}</div>${body}</div>`;
}

/* ---------- Programmes ---------- */
function programmesScreen(mode, admin) {
  const rows = D.programmes;
  const filters = `<div class="row wrap"><label class="search grow">${ic('search', 's')}<input placeholder="Programme, university, specialization" aria-label="Search programmes"></label></div><div class="hscroll"><button class="pill" aria-pressed="true">All levels</button><button class="pill">PG</button><button class="pill">UG</button><button class="pill">Online</button><button class="pill">Fee under ₹1.5 lakh</button><button class="pill">Intake this month</button><button class="pill">NAAC A++</button></div>`;
  if (mode === 'phone') return `${filters}<div class="list">${rows.map(p => `<div class="li"><span class="avatar">${ic('book', 's')}</span><span class="t ellipsis">${p.name}</span><span class="num small">${inr(p.fee)}</span><span class="s">${p.uni} · ${p.mode} · ${p.dur} · ${p.elig}</span></div>`).join('')}</div><p class="note">Read-only. From the shared catalogue maintained by the B2B CRM. "Suggest a correction" sends a note to the Admin.</p>`;
  return `${filters}<div class="table-wrap"><table><thead><tr><th></th><th>Programme</th><th>University</th><th>Mode · duration</th><th>Eligibility</th><th>Fee (total)</th><th>EMI</th><th>Intake</th>${admin ? '<th>Partners and rate</th><th>Counsellor owes</th>' : ''}</tr></thead><tbody>${rows.map((p, i) => `<tr><td><input type="checkbox" id="cmp-${i}" aria-label="Compare ${p.name}" ${i < 2 ? 'checked' : ''}></td><td><b>${p.name}</b><div class="small muted">${p.spec}</div></td><td>${p.uni}<div class="small muted">${p.acc}</div></td><td>${p.mode} · ${p.dur}</td><td class="small">${p.elig}</td><td class="num">${inr(p.fee)}</td><td class="num small">${inr(p.emi)}/mo</td><td class="small">${p.intake}</td>${admin ? `<td class="small">${p.rate}</td><td class="num">${p.owed == null ? '<span class="chip breach">Needs rate</span>' : inr(p.owed)}</td>` : ''}</tr>`).join('')}</tbody></table></div><div class="row"><button class="btn primary sm">Compare 2 selected</button><span class="note">Send the comparison or a brochure on WhatsApp or email in one tap. ${admin ? 'Partner rates and the counsellor commission are shown to Admin and Marketing only.' : 'Read-only, from the shared catalogue.'}</span></div>`;
}

/* ---------- Me ---------- */
function meScreen(mode) {
  const t = S.sales.meTab;
  const tabs = `<div class="tabs" role="tablist">${[['commission', 'Commission'], ['templates', 'Email templates'], ['guide', 'Guide'], ['settings', 'Settings']].map(([k, n]) => `<button role="tab" aria-selected="${t === k}" data-a="meTab" data-v="${k}">${n}</button>`).join('')}</div>`;
  let body;
  if (t === 'commission') {
    const tiles = [['Provisional', 141300, 'risk'], ['Confirmed', 35800, 'soft'], ['Due', 35280, 'warm'], ['Settled', 70560, 'ok']];
    body = `<p class="note">What you owe Eduwit for each enrolment you closed: the highest partner commission for that programme. Eduwit moves no money from here.</p><div class="grid g2" style="grid-template-columns:repeat(2,minmax(0,1fr))">${tiles.map(([n, v, c]) => `<div class="stat"><span class="chip ${c}" style="justify-self:start">${n}</span><b>${inr(v)}</b></div>`).join('')}</div>
    <div class="list">${[['Imran Qureshi', 'Amity Online · Online MBA', 35800, 'Highest of UpGrad 20%, Collegedunia 18% → 20% of ₹1,79,000', 'Confirmed'], ['Kavya Reddy', 'Jain Online · Online M.Com', 18700, 'Collegedunia 17% of ₹1,10,000', 'Provisional'], ['A. Banerjee', 'NMIMS CDOE · Online MBA', 35280, 'Highest of UpGrad 18%, Sunstone 16% → 18% of ₹1,96,000', 'Due 30 Oct'], ['R. Saxena', 'Manipal Online · Online MCA', 23700, 'No partner for the programme: highest university rate 15% (flagged)', 'Provisional']].map(r => `<div class="li"><span class="avatar">${initials(r[0])}</span><span class="t ellipsis">${r[0]}</span><span class="num">${inr(r[2])}</span><span class="s">${r[1]} · ${r[4]}</span><span class="s small">${r[3]}</span></div>`).join('')}</div><button class="btn ghost sm" data-a="toast" data-v="Statement for September downloaded">Download September statement</button>`;
  } else if (t === 'templates') {
    body = `<p class="note">Everyone's sales email templates are shared. Edit someone else's and you save your own copy; theirs never changes.</p><div class="list">${D.emailTemplates.map(e => `<div class="li"><span class="avatar">${ic(e.parent ? 'fork' : 'doc', 's')}</span><span class="t ellipsis">${e.name} ${e.rec ? '<span class="chip warm">Recommended</span>' : ''}</span><span class="num small muted">${e.reply}% reply</span><span class="s">${e.author}${e.parent ? ' · copy of "' + e.parent + '"' : ''} · ${e.cat} · used ${e.uses}×</span><span class="s row" style="gap:6px;margin-top:4px"><button class="btn ghost sm" data-a="toast" data-v="Template inserted into a new email">Use</button><button class="btn quiet sm" data-a="toast" data-v="${e.mine ? 'Editing your template' : 'Saved as your own copy; the original is unchanged'}">${e.mine ? 'Edit' : 'Edit as my copy'}</button></span></div>`).join('')}</div><button class="btn primary sm" data-a="toast" data-v="New template">${ic('plus', 's')}New template</button>`;
  } else if (t === 'guide') {
    body = `<div class="list">${['A day in the app', 'Today and Follow-ups', 'Calling and logging', 'WhatsApp templates and the 24-hour window', 'Email and sales templates', 'Stages and sub-stages', 'Cross-sell', 'Applications and documents', 'Recording an enrolment', 'Your commission'].map((g, i) => `<div class="li"><span class="avatar">${i < 3 ? ic('check', 's') : ic('book', 's')}</span><span class="t">${g}</span><span class="small muted">${i < 3 ? 'Read' : ''}</span></div>`).join('')}</div>`;
  } else {
    body = `<div class="panel"><header><h3>Availability</h3></header><div class="body"><div class="pills"><button class="pill" aria-pressed="true">Working</button><button class="pill">Away 30 min</button><button class="pill">Away rest of day</button></div><p class="note">Mon–Sat 10:00–19:00 IST · set by the Admin</p></div></div><div class="panel"><header><h3>Connections</h3></header><div class="body small"><div class="row between"><span>${ic('mail', 's')} Gmail priya@eduwit.in</span><span class="chip ok">Connected (company-wide)</span></div><div class="row between"><span>${ic('phone', 's')} Reminders on my WhatsApp</span><span class="chip soft">Off</span></div><div class="row between"><span>Push notifications</span><span class="chip ok">On</span></div></div></div>`;
  }
  return `<div class="row"><span class="avatar lg">${D.me.initials}</span><div><b>${D.me.name}</b><div class="small muted">priya@eduwit.in · Counsellor</div></div></div>${tabs}${body}`;
}

/* ---------- sheets ---------- */
function sheet(mode) {
  const sh = S.sheet; if (!sh) return '';
  const fixed = mode === 'desk' ? ' style="position:fixed"' : '';
  const center = mode === 'desk' ? ' center' : '';
  const wrap = inner => `<div class="scrim${center}"${fixed} data-a="scrim"><div class="sheet" role="dialog" aria-modal="true"><div class="grab"></div>${inner}</div></div>`;
  const l = sh.lead ? D.lead(sh.lead) : null;
  if (sh.kind === 'dial') {
    if (mode === 'phone') return wrap(`<div class="dialer"><span class="eyebrow">Opening your phone's dialler</span><span class="bignum">${l.phone}</span><span class="muted small">${l.name} · ${l.script === 'neutral' ? 'Opening line: "Eduwit can help you compare options."' : 'Standard opening'}</span><p class="note">Every tap on Call is logged. When you come back, the call log opens on its own.</p></div><button class="btn primary block" data-a="logCall" data-v="${l.id}">I'm back: log the call</button><button class="btn quiet block" data-a="close">Cancel</button>`);
    return wrap(`<div class="row between"><h2>Call ${l.name}</h2><button class="btn quiet sm" data-a="close" aria-label="Close">${ic('x')}</button></div><div class="row" style="gap:20px;align-items:center"><div class="grow dialer" style="justify-items:start;text-align:left"><span class="bignum">${l.phone}</span><button class="btn ghost sm" data-a="toast" data-v="Number copied">${ic('copy', 's')}Copy</button><p class="note">Scan to open the dialler on your phone. Counsellors call from their own phones; telephony comes later.</p></div>${qr()}</div><button class="btn primary block" data-a="logCall" data-v="${l.id}">Log the call</button>`);
  }
  if (sh.kind === 'log') {
    const outs = ['Connected', 'No answer', 'Busy', 'Switched off', 'Wrong number', 'Call back'];
    const auto = sh.outcome && ['No answer', 'Busy', 'Switched off'].includes(sh.outcome) && l.stage === 0 ? 'Stage moves New Lead → Could Not Connect' : sh.outcome === 'Connected' && l.stage <= 1 ? `Stage moves ${stageName(l)} → Contacted` : '';
    const nexts = ['In 3 hours', 'Today 18:00', 'Tomorrow 10:00', 'Pick date and time'];
    return wrap(`<div class="row between"><h2>Log call · ${l.name}</h2><button class="btn quiet sm" data-a="close" aria-label="Close">${ic('x')}</button></div>
      <div class="field"><span>Outcome</span><div class="pills">${outs.map(o => `<button class="pill" data-a="outcome" data-v="${o}" aria-pressed="${sh.outcome === o}">${o}</button>`).join('')}</div></div>
      <div class="field"><span>Talk time</span><div class="row"><input class="input num" id="talk" value="4 min" style="max-width:110px" aria-label="Talk time"><span class="note">Estimated from your time away (11:20 to 11:25)</span></div></div>
      <label class="field"><span>Notes</span><textarea class="input" id="call-notes" placeholder="What did you learn?">${l.id === 4812 ? 'Weekend batch confirmed. Comparing NMIMS and Amity; wants EMI under ₹8k.' : ''}</textarea></label>
      ${auto ? `<div class="banner info">${ic('next')}<div>${auto}</div></div>` : ''}
      <div class="field"><span>Next follow-up (required)</span><div class="pills">${nexts.map(n => `<button class="pill" data-a="nextFu" data-v="${n}" aria-pressed="${sh.next === n}">${n}</button>`).join('')}</div>${sh.outcome === 'No answer' ? '<p class="note">Suggested: retry in 3 hours. After 3 no-answers in 48 hours you will be offered a WhatsApp template.</p>' : ''}</div>
      <button class="btn primary block" data-a="saveLog" ${sh.outcome && sh.next ? '' : 'disabled'}>Save call log</button><p class="note">A tapped call with no log after 10 minutes shows "Call not logged" on the lead.</p>`);
  }
  if (sh.kind === 'stage') {
    const st = D.STAGES[sh.stage];
    return wrap(`<div class="row between"><h2>Change stage</h2><button class="btn quiet sm" data-a="close" aria-label="Close">${ic('x')}</button></div>
      <div class="field"><span>Stage</span><div class="pills">${D.STAGES.map((s, i) => `<button class="pill" data-a="pickStage" data-v="${i}" aria-pressed="${sh.stage === i}" ${i < l.stage && ![1, 4, 9].includes(i) ? 'disabled title="Backward moves need the Admin"' : ''}>${s.name}</button>`).join('')}</div></div>
      <div class="field"><span>Sub-stage (required)</span><div class="pills">${st.subs.map(s => `<button class="pill" data-a="pickSub" data-v="${esc(s)}" aria-pressed="${sh.sub === s}">${s}</button>`).join('')}</div></div>
      <label class="field"><span>Comment ${sh.stage === 9 && sh.sub === 'Other' ? '(required)' : '(optional)'}</span><textarea class="input" id="stage-comment" placeholder="Shown on the timeline"></textarea></label>
      ${sh.stage !== 8 && sh.stage !== 9 ? `<label class="field"><span>Next follow-up (required)</span><input class="input" id="stage-next" type="datetime-local" value="2026-10-15T10:30"></label>` : ''}
      ${sh.stage === 9 && sh.sub ? `<div class="banner info">${ic('flow')}<div>${['Wrong number', 'Junk or test', 'Enrolled elsewhere', 'Opted out'].includes(sh.sub) ? 'This lead closes and never returns to nurture.' : 'The lead returns to the Nurture Pool; its first nurture message goes out after the delay set for "' + sh.sub + '".'}</div></div>` : ''}
      <button class="btn primary block" data-a="saveStage" ${sh.sub ? '' : 'disabled'}>Save stage</button><p class="note">Counsellors see Eduwit's stages; the master lead table gets the matching canonical stage (${st.canon}).</p>`);
  }
  if (sh.kind === 'contact') return wrap(`<div class="row between"><h2>Add a contact detail</h2><button class="btn quiet sm" data-a="close" aria-label="Close">${ic('x')}</button></div><div class="pills"><button class="pill" aria-pressed="true">Phone</button><button class="pill">Email</button></div><label class="field"><span>Number</span><input class="input mono" id="new-phone" value="+91 90000 00031"></label><div class="field"><span>Label</span><div class="pills"><button class="pill">Alternate</button><button class="pill" aria-pressed="true">Parent</button><button class="pill">Office</button><button class="pill">WhatsApp only</button></div></div><div class="field"><span>Make primary for</span><div class="pills"><button class="pill">Calls</button><button class="pill">WhatsApp</button></div></div><div class="banner info">${ic('check')}<div>Checked against existing leads: no other student uses this number.</div></div><button class="btn primary block" data-a="close">Add number</button>`);
  if (sh.kind === 'cross') return wrap(`<div class="row between"><h2>Change interest</h2><button class="btn quiet sm" data-a="close" aria-label="Close">${ic('x')}</button></div><label class="field"><span>Programme</span><select class="input" id="x-prog"><option>${l.course}</option><option>Executive MBA</option><option>Online MBA (dual specialization)</option></select></label><label class="field"><span>University</span><select class="input" id="x-uni"><option>${l.uni || 'Any'}</option><option>Amity Online</option><option>NMIMS CDOE</option></select></label><label class="field"><span>Reason (required)</span><input class="input" id="x-reason" placeholder="e.g. 7 years' experience, Executive MBA fits better"></label><div class="banner info">${ic('lock')}<div>Recorded as a human correction. It never sends the lead to partners and reaches the master lead table in the next 15-minute sync.</div></div><button class="btn primary block" data-a="close">Save change</button>`);
  if (sh.kind === 'viewbuilder') return wrap(`<div class="row between"><h2>Build a view</h2><button class="btn quiet sm" data-a="close" aria-label="Close">${ic('x')}</button></div>
    <div class="card pad stack" style="gap:8px"><span class="eyebrow">All of</span>
    ${[['Programme', 'contains', 'MBA'], ['Source', 'is', 'Meta lead form'], ['Temperature', 'is', 'Hot']].map(r => `<div class="row wrap" style="gap:6px"><span class="chip soft">${r[0]}</span><span class="small muted">${r[1]}</span><span class="chip line">${r[2]}</span></div>`).join('')}
    <span class="eyebrow">Any of</span><div class="row wrap" style="gap:6px"><span class="chip soft">Last contacted</span><span class="small muted">more than</span><span class="chip line">2 days ago</span></div><div class="row wrap" style="gap:6px"><span class="chip soft">Follow-up</span><span class="small muted">is</span><span class="chip line">Overdue</span></div>
    <button class="btn quiet sm" style="justify-self:start">${ic('plus', 's')}Add condition</button></div>
    <div class="field"><span>Show as</span><div class="pills"><button class="pill" aria-pressed="true">List</button><button class="pill">Kanban</button></div></div>
    <label class="field"><span>Name</span><input class="input" id="view-name" value="MBA hot from Meta"></label><div class="row"><button class="btn primary grow" data-a="close">Save view</button><button class="btn ghost" data-a="close">Apply once</button></div>`);
  if (sh.kind === 'newlead') return wrap(`<div class="row between"><h2>New lead</h2><button class="btn quiet sm" data-a="close" aria-label="Close">${ic('x')}</button></div><p class="note">Phone first: we check it isn't already someone's lead.</p><div class="row"><input class="input mono grow" id="nl-phone" value="+91 90000 00044" aria-label="Phone"><button class="btn primary" data-a="lookup">Check</button></div>${sh.found ? `<div class="banner">${ic('users')}<div><b>Already with UpGrad since 2 Sep 2026.</b> Nothing is created. Only the Admin can act on it, through the B2B CRM.</div></div>` : ''}`);
  if (sh.kind === 'cmdk') return wrap(`<label class="search">${ic('search', 's')}<input id="cmdk" placeholder="Search leads, people, settings…" autofocus></label><div class="list">${['Go to Lead Allocation', 'Open lead: Asha Verma', 'View as Sales', 'Create journey', 'Export current view', 'Settings › Stages and sub-stages'].map(x => `<button class="li" data-a="close"><span class="avatar">${ic('next', 's')}</span><span class="t">${x}</span></button>`).join('')}</div>`);
  return '';
}
A.scrim = (v, el, e) => { if (e.target === el) { S.sheet = null; render(); } };
function qr() {
  // stand-in for the real code, which encodes tel:+919000000012
  const finder = (x, y) => { const m = Math.max(Math.abs(x - 3), Math.abs(y - 3)); return m === 3 || m <= 1; };
  let s = ''; let seed = 7;
  for (let y = 0; y < 21; y++) for (let x = 0; x < 21; x++) {
    seed = (seed * 9301 + 49297) % 233280;
    let on;
    if (x < 7 && y < 7) on = finder(x, y); else if (x > 13 && y < 7) on = finder(x - 14, y); else if (x < 7 && y > 13) on = finder(x, y - 14);
    else if (x < 8 && y < 8 || x > 12 && y < 8 || x < 8 && y > 12) on = false; else on = seed / 233280 > .5;
    if (on) s += `<rect x="${x}" y="${y}" width="1" height="1"/>`;
  }
  return `<svg class="qr" viewBox="0 0 21 21" fill="#072E5A" aria-label="QR code to dial on your phone">${s}</svg>`;
}
