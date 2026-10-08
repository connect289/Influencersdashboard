import json, hashlib, sys, difflib, os
SP = sys.argv[1]
NO_CONSENT = '--no-consent' in sys.argv   # hold the consent wording and recording (edits 3, 4, 9) pending the lawyer
w = json.load(open(f"{SP}/witty/live.json"))['workflow']
N = {n['name']: n for n in w['nodes']}
HO_EN_OLD = "Thank you for sharing your details{name}. Based on your interest in {course}, I've arranged for one of our Academic Counselors to contact you on this number. They'll help you with the next steps."
HO_EN_NEW = "Thank you{name}. An academic counsellor will contact you shortly about {course}."
HO_HI_OLD = "Details share karne ke liye thank you{name}. {course} mein aapki interest ke hisaab se maine hamare ek Academic Counselor ko aapse isi number par contact karne ke liye bol diya hai. Woh aapko next steps mein madad karenge."
HO_HI_NEW = "Thank you{name}. Ek academic counsellor jald hi aapse {course} ke baare mein contact karenge."
OF_EN_OLD = "Would you like one of our academic counselors to help you with the next steps?"
OF_EN_NEW = "Would you like an academic counsellor to help you with the next steps?"
OF_HI_OLD = "Kya aap chahenge ki hamare ek academic counselor next steps mein aapki madad karein?"
OF_HI_NEW = "Kya aap chahenge ki ek academic counsellor next steps mein aapki madad karein?"
CO_EN_OLD = "Your details are used only to help with your admission and may be shared with our partner universities. Reply STOP anytime to opt out."
CO_EN_NEW = "Your details are used only to help with your admission and may be shared with our partner universities and our admission partners (edtech companies). Reply STOP anytime to opt out."
CO_HI_OLD = "Aapki details sirf admission help ke liye use hongi aur partner universities ke saath share ho sakti hain. Kabhi bhi STOP likh kar band kar sakte hain."
CO_HI_NEW = "Aapki details sirf admission help ke liye use hongi aur hamari partner universities aur admission partners (edtech companies) ke saath share ho sakti hain. Kabhi bhi STOP likh kar band kar sakte hain."
CA_OLD = "s.consent_at = new Date().toISOString(); }"
CA_NEW = "s.consent_at = new Date().toISOString(); s.consent_partner_share_at = s.consent_at; s.consent_text_version = 'witty-notice-2026-10-v2'; }"
TY_OLD = "const type = !s.crm_fingerprint ? 'lead.qualified' : escalate ? 'lead.escalated' : clsChanged ? 'classification_changed' : 'lead.updated';"
TY_NEW = "const type = escalate ? 'lead.escalated' : !s.crm_fingerprint ? 'lead.qualified' : clsChanged ? 'classification_changed' : 'lead.updated';"
PH_OLD = "s.phase = 'ESCALATION'; s.bot_paused = true; }\nelse if (mode === 'SUPPORT') s.phase = 'SUPPORT';"
PH_NEW = "s.phase = 'ESCALATION'; s.bot_paused = true; }\nelse if (s.escalated_at && s.bot_paused) s.phase = 'ESCALATION';\nelse if (mode === 'SUPPORT') s.phase = 'SUPPORT';"
FB_OLD = "course: course || 'your program' });"
FB_NEW = "course: course || (plan.language === 'english' ? 'your programme' : 'aapke programme') });"
REPLY_NODES = ["Plan Reply", "Verify Reply", "Verify Rewrite", "Finalize Counselor"]
ENGINE_NODES = ["Plan Reply", "Validate + Decide"]
plan = {}
def add(node, old, new, count):
    plan.setdefault(node, []).append((old, new, count))
for n in REPLY_NODES:
    add(n, HO_EN_OLD, HO_EN_NEW, None); add(n, HO_HI_OLD, HO_HI_NEW, None)
if not NO_CONSENT:
    for n in REPLY_NODES + ["Assemble Commit"]:
        add(n, CO_EN_OLD, CO_EN_NEW, 1); add(n, CO_HI_OLD, CO_HI_NEW, None)
for n in ENGINE_NODES:
    add(n, OF_EN_OLD, OF_EN_NEW, 1); add(n, OF_HI_OLD, OF_HI_NEW, 1); add(n, TY_OLD, TY_NEW, 1); add(n, PH_OLD, PH_NEW, 1)
add("Plan Reply", FB_OLD, FB_NEW, 1)
if not NO_CONSENT:
    add("Assemble Commit", CA_OLD, CA_NEW, 1)
manifest = {}
for node, reps in plan.items():
    old_code = N[node]['parameters']['jsCode']
    code = old_code
    for old, new, count in reps:
        c = code.count(old)
        if c == 0 or (count is not None and c != count):
            sys.exit(f"ABORT {node}: expected {count} of {old[:60]!r}, found {c}")
        code = code.replace(old, new)
        print(f"{node}: {c}x {old[:50]!r}")
    for old, _, _ in reps:
        assert old not in code, (node, old[:40])
    fn = f"{SP}/wittyrel/nodes{'_noconsent' if NO_CONSENT else ''}/{node.replace(' ', '_').replace('+', 'and')}.js"
    os.makedirs(os.path.dirname(fn), exist_ok=True)
    open(fn, 'w').write(code)
    manifest[node] = {"id": N[node]['id'], "file": fn, "old_md5": hashlib.md5(old_code.encode()).hexdigest(),
                      "new_md5": hashlib.md5(code.encode()).hexdigest(), "old_len": len(old_code), "new_len": len(code),
                      "changed_lines": sum(1 for l in difflib.unified_diff(old_code.splitlines(), code.splitlines(), lineterm='', n=0) if l[:1] in '+-' and l[:3] not in ('+++', '---'))}
json.dump(manifest, open(f"{SP}/wittyrel/manifest{'_noconsent' if NO_CONSENT else ''}.json", 'w'), indent=1)
for k, v in manifest.items(): print(k, v['old_md5'], '->', v['new_md5'], v['old_len'], '->', v['new_len'], 'lines', v['changed_lines'])
