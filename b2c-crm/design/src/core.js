/* Core: state, icons, helpers, shell and events. Screens live in sales.js and workspace.js. */
const S = {
  iface: 'sales', device: 'phone', theme: 'system',
  sales: { route: 'today', lead: null, back: null, fu: 'notworked', convo: null, tplPick: null, leadsView: 'Due now', leadTab: 'overview', meTab: 'commission' },
  ws: { marketing: 'nurture', admin: 'home', journey: null, lead: null, tab: {} },
  sheet: null, toast: null,
};
const IFACES = { sales: 'Sales app', marketing: 'Marketing workspace', admin: 'Admin console' };

const ICON = {
  home: '<path d="M3 11l9-7 9 7"/><path d="M5 10v10h14V10"/>',
  users: '<circle cx="9" cy="8" r="3.2"/><path d="M3 20c0-3.3 2.7-6 6-6s6 2.7 6 6"/><path d="M16 4.5a3.2 3.2 0 0 1 0 6.4M18 14.5c2 .8 3 3 3 5.5"/>',
  cal: '<rect x="3.5" y="5" width="17" height="15.5" rx="2"/><path d="M3.5 10h17M8 3v4M16 3v4"/>',
  inbox: '<path d="M4 13l2.5-8h11L20 13v6H4z"/><path d="M4 13h4.5l1 2h5l1-2H20"/>',
  user: '<circle cx="12" cy="8" r="3.5"/><path d="M5 20c0-3.9 3.1-7 7-7s7 3.1 7 7"/>',
  phone: '<path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2"/>',
  wa: '<path d="M4 20l1.3-3.9A8 8 0 1 1 8 19z"/><path d="M9 9.5c.5 2.5 2.5 4.5 5 5"/>',
  mail: '<rect x="3" y="5" width="18" height="14" rx="2"/><path d="M3.5 6l8.5 7 8.5-7"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.3-4.3"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  back: '<path d="M15 5l-7 7 7 7"/>',
  next: '<path d="M9 5l7 7-7 7"/>',
  check: '<path d="M5 12.5l4.5 4.5L19 7.5"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  alert: '<path d="M12 3.5L2.5 20h19z"/><path d="M12 10v4.5M12 17.5v.01"/>',
  kanban: '<rect x="3.5" y="4" width="5" height="16" rx="1.2"/><rect x="10" y="4" width="5" height="10" rx="1.2"/><rect x="16.5" y="4" width="4" height="13" rx="1.2"/>',
  book: '<path d="M4 5.5A2.5 2.5 0 0 1 6.5 3H20v15H6.5A2.5 2.5 0 0 0 4 20.5z"/><path d="M4 20.5A2.5 2.5 0 0 0 6.5 23H20v-5"/>',
  spark: '<path d="M12 3l1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="M19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z"/>',
  sliders: '<path d="M4 6h10M18 6h2M4 12h4M12 12h8M4 18h12M20 18h0"/><circle cx="16" cy="6" r="2"/><circle cx="10" cy="12" r="2"/><circle cx="18" cy="18" r="2"/>',
  gear: '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.6 1.6 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.6 1.6 0 0 0-2.7 1.1V21a2 2 0 1 1-4 0v-.1a1.6 1.6 0 0 0-2.7-1.1l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1A1.6 1.6 0 0 0 3.6 15H3.5a2 2 0 1 1 0-4h.1a1.6 1.6 0 0 0 1.1-2.7l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.6 1.6 0 0 0 2.7-1.1V3.5a2 2 0 1 1 4 0v.1a1.6 1.6 0 0 0 2.7 1.1l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.6 1.6 0 0 0 1.1 2.7h.1a2 2 0 1 1 0 4h-.1a1.6 1.6 0 0 0-1.4.8z"/>',
  rupee: '<path d="M7 4h11M7 9h11M7 4c6 0 6 9 0 9h-.5L15 21"/>',
  chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  plug: '<path d="M9 3v5M15 3v5M6 8h12v3a6 6 0 0 1-12 0zM12 17v4"/>',
  flow: '<circle cx="6" cy="5" r="2.2"/><circle cx="6" cy="19" r="2.2"/><circle cx="18" cy="12" r="2.2"/><path d="M6 7.2v9.6M8 6c6 0 8 2 8 4M8 18c6 0 8-2 8-4"/>',
  doc: '<path d="M6 3h8l4 4v14H6z"/><path d="M14 3v4h4M9 12h6M9 16h6"/>',
  mega: '<path d="M3 10v4h3l7 4V6L6 10z"/><path d="M16.5 9a4 4 0 0 1 0 6M19 6.5a7.5 7.5 0 0 1 0 11"/>',
  target: '<circle cx="12" cy="12" r="8.5"/><circle cx="12" cy="12" r="4.5"/><circle cx="12" cy="12" r=".8"/>',
  shuffle: '<path d="M3 7h3.5c5 0 6 10 11 10H21M3 17h3.5c2 0 3.3-1.6 4.3-3.6M15 7h6M18 4l3 3-3 3M18 14l3 3-3 3"/>',
  leaf: '<path d="M5 19c0-8 6-14 15-14 0 9-6 15-14 15"/><path d="M5 19l7-7"/>',
  x: '<path d="M6 6l12 12M18 6L6 18"/>',
  lock: '<rect x="5" y="11" width="14" height="9.5" rx="2"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/>',
  star: '<path d="M12 3.5l2.6 5.4 5.9.8-4.3 4.1 1 5.8L12 16.9l-5.2 2.7 1-5.8-4.3-4.1 5.9-.8z"/>',
  eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="2.8"/>',
  pin: '<path d="M12 21s-6.5-5.4-6.5-11a6.5 6.5 0 0 1 13 0C18.5 15.6 12 21 12 21z"/><circle cx="12" cy="10" r="2.3"/>',
  copy: '<rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V5a1 1 0 0 0-1-1H5a1 1 0 0 0-1 1v10a1 1 0 0 0 1 1h3"/>',
  fork: '<circle cx="6" cy="5" r="2"/><circle cx="18" cy="5" r="2"/><circle cx="12" cy="19" r="2"/><path d="M6 7v2a3 3 0 0 0 3 3h6a3 3 0 0 0 3-3V7M12 12v5"/>',
  send: '<path d="M21 3L10 14M21 3l-7 18-4-7-7-4z"/>',
  more: '<circle cx="5" cy="12" r="1.2"/><circle cx="12" cy="12" r="1.2"/><circle cx="19" cy="12" r="1.2"/>',
  sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2.5v2M12 19.5v2M2.5 12h2M19.5 12h2M5.3 5.3l1.4 1.4M17.3 17.3l1.4 1.4M5.3 18.7l1.4-1.4M17.3 6.7l1.4-1.4"/>',
  moon: '<path d="M20 14.5A8 8 0 1 1 9.5 4a6.5 6.5 0 0 0 10.5 10.5z"/>',
  monitor: '<rect x="3" y="4" width="18" height="12" rx="2"/><path d="M8 20h8M12 16v4"/>',
  mobile: '<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>',
};
const ic = (n, cls = '') => `<svg class="icon ${cls}" viewBox="0 0 24 24" aria-hidden="true">${ICON[n] || ''}</svg>`;
const LOGO = `<svg class="logo" viewBox="0 0 32 32" aria-hidden="true"><path d="M16 4a8 8 0 0 0-5 14.2V22h5z" fill="#072E5A"/><path d="M16 4a8 8 0 0 1 5 14.2V22h-5z" fill="#F4A504"/><path d="M5 17l5 4h6v6l-6-2.5L5 26z" fill="#072E5A"/><path d="M27 17l-5 4h-6v6l6-2.5 5 1.5z" fill="#F4A504"/></svg>`;
const esc = s => String(s ?? '').replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const inr = n => n == null ? '—' : '₹' + Math.round(n).toLocaleString('en-IN');
const initials = n => n.split(' ').map(x => x[0]).slice(0, 2).join('');
const tempChip = t => t ? `<span class="chip ${t}">${t === 'hot' ? 'Hot' : t === 'warm' ? 'Warm' : 'Cold'}</span>` : '';
const slaChip = s => !s ? '' : s.kind === 'breach' ? `<span class="chip breach">${ic('alert', 's')}SLA breached ${s.mins} min</span>` : s.kind === 'due' ? `<span class="chip risk">${ic('clock', 's')}${s.mins} min left</span>` : `<span class="chip ok">${ic('check', 's')}SLA met</span>`;
const stageName = l => l.stage < 0 ? 'Nurture' : D.STAGES[l.stage].name;
const barChip = l => l.barred ? `<span class="chip bar" title="Never routed to a partner again">${ic('lock', 's')}Partner-barred</span>` : '';

