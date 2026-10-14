/** The in-app guide for counsellors (spec B16): short, practical, one section per job. */
export const GUIDE: { title: string; body: string[] }[] = [
  { title: "A day in the app", body: [
    "Start on Today. Work the queue from the top: overdue follow-ups, then new leads, then what is due today.",
    "Every lead you touch ends with a next follow-up. The app will not let you save a call or a stage without one, so nothing is forgotten.",
  ] },
  { title: "New leads and the first-contact SLA", body: [
    "A new lead shows a timer: call before it runs out (the Admin sets the limits: by default 15 minutes for a hot lead, 4 hours for warm, a day for cold, counted in your working hours).",
    "When the timer runs out the lead turns red and the Admin is told. Call it first.",
  ] },
  { title: "Calling and logging", body: [
    "Tap Call: your phone's dialler opens. When you come back, the log sheet is waiting: choose the outcome, add a note, pick the next follow-up.",
    "A tapped call that is not logged within 10 minutes shows \"Call not logged\" on the lead and alerts you.",
    "The stage moves by itself from New Lead: No answer, Busy or Switched off go to Could Not Connect; Connected goes to Contacted.",
  ] },
  { title: "WhatsApp and the 24-hour window", body: [
    "You can type freely only within 24 hours of the student's last message. Outside that window, start with an approved sales template.",
    "Messages go from the Eduwit B2C number. In test mode nothing reaches the student; the message shows \"test mode, not sent\".",
    "If a student writes STOP, every message stops at once and the lead shows Opted out.",
  ] },
  { title: "Stages and sub-stages", body: [
    "Choose a stage and a sub-stage. Lost always needs a comment; some Lost reasons send the lead to nurture, others close it for good.",
    "Moving a lead back to an earlier stage needs the Admin.",
  ] },
  { title: "Changing interest (cross-sell)", body: [
    "If the student wants a different programme or university, use Change on Interest and say why. The change is kept in the history and reaches the master lead table.",
  ] },
  { title: "Applications and enrolment", body: [
    "Add the application with the university's application ID; the lead becomes an Applicant. Tick the documents as they arrive.",
    "Record the enrolment with the fee, the date and the proof (receipt or university letter). The Admin verifies it; then it counts.",
  ] },
  { title: "Students already with partners", body: [
    "Some students were already contacted by admission partners. The lead says so. Open as a neutral adviser: \"Eduwit can help you compare your options\"; do not pitch one university.",
  ] },
  { title: "Privacy", body: [
    "A counsellor sees only their own leads; the sales head, the Admin and Marketing see all. Never copy student data into personal chats or sheets.",
  ] },
];
