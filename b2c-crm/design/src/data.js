/* Sample data for the clickable design. Every person, number and amount here is invented.
   Phones use the test range 91 90000 000NN, which Eduwit never messages. */
const D = (() => {
  const now = new Date('2026-10-14T11:20:00+05:30');
  const counsellors = [
    { id: 'u1', name: 'Priya Sharma', first: 'Priya', initials: 'PS', role: 'Counsellor', langs: ['English', 'Hindi'], skills: ['MBA', 'Executive MBA'], status: 'Working', open: 38, month: 61, cap: 200, enrol: 4, target: 6, calls: 23, connected: 11 },
    { id: 'u2', name: 'Rohan Mehta', first: 'Rohan', initials: 'RM', role: 'Counsellor', langs: ['English', 'Hindi', 'Marathi'], skills: ['MCA', 'BCA'], status: 'Working', open: 31, month: 54, cap: 200, enrol: 3, target: 6, calls: 19, connected: 8 },
    { id: 'u3', name: 'Ankit Verma', first: 'Ankit', initials: 'AV', role: 'Counsellor', langs: ['English', 'Hindi'], skills: ['BBA', 'B.Com'], status: 'Away 30 min', open: 27, month: 47, cap: 200, enrol: 2, target: 5, calls: 14, connected: 5 },
    { id: 'u4', name: 'Fatima Khan', first: 'Fatima', initials: 'FK', role: 'Counsellor', langs: ['English', 'Urdu', 'Hindi'], skills: ['M.Com', 'MBA'], status: 'On leave till 16 Oct', open: 0, month: 22, cap: 200, enrol: 1, target: 5, calls: 0, connected: 0 },
  ];
  const me = counsellors[0];

  // stage index into STAGES
  const leads = [
    { id: 4812, name: 'Asha Verma', phone: '+91 90000 00012', email: 'asha.v@example.in', city: 'Pune', lang: 'Hindi', course: 'Online MBA', spec: 'Finance', uni: 'NMIMS CDOE', level: 'PG', mode: 'Online', stage: 0, sub: 'Fresh assignment', temp: 'hot', score: 72, lane: 'sales', reason: 'duplicate_cascade', reasonText: 'Duplicate at UpGrad and Sunstone', barred: 'duplicate', providers: [['UpGrad', '28 Aug 2026'], ['Sunstone', 'date not given']], owner: 'u1', sla: { kind: 'due', mins: 6 }, next: 'First call', nextAt: 'Now', assigned: '11:14', source: 'Meta lead form', campaign: 'Oct MBA · Lead form', qual: 'B.Com, 68%', exp: '3 years, accounts executive', budget: '₹1.2–1.6 lakh a year', timeline: 'Jan 2027 intake', script: 'neutral' },
    { id: 4807, name: 'Rahul Kulkarni', phone: '+91 90000 00014', email: 'rahul.k@example.in', city: 'Nagpur', lang: 'Marathi', course: 'Online MCA', spec: 'Data Science', uni: 'Manipal Online', level: 'PG', mode: 'Online', stage: 1, sub: 'No answer', temp: 'warm', score: 48, lane: 'sales', reason: 'no_partner_offers_programme', reasonText: 'No partner offers this programme', owner: 'u1', sla: { kind: 'met' }, next: 'Call back', nextAt: '12:30', assigned: 'Yesterday', source: 'Witty (WhatsApp)', campaign: '—', qual: 'B.Sc IT, 61%', exp: 'Fresher', budget: 'Up to ₹1 lakh a year', timeline: 'Within 3 months', script: 'standard', attempts: 2 },
    { id: 4799, name: 'Sneha Iyer', phone: '+91 90000 00015', email: 'sneha.iyer@example.in', city: 'Chennai', lang: 'English', course: 'Executive MBA', spec: 'Marketing', uni: 'IIM Kozhikode (EP)', level: 'PG', mode: 'Blended', stage: 4, sub: 'Awaiting parent decision', temp: 'hot', score: 81, lane: 'sales', reason: 'no_partner_consent', reasonText: 'Said no to partner sharing', owner: 'u1', sla: { kind: 'met' }, next: 'Follow-up call', nextAt: 'Overdue 25 min', overdue: true, assigned: '9 Oct', source: 'Website form', campaign: 'Google · Exec MBA', qual: 'B.E., 74%', exp: '7 years, brand manager', budget: '₹3–4 lakh total', timeline: 'Next intake', script: 'standard' },
    { id: 4790, name: 'Mohit Bansal', phone: '+91 90000 00016', email: 'mohit.b@example.in', city: 'Jaipur', lang: 'Hindi', course: 'Online BBA', spec: 'General', uni: 'Amity Online', level: 'UG', mode: 'Online', stage: 2, sub: 'Spoke briefly', temp: 'warm', score: 55, lane: 'sales', reason: 'partners_unreachable', reasonText: '3 partners tried, none reachable', owner: 'u1', sla: { kind: 'met' }, next: 'WhatsApp brochure', nextAt: '14:00', assigned: '12 Oct', source: 'Google search ad', campaign: 'BBA · Search', qual: '12th, 71%', exp: 'Fresher', budget: '₹60k a year', timeline: 'This year', script: 'standard' },
    { id: 4786, name: 'Kavya Reddy', phone: '+91 90000 00017', email: 'kavya.r@example.in', city: 'Hyderabad', lang: 'English', course: 'Online M.Com', spec: 'Accounting', uni: 'Jain Online', level: 'PG', mode: 'Online', stage: 6, sub: 'Application submitted', temp: 'hot', score: 77, lane: 'sales', reason: 'b2c_created', reasonText: 'Created by Priya (walk-in)', owner: 'u1', sla: { kind: 'met' }, next: 'Document chase', nextAt: '16:00', assigned: '2 Oct', source: 'Walk-in', campaign: '—', qual: 'B.Com, 66%', exp: '1 year', budget: '₹80k total', timeline: 'Oct 2026 intake', script: 'standard', appId: 'JAIN-OL-24-55871' },
    { id: 4771, name: 'Imran Qureshi', phone: '+91 90000 00018', email: 'imran.q@example.in', city: 'Lucknow', lang: 'Urdu', course: 'Online MBA', spec: 'HR', uni: 'Amity Online', level: 'PG', mode: 'Online', stage: 8, sub: 'Fee paid (full)', temp: 'hot', score: 90, lane: 'sales', reason: 'duplicate_cascade', reasonText: 'Duplicate at UpGrad', barred: 'duplicate', owner: 'u1', sla: { kind: 'met' }, next: 'Upload fee receipt', nextAt: 'Tomorrow 11:00', assigned: '24 Sep', source: 'Meta lead form', campaign: 'Sep MBA', qual: 'BBA, 63%', exp: '4 years', budget: '₹1.8 lakh total', timeline: 'Oct 2026', script: 'neutral' },
    { id: 4766, name: 'Neha Gupta', phone: '+91 90000 00019', email: 'neha.g@example.in', city: 'Delhi', lang: 'Hindi', course: 'Online MBA', spec: 'Operations', uni: 'Any', level: 'PG', mode: 'Online', stage: 0, sub: 'Re-engaged from nurture', temp: 'hot', score: 64, lane: 'sales', reason: 'reengaged', reasonText: 'Lost by Sunstone: over budget · re-engaged (tapped "Yes, call me")', barred: 'lost', owner: 'u1', sla: { kind: 'breach', mins: 12 }, next: 'First call', nextAt: 'Breached', assigned: '10:53', source: 'Meta lead form', campaign: 'Aug MBA', qual: 'B.A., 58%', exp: '2 years, retail', budget: 'Under ₹1 lakh', timeline: 'Undecided', script: 'standard' },
    { id: 4752, name: 'Arjun Nair', phone: '+91 90000 00020', email: 'arjun.n@example.in', city: 'Kochi', lang: 'English', course: 'Online MCA', spec: 'Cloud', uni: 'LPU Online', level: 'PG', mode: 'Online', stage: 5, sub: 'Fee and EMI explained', temp: 'warm', score: 59, lane: 'sales', reason: 'no_capacity', reasonText: 'Partners at capacity', owner: 'u1', sla: { kind: 'met' }, next: 'Comparison follow-up', nextAt: 'Tomorrow 10:30', assigned: '7 Oct', source: 'Witty (WhatsApp)', campaign: '—', qual: 'BCA, 70%', exp: '2 years, support', budget: '₹1.5 lakh total', timeline: 'Jan 2027', script: 'standard' },
    { id: 4733, name: 'Pooja Singh', phone: '+91 90000 00021', email: 'pooja.s@example.in', city: 'Patna', lang: 'Hindi', course: 'Online BCA', spec: 'General', uni: 'Manipal Online', level: 'UG', mode: 'Online', stage: 9, sub: "Can't afford fee or EMI", temp: 'cold', score: 22, lane: 'sales', reason: 'no_partner_offers_programme', reasonText: 'No partner offers this programme', owner: 'u1', sla: { kind: 'met' }, next: '—', nextAt: '—', assigned: '20 Sep', source: 'Website form', campaign: '—', qual: '12th, 55%', exp: 'Fresher', budget: 'Under ₹40k', timeline: 'Later', script: 'standard' },
    // Pool (nurture) leads, seen by Admin and Marketing
    { id: 4840, name: 'Vikram Joshi', phone: '+91 90000 00022', email: '', city: 'Indore', lang: 'Hindi', course: '—', spec: '', uni: '', level: '', mode: '', stage: -1, sub: 'Qualifying', temp: 'cold', score: 18, lane: 'nurture', reason: 'not_qualified', reasonText: 'Missing course and email', missing: ['Course', 'Email'], owner: null, journey: 'Qualify: missing details · step 2 of 5', lastMsg: 'explore_programmes · Read', lastAct: 'Witty chat, 2 days ago', source: 'Witty (WhatsApp)', pool: '2 days' },
    { id: 4828, name: 'Ritika Das', phone: '+91 90000 00023', email: 'ritika.d@example.in', city: 'Kolkata', lang: 'English', course: 'Online MBA', spec: 'Finance', uni: '', level: 'PG', mode: 'Online', stage: -1, sub: 'Partner-lost', temp: 'warm', score: 41, lane: 'nurture', reason: 'partner_lost', reasonText: 'Lost by UpGrad: over budget', barred: 'lost', owner: null, journey: 'Fee concern · waits until 21 Oct', lastMsg: '—', lastAct: 'UpGrad call, 9 Oct', source: 'Meta lead form', pool: '6 days' },
    { id: 4815, name: 'Sanjay Patil', phone: '+91 90000 00024', email: 'sanjay.p@example.in', city: 'Nashik', lang: 'Marathi', course: 'Online BBA', spec: '', uni: '', level: 'UG', mode: 'Online', stage: -1, sub: 'Consent pending', temp: 'warm', score: 52, lane: 'nurture', reason: 'consent_no_answer', reasonText: 'No answer to partner-sharing request in 48 h', missing: ['Partner consent'], owner: null, journey: 'Consent repeat · step 1 of 3', lastMsg: 'wa_partner_consent_v1 · Delivered', lastAct: 'Form, 4 days ago', source: 'Google lead form', pool: '2 days' },
    { id: 4802, name: 'Meera Pillai', phone: '+91 90000 00025', email: 'meera.p@example.in', city: 'Thrissur', lang: 'English', course: 'Online M.Com', spec: '', uni: '', level: 'PG', mode: 'Online', stage: -1, sub: 'Counsellor-lost', temp: 'cold', score: 33, lane: 'nurture', reason: 'counsellor_lost', reasonText: 'Lost by Rohan: not now, later', owner: null, journey: 'Not now · monthly update · waits until 4 Nov', lastMsg: '—', lastAct: 'Call with Rohan, 5 Oct', source: 'Website form', pool: '9 days' },
    { id: 4781, name: 'Deepak Yadav', phone: '+91 90000 00026', email: 'deepak.y@example.in', city: 'Gurugram', lang: 'Hindi', course: 'Executive MBA', spec: '', uni: '', level: 'PG', mode: 'Blended', stage: -1, sub: 'Partner-lost', temp: 'warm', score: 57, lane: 'nurture', reason: 'partner_lost', reasonText: 'Lost by Sunstone: uncontactable', barred: 'lost', owner: null, journey: 'We tried to reach you · step 3 of 4', lastMsg: 'reach_you_2 · Read', lastAct: 'Email opened, today 09:12', source: 'Meta lead form', pool: '14 days' },
  ];

  leads.forEach(l => Object.assign(l, { qual: 'Not known yet', exp: 'Not known yet', budget: 'Not known yet', timeline: 'Not known yet', next: '—', nextAt: '—', assigned: '—', script: 'standard', campaign: '—', ...l }));

  const STAGES = [
    { name: 'New Lead', canon: 'assigned', subs: ['Fresh assignment', 'Re-engaged from nurture', 'Re-enquiry', 'Created by me', 'Returned from partners'] },
    { name: 'Could Not Connect', canon: 'contacted', subs: ['No answer', 'Busy', 'Switched off', 'Wrong number', 'Call back requested', 'Invalid number'] },
    { name: 'Contacted', canon: 'contacted', subs: ['Spoke briefly', 'Asked to call later', 'Parent or guardian spoke', 'WhatsApp reply only'] },
    { name: 'Qualified', canon: 'counselled', subs: ['Eligible and interested', 'Eligible, undecided', 'Budget confirmed', 'Timeline confirmed'] },
    { name: 'Follow Up', canon: 'counselled', subs: ['Call back on date', 'Awaiting parent decision', 'Comparing options', 'Awaiting documents', 'Awaiting fee arrangement or loan'] },
    { name: 'Program Details Explained', canon: 'counselled', subs: ['Brochure shared', 'Fee and EMI explained', 'Comparison shared', 'University call arranged'] },
    { name: 'Applicant', canon: 'applied', subs: ['Application started', 'Application submitted', 'Application fee paid'] },
    { name: 'Docs Submitted', canon: 'applied', subs: ['Partial', 'Complete', 'Verification pending', 'Verification query'] },
    { name: 'Enrolled', canon: 'enrolled', subs: ['Fee paid (partial)', 'Fee paid (full)', 'Enrollment confirmed by university', 'Verified by Admin'] },
    { name: 'Lost', canon: 'lost', subs: ['Uncontactable', 'Not eligible', 'Not interested', "Can't afford fee or EMI", 'Loan not approved', 'Document verification failed', 'Lost to competitor', 'Chose another provider', 'Not now, later', 'Wrong number', 'Junk or test', 'Enrolled elsewhere', 'Opted out', 'Other'] },
  ];

  const timeline = {
    4812: [
      { t: '11:14', kind: 'assign', text: 'Assigned to Priya by rule "Duplicate cascade → senior pool" (round robin, turn 3 of 2 eligible).' },
      { t: '11:14', kind: 'wa', dir: 'out', text: 'Template counsellor_intro_hours: "Hi Asha, I\'m Priya from Eduwit. I\'ll call you shortly about the Online MBA." · Delivered' },
      { t: '11:13', kind: 'handoff', text: 'Handed to B2C: duplicate cascade. UpGrad (had her since 28 Aug) and Sunstone both reported her as an existing lead. Partner-barred.' },
      { t: '10:58', kind: 'witty', text: 'Witty chat (14 messages): asked about NMIMS fees and EMI; works in accounts; wants a weekend batch.' },
      { t: '10:41', kind: 'source', text: 'Meta lead form "Oct MBA · Lead form", campaign 120210001.' },
    ],
  };

  const followups = [
    { id: 1, lead: 4766, type: 'Call', note: 'First call · re-engaged lead, hot', when: 'Due now', bucket: 'notworked', sla: 'Breached 12 min' },
    { id: 2, lead: 4812, type: 'Call', note: 'First call · neutral-adviser opening', when: 'Due now', bucket: 'notworked', sla: '6 min left' },
    { id: 3, lead: 4799, type: 'Call', note: 'Parent decision on IIM K EP fee', when: '10:55', bucket: 'overdue', sla: 'Overdue 25 min' },
    { id: 4, lead: 4807, type: 'Call', note: 'Retry, 2 no-answers so far', when: '12:30', bucket: 'today' },
    { id: 5, lead: 4790, type: 'WhatsApp', note: 'Send Amity BBA brochure', when: '14:00', bucket: 'today' },
    { id: 6, lead: 4786, type: 'Document', note: 'Chase 12th marksheet and photo', when: '16:00', bucket: 'today' },
    { id: 7, lead: 4752, type: 'Call', note: 'Walk through LPU vs Manipal comparison', when: 'Tomorrow 10:30', bucket: 'upcoming', day: 'Thu 15 Oct' },
    { id: 8, lead: 4771, type: 'Document', note: 'Fee receipt for verification', when: 'Tomorrow 11:00', bucket: 'upcoming', day: 'Thu 15 Oct' },
    { id: 9, lead: 4790, type: 'Call', note: 'Check if parents agreed', when: 'Fri 16 Oct 18:00', bucket: 'upcoming', day: 'Fri 16 Oct' },
  ];

  const conversations = [
    { lead: 4799, last: 'Papa wants to know if the EMI has no-cost option?', at: '10:31', unread: 1, window: { open: true, left: '23 h 12 min' }, msgs: [
      { dir: 'out', tpl: 'sales_followup_programme', text: 'Hi Sneha, this is Priya from Eduwit. As promised, here are the IIM Kozhikode Executive MBA details. Shall we speak today?', at: 'Yesterday 17:02', status: 'Read' },
      { dir: 'in', text: 'Thanks Priya. Discussing with my father tonight.', at: 'Yesterday 21:40' },
      { dir: 'in', text: 'Papa wants to know if the EMI has no-cost option?', at: '10:31' },
    ] },
    { lead: 4812, last: 'Hi Asha, I\'m Priya from Eduwit. I\'ll call you shortly…', at: '11:14', unread: 0, window: { open: false }, msgs: [
      { dir: 'out', tpl: 'counsellor_intro_hours', text: 'Hi Asha, I\'m Priya from Eduwit. I\'ll call you shortly about the Online MBA.', at: '11:14', status: 'Delivered' },
    ] },
    { lead: 4790, last: 'ok send details', at: 'Yesterday', unread: 0, window: { open: false }, msgs: [
      { dir: 'out', tpl: 'sales_opener_v2', text: 'Hi Mohit, Priya from Eduwit here about the Online BBA you asked for. Can I share the fee details?', at: 'Mon 12:10', status: 'Read' },
      { dir: 'in', text: 'ok send details', at: 'Mon 12:44' },
    ] },
    { lead: 4786, last: 'Sent: Document checklist (Jain Online)', at: 'Mon', unread: 0, window: { open: false }, msgs: [
      { dir: 'out', tpl: 'docs_reminder', text: 'Hi Kavya, a reminder to share your 12th marksheet and a photo for your Jain Online application.', at: 'Mon 16:00', status: 'Delivered' },
    ] },
  ];

  const salesTemplates = [
    { name: 'sales_opener_v2', cat: 'Opener', text: 'Hi {{first_name}}, {{counsellor}} from Eduwit here about the {{programme}} you asked for. Can I share the fee details?', lang: 'English' },
    { name: 'sales_followup_programme', cat: 'Follow-up', text: 'Hi {{first_name}}, this is {{counsellor}} from Eduwit. As promised, here are the {{programme}} details. Shall we speak {{when}}?', lang: 'English' },
    { name: 'sales_opener_hi', cat: 'Opener', text: 'नमस्ते {{first_name}}, मैं Eduwit से {{counsellor}}। आपने {{programme}} के बारे में पूछा था, क्या मैं फीस की जानकारी भेजूँ?', lang: 'Hindi' },
    { name: 'docs_reminder', cat: 'Documents', text: 'Hi {{first_name}}, a reminder to share {{documents}} for your {{university}} application.', lang: 'English' },
    { name: 'fee_emi', cat: 'Fee and EMI', text: 'Hi {{first_name}}, {{programme}} at {{university}} is {{fee}} with EMI from {{emi}} a month. Want me to explain?', lang: 'English' },
  ];

  const emailTemplates = [
    { name: 'After first call', author: 'Priya Sharma', mine: true, uses: 42, reply: 31, cat: 'After call', rec: true },
    { name: 'MBA comparison (3 universities)', author: 'Rohan Mehta', mine: false, uses: 37, reply: 28, cat: 'Brochure' },
    { name: 'Fee and EMI options', author: 'Priya Sharma', mine: true, uses: 25, reply: 24, cat: 'Fee and EMI' },
    { name: 'Documents checklist', author: 'Ankit Verma', mine: false, uses: 19, reply: 47, cat: 'Documents checklist' },
    { name: 'MBA comparison (Priya\'s version)', author: 'Priya Sharma', mine: true, uses: 6, reply: 33, cat: 'Brochure', parent: 'MBA comparison (3 universities)' },
  ];

  const programmes = [
    { uni: 'NMIMS CDOE', name: 'Online MBA', spec: 'Finance, Marketing, HR, Operations', level: 'PG', mode: 'Online', dur: '2 years', elig: 'Graduate, 50%', fee: 196000, emi: 8166, intake: 'Jan 2027 · closes 20 Dec', acc: 'UGC-DEB, NAAC A++', partners: 2, rate: '18% (UpGrad) · 16% (Sunstone)', owed: 35280 },
    { uni: 'Amity Online', name: 'Online MBA', spec: 'HR, Marketing, Finance, IB', level: 'PG', mode: 'Online', dur: '2 years', elig: 'Graduate, 40%', fee: 179000, emi: 7458, intake: 'Oct 2026 · closes 31 Oct', acc: 'UGC-DEB, NAAC A+', partners: 3, rate: '20% (UpGrad) · 18% (Collegedunia)', owed: 35800 },
    { uni: 'Manipal Online', name: 'Online MCA', spec: 'Data Science, Cloud, Cyber Security', level: 'PG', mode: 'Online', dur: '2 years', elig: 'BCA/B.Sc, 50%', fee: 158000, emi: 6583, intake: 'Jan 2027', acc: 'UGC-DEB, NAAC A+', partners: 0, rate: 'No partner · university rate 15% (flagged)', owed: 23700 },
    { uni: 'LPU Online', name: 'Online MCA', spec: 'Cloud, AI/ML', level: 'PG', mode: 'Online', dur: '2 years', elig: 'Graduate with maths, 50%', fee: 132000, emi: 5500, intake: 'Jan 2027', acc: 'UGC-DEB, NAAC A++', partners: 1, rate: '15% (Sunstone)', owed: 19800 },
    { uni: 'Jain Online', name: 'Online M.Com', spec: 'Accounting, Finance', level: 'PG', mode: 'Online', dur: '2 years', elig: 'B.Com, 45%', fee: 110000, emi: 4583, intake: 'Oct 2026 · closes 25 Oct', acc: 'UGC-DEB, NAAC A++', partners: 1, rate: '17% (Collegedunia)', owed: 18700 },
    { uni: 'Amity Online', name: 'Online BBA', spec: 'General', level: 'UG', mode: 'Online', dur: '3 years', elig: '12th pass, 40%', fee: 165000, emi: 4583, intake: 'Oct 2026', acc: 'UGC-DEB, NAAC A+', partners: 2, rate: '15% (UpGrad) · 14% (Sunstone)', owed: 24750 },
    { uni: 'IIM Kozhikode', name: 'Executive Programme in Marketing', spec: 'Marketing', level: 'PG cert.', mode: 'Blended', dur: '12 months', elig: 'Graduate, 5 years exp.', fee: 375000, emi: 15625, intake: 'Feb 2027', acc: 'IIM', partners: 0, rate: 'University has no partner: needs rate', owed: null },
  ];

  const journeys = [
    { name: 'Qualify: missing details', trigger: 'Enters pool · not qualified', status: 'Live', v: 'v3', inFlow: 412, entered: 1880, reeng: 9.8, steps: [
      { k: 'trigger', t: 'Enters the pool', s: 'reason = not_qualified' },
      { k: 'send', t: 'WhatsApp: explore_programmes', s: 'Utility · English / Hindi', n: 1880 },
      { k: 'wait', t: 'Wait 1 day', s: 'until 10:00', n: 1702 },
      { k: 'branch', t: 'Still missing course?', s: 'yes 71% · no 29%', n: 1702 },
      { k: 'send', t: 'WhatsApp: missing_details', s: 'Quick replies: MBA · MCA · BBA · Other', n: 1208 },
      { k: 'wait', t: 'Wait 2 days', s: '', n: 1013 },
      { k: 'send', t: 'Email: tell_us_more', s: 'From connect@eduwit.in', n: 640 },
      { k: 'exit', t: 'Exit', s: 'qualified → back to partner routing · opted out · dormant', n: 0 },
    ] },
    { name: 'Partner-lost: over budget', trigger: 'Enters pool · partner lost · over budget', status: 'Live', v: 'v2', inFlow: 188, entered: 640, reeng: 12.4 },
    { name: 'We tried to reach you', trigger: 'Lost · uncontactable (3 days)', status: 'Live', v: 'v1', inFlow: 96, entered: 311, reeng: 7.1 },
    { name: 'Consent repeat', trigger: 'Enters pool · consent no answer', status: 'Live', v: 'v1', inFlow: 54, entered: 120, reeng: 0 },
    { name: 'Not now: monthly update', trigger: 'Lost · not now, later (30 days)', status: 'Live', v: 'v2', inFlow: 230, entered: 455, reeng: 4.2 },
    { name: 'Admission deadline countdown', trigger: 'Date · 7 days before deadline', status: 'Draft', v: 'v1', inFlow: 0, entered: 0, reeng: 0 },
  ];

  const replies = [
    { lead: 4781, ch: 'WhatsApp', text: 'yes pls call after 6pm', cls: 'Positive', conf: 0.97, method: 'Button', at: '11:02' },
    { lead: 4828, ch: 'WhatsApp', text: 'kitna fees hai total aur emi milega kya', cls: 'Question', conf: 0.74, method: 'AI', at: '10:47' },
    { lead: 4802, ch: 'Email', text: 'Not right now, maybe next year. Thanks', cls: 'Negative', conf: 0.91, method: 'AI', at: '09:30' },
    { lead: 4815, ch: 'WhatsApp', text: 'STOP', cls: 'Opt-out', conf: 1, method: 'Rule', at: '08:55' },
  ];

  const rules = [
    { on: true, name: 'Test leads', cond: 'Lead is a test lead', logic: 'Manual queue', pool: 'Admin only', fb: '—' },
    { on: true, name: 'Duplicate cascade → senior pool', cond: 'Reason is duplicate cascade', logic: 'Round robin', pool: 'Seniors (Priya, Rohan)', fb: 'Next rule' },
    { on: true, name: 'Re-engaged lost leads', cond: 'Trigger is re-engagement and lost by a B2C counsellor', logic: 'Returning student', pool: 'Everyone', fb: 'Next rule' },
    { on: true, name: 'Hindi-speaking leads', cond: 'Language is Hindi', logic: 'Skill or language match', pool: 'Hindi speakers', fb: 'Next rule' },
    { on: false, name: 'Executive programmes', cond: 'Programme level is Executive', logic: 'Skill match', pool: 'Exec MBA', fb: 'Next rule' },
    { on: true, name: 'Everyone else (catch-all)', cond: 'Any lead', logic: 'Round robin', pool: 'Everyone', fb: 'Unassigned queue + alert' },
  ];

  const lead = id => leads.find(l => l.id === +id);
  return { now, counsellors, me, leads, STAGES, timeline, followups, conversations, salesTemplates, emailTemplates, programmes, journeys, replies, rules, lead };
})();