function toast(msg) { S.toast = msg; render(); clearTimeout(toast.t); toast.t = setTimeout(() => { S.toast = null; render(); }, 2600); }

function protoBar() {
  const segs = Object.entries(IFACES).map(([k, v]) => `<button data-a="iface" data-v="${k}" aria-pressed="${S.iface === k}">${v}</button>`).join('');
  const device = S.iface === 'sales' ? `<div class="seg" role="group" aria-label="Width"><button data-a="device" data-v="phone" aria-pressed="${S.device === 'phone'}">${ic('mobile', 's')} Phone</button><button data-a="device" data-v="desktop" aria-pressed="${S.device === 'desktop'}">${ic('monitor', 's')} Desktop</button></div>` : '';
  const theme = `<div class="seg" role="group" aria-label="Theme"><button data-a="theme" data-v="light" aria-pressed="${S.theme === 'light'}" title="Light">${ic('sun', 's')}</button><button data-a="theme" data-v="system" aria-pressed="${S.theme === 'system'}" title="System">Auto</button><button data-a="theme" data-v="dark" aria-pressed="${S.theme === 'dark'}" title="Dark">${ic('moon', 's')}</button></div>`;
  return `<div class="proto"><div class="brand">${LOGO}<span>Eduwit B2C CRM <small>· clickable design</small></span></div>
    <div class="seg" role="group" aria-label="Interface">${segs}</div>${device}${theme}<span class="sample">Sample data</span></div>`;
}

function render() {
  const root = document.documentElement;
  if (S.theme === 'system') root.removeAttribute('data-theme'); else root.setAttribute('data-theme', S.theme);
  let body;
  if (S.iface === 'sales') body = S.device === 'phone' ? `<div class="stage"><div class="phone">${phoneStatus()}${salesApp()}</div></div>` : `<div class="stage desk">${salesDesk()}</div>`;
  else body = `<div class="stage desk">${workspace(S.iface)}</div>`;
  document.getElementById('app').innerHTML = protoBar() + body + (S.toast ? `<div class="toast" role="status">${esc(S.toast)}</div>` : '');
}
const phoneStatus = () => `<div class="statusbar"><span>11:20</span><span>4G ▮▮▮</span></div>`;

/* ---------- events ---------- */
const A = {};
document.addEventListener('click', e => {
  const el = e.target.closest('[data-a]');
  if (!el) return;
  const fn = A[el.dataset.a];
  if (fn) { e.preventDefault(); fn(el.dataset.v, el, e); }
});
document.addEventListener('keydown', e => {
  if (e.key === 'Escape' && S.sheet) { S.sheet = null; render(); }
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k' && S.iface === 'admin') { e.preventDefault(); S.sheet = { kind: 'cmdk' }; render(); }
});
A.iface = v => { S.iface = v; S.sheet = null; render(); };
A.device = v => { S.device = v; render(); };
A.theme = v => { S.theme = v; try { localStorage.setItem('b2c-proto-theme', v); } catch (_) {} render(); };
A.close = () => { S.sheet = null; render(); };
A.toast = v => toast(v);
A.noop = () => {};
try { const t = localStorage.getItem('b2c-proto-theme'); if (t) S.theme = t; } catch (_) {}

/* tiny charts, drawn to scale */
function lineChart(series, { w = 520, h = 160, labels = [], max } = {}) {
  const pad = { l: 30, r: 10, t: 10, b: 22 };
  const all = series.flatMap(s => s.data); const top = max ?? (Math.ceil(Math.max(...all) / 10) * 10 || 10);
  const x = i => pad.l + i * (w - pad.l - pad.r) / (series[0].data.length - 1);
  const y = v => pad.t + (h - pad.t - pad.b) * (1 - v / top);
  const ticks = [0, top / 2, top];
  let g = ticks.map(t => `<line class="gridl" x1="${pad.l}" x2="${w - pad.r}" y1="${y(t)}" y2="${y(t)}"/><text x="${pad.l - 6}" y="${y(t) + 3}" text-anchor="end">${t}</text>`).join('');
  g += labels.map((l, i) => l ? `<text x="${x(i)}" y="${h - 6}" text-anchor="middle">${l}</text>` : '').join('');
  const paths = series.map(s => {
    const pts = s.data.map((v, i) => `${x(i).toFixed(1)},${y(v).toFixed(1)}`).join(' ');
    const last = s.data.length - 1;
    const area = s.area ? `<polygon points="${x(0)},${y(0)} ${pts} ${x(last)},${y(0)}" fill="${s.color}" opacity=".10"/>` : '';
    return `${area}<polyline points="${pts}" fill="none" stroke="${s.color}" stroke-width="2" stroke-linejoin="round"/><circle cx="${x(last)}" cy="${y(s.data[last])}" r="3.2" fill="${s.color}"/>`;
  }).join('');
  return `<svg class="chart" viewBox="0 0 ${w} ${h}" width="100%" role="img">${g}${paths}</svg>`;
}
function barsChart(rows, { w = 520, h = 170, color = 'var(--primary)' } = {}) {
  const pad = { l: 30, r: 8, t: 10, b: 22 }; const top = Math.ceil(Math.max(...rows.map(r => r[1])) / 10) * 10 || 10;
  const bw = (w - pad.l - pad.r) / rows.length; const y = v => pad.t + (h - pad.t - pad.b) * (1 - v / top);
  let g = [0, top / 2, top].map(t => `<line class="gridl" x1="${pad.l}" x2="${w - pad.r}" y1="${y(t)}" y2="${y(t)}"/><text x="${pad.l - 6}" y="${y(t) + 3}" text-anchor="end">${t}</text>`).join('');
  g += rows.map((r, i) => `<rect x="${pad.l + i * bw + bw * .18}" y="${y(r[1])}" width="${bw * .64}" height="${y(0) - y(r[1])}" rx="3" fill="${r[2] || color}"/><text x="${pad.l + i * bw + bw / 2}" y="${h - 6}" text-anchor="middle">${r[0]}</text>`).join('');
  return `<svg class="chart" viewBox="0 0 ${w} ${h}" width="100%" role="img">${g}</svg>`;
}
