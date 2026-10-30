# Scratchpad only: these checks reproduce the old state on a local fixture. Do not commit them as they are.
# Rehearsal of the w5_*.sql fixes on a throwaway local Postgres (never production or staging).
# Usage: create an empty database, run tests/00_fixture.sql then tests/01_functions.sql in it, then
#   PGHOST=<socket dir> PGPORT=<port> PGDATABASE=<db> python3 tests/run_tests.py <scratch dir for rollback files>
# 01_functions.sql holds the production definitions of 30 Oct 2026 (no secrets, no personal data).
import subprocess, sys, re, os
A = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # the folder holding the w5_*.sql files
T = sys.argv[1]
BASE = ['psql', '-X', '-q', '-At', '-h', os.environ.get('PGHOST', '/var/lib/postgresql/witty-audit-test/sock'), '-p', os.environ.get('PGPORT', '54999'), '-U', 'postgres', '-d', os.environ.get('PGDATABASE', 'witty_t')]
passed = failed = 0
def sql(q, role=None, expect_error=None):
    if role: q = f"begin; set local role {role}; {q}; rollback;"
    r = subprocess.run(BASE + ['-v', 'ON_ERROR_STOP=1', '-c', q], capture_output=True, text=True)
    if expect_error is None and r.returncode != 0: raise RuntimeError(r.stderr.strip())
    return r
def run_file(path):
    r = subprocess.run(BASE + ['-v', 'ON_ERROR_STOP=1', '-f', path], capture_output=True, text=True)
    if r.returncode != 0: raise RuntimeError(path + ': ' + r.stderr.strip())
def rollback_of(path):
    lines = open(path).read().splitlines()
    i = next(k for k, l in enumerate(lines) if l.startswith('-- rollback'))
    body = [l[3:] if l.startswith('-- ') else ('' if l == '--' else l) for l in lines[i + 1:]]
    out = os.path.join(T, os.path.basename(path).replace('.sql', '.rollback.sql'))
    open(out, 'w').write('\n'.join(body) + '\n'); return out
def check(name, cond, detail=''):
    global passed, failed
    if cond: passed += 1; print('PASS', name)
    else: failed += 1; print('FAIL', name, detail)
SNAP = """select 'fn '||p.oid::regprocedure::text||' '||coalesce((select string_agg(a::text, ',' order by a::text) from unnest(p.proacl) a),'') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'w2\\_%'
union all select 'rel '||c.relname||' '||coalesce((select string_agg(a::text, ',' order by a::text) from unnest(c.relacl) a),'')||' '||coalesce(c.reloptions::text,'') from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relname like 'w2\\_%' and c.relkind in ('r','v')
union all select 'def '||p.proname||' '||md5(pg_get_functiondef(p.oid)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('w2_stale_inbox','w2_cache_plan') order by 1"""
snap = lambda: sql(SNAP).stdout
base = snap()
F1, F2, F3, F4 = [f'{A}/{x}' for x in ('w5_latency_daily_invoker.sql', 'w5_revoke_api_grants.sql', 'w5_stale_inbox_first_message.sql', 'w5_cache_plan_skip_unchanged.sql')]

# ---- seed data used by the behaviour checks
sql("""insert into w2_messages (phone, direction, kind, content, latency_ms, prompt_tokens, cached_tokens) values ('915555000001','out','reply','x',1200,100,90);
insert into w2_prompts (name, body) values ('extractor', 'EXTRACTOR PROMPT'), ('counselor', 'COUNSELOR PROMPT');
insert into catalog_programs (course_key, course, specialization, mode, level) values ('mba','MBA','Finance','online','PG'),('mba','MBA','HR','online','PG'),('bca','BCA','General','online','UG');""")

# ---- T1 view
check('anon can read the view before (the defect)', sql("select count(*) from w2_latency_daily", 'anon').stdout.strip() == '1')
run_file(F1); run_file(F1)
check('view: security_invoker set', 'security_invoker=true' in sql("select reloptions::text from pg_class where relname='w2_latency_daily'").stdout)
r = sql("select count(*) from w2_latency_daily", 'anon', expect_error=True)
check('view: anon refused', r.returncode != 0 and 'permission denied' in r.stderr, r.stderr)
r = sql("select count(*) from w2_latency_daily", 'authenticated', expect_error=True)
check('view: authenticated refused', r.returncode != 0 and 'permission denied' in r.stderr, r.stderr)
check('view: service_role still reads every row', sql("select count(*) from w2_latency_daily", 'service_role').stdout.strip() == '1')
check('view: postgres still reads every row', sql("select count(*) from w2_latency_daily").stdout.strip() == '1')

# ---- T2 grants
run_file(F2); run_file(F2)
bad = sql("""select string_agg(p.proname||':'||r, ',') from pg_proc p join pg_namespace n on n.oid=p.pronamespace, unnest(array['anon','authenticated']) r
 where n.nspname='public' and p.proname like 'w2\\_%' and has_function_privilege(r, p.oid, 'EXECUTE') and not (p.proname='w2_crm_owned' and r='authenticated')""").stdout.strip()
check('grants: no w2 function executable by anon/authenticated (except authenticated on w2_crm_owned)', bad == '', bad)
check('grants: authenticated keeps w2_crm_owned', sql("select has_function_privilege('authenticated','public.w2_crm_owned(text)','EXECUTE')").stdout.strip() == 't')
check('grants: anon still cannot run w2_crm_owned', sql("select has_function_privilege('anon','public.w2_crm_owned(text)','EXECUTE')").stdout.strip() == 'f')
miss = sql("select string_agg(p.proname, ',') from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname like 'w2\\_%' and not has_function_privilege('service_role', p.oid, 'EXECUTE')").stdout.strip()
check('grants: service_role keeps EXECUTE on every w2 function', miss == '', miss)
badt = sql("""select string_agg(c.relname||':'||r, ',') from pg_class c join pg_namespace n on n.oid=c.relnamespace, unnest(array['anon','authenticated']) r
 where n.nspname='public' and c.relname like 'w2\\_%' and c.relkind in ('r','v') and (has_table_privilege(r, c.oid, 'SELECT') or has_table_privilege(r, c.oid, 'INSERT') or has_table_privilege(r, c.oid, 'UPDATE') or has_table_privilege(r, c.oid, 'DELETE') or has_table_privilege(r, c.oid, 'TRUNCATE'))""").stdout.strip()
check('grants: anon/authenticated hold no privilege on any w2 table or view (backups included)', badt == '', badt)
check('grants: service_role keeps table privileges', sql("select has_table_privilege('service_role','public.w2_inbox','INSERT') and has_table_privilege('service_role','public.w2_messages_backup_20261004','SELECT')").stdout.strip() == 't')
r = sql("select w2_health_alerts()", 'eduwit_one_reader', expect_error=True)
check('grants: eduwit_one_reader can still call w2_health_alerts() (nested helpers granted)', r.returncode == 0, r.stderr)
r = sql("select w2_health_digest(24)", 'eduwit_one_reader', expect_error=True)
check('grants: eduwit_one_reader can still call w2_health_digest()', r.returncode == 0, r.stderr)
r = sql("select w2_inbox_add('{}'::jsonb)", 'anon', expect_error=True)
check('grants: anon gets permission denied on a w2 RPC', r.returncode != 0 and 'permission denied for function' in r.stderr, r.stderr)
r = sql("select w2_inbox_add(jsonb_build_object('message_id','m-own','phone','915555000009','content','hi'))")
check('grants: the owner (n8n as postgres) still runs w2 functions', 'inserted' in r.stdout or r.returncode == 0)
sql("delete from w2_inbox where message_id='m-own'; delete from w2_messages where message_id='m-own'")

# ---- T3 stale inbox
old = "now() - interval '10 minutes'"
sql(f"""insert into w2_inbox (message_id, phone, content, received_at) values
 ('a1','915555000101','first msg, no conversation row',{old}),
 ('b1','915555000102','conversation, lock free',{old}),
 ('c1','915555000103','conversation locked',{old}),
 ('d1','915555000104','opted out',{old}),
 ('e1','915555000105','too recent', now()),
 ('f1','915555000106','processed',{old});
update w2_inbox set processed_at = now() where message_id='f1';
insert into w2_conversations (phone) values ('915555000102');
insert into w2_conversations (phone, lock_until) values ('915555000103', now() + interval '1 minute');
insert into w2_conversations (phone, opted_out) values ('915555000104', true);""")
before = sql("select string_agg(phone, ',' order by phone) from w2_stale_inbox(40)").stdout.strip()
check('stale (live definition) misses the first message without a conversation row (the defect)', before == '915555000102', before)
run_file(F3); run_file(F3)
after = sql("select string_agg(phone, ',' order by phone) from w2_stale_inbox(40)").stdout.strip()
check('stale (fixed) re-runs the orphan first message, filters the rest exactly as before', after == '915555000101,915555000102', after)
check('stale (fixed) feeds the stale_inbox health alert too', 'stale_inbox' in sql("select w2_health_alerts()::text").stdout)
check('stale: definition keeps signature, language, volatility', sql("select prorettype::regtype::text||' '||provolatile::text||' '||(select lanname from pg_language where oid=prolang)||' '||pg_get_function_arguments(oid) from pg_proc where proname='w2_stale_inbox'").stdout.strip() == 'text s sql p_older_than_seconds integer DEFAULT 40')
sql("delete from w2_inbox; delete from w2_conversations")

# ---- T4 cache plan equivalence and no-op write
def plan(): return sql("select w2_cache_plan('gemini-3.6-flash', 40)::text").stdout.strip()
def jobs(p): return sorted(re.findall(r'"name": "(extractor|counselor)"', p))
def row(n): return sql(f"select xmin::text||' '||updated_at::text from w2_gemini_caches where name='{n}'").stdout.strip()
def save_valid():
    for n in ('extractor', 'counselor'):
        sql(f"""select w2_cache_saved(jsonb_build_object('name','{n}','cache_name','cachedContents/{n}','model','gemini-3.6-flash','hash', md5(w2_build_prompt('{n}')),'tokens',10,'expire_at', now() + interval '90 minutes'))""")
p_old_first = plan(); save_valid(); p_old_valid = plan(); r_old = row('extractor'); p_old_again = plan(); r_old2 = row('extractor')
check('cache (live definition) rewrites the row on every run even when nothing changed', r_old != r_old2)
sql("delete from w2_gemini_caches")
run_file(F4); run_file(F4)
p_new_first = plan(); save_valid(); p_new_valid = plan(); r1 = row('extractor'); p_new_again = plan(); r2 = row('extractor')
check('cache: first run asks for both caches, as before', jobs(p_new_first) == jobs(p_old_first) == ['counselor', 'extractor'], p_new_first[:120])
check('cache: valid caches -> no job, as before', p_new_valid == p_old_valid == '[]', p_new_valid)
check('cache: unchanged text -> row not rewritten (same xmin and updated_at)', r1 == r2, f'{r1} vs {r2}')
sql("update w2_prompts set body = 'EXTRACTOR PROMPT v2' where name='extractor'")
p_changed = plan()
check('cache: changed extractor prompt -> one job for extractor only', jobs(p_changed) == ['extractor'], p_changed[:200])
check('cache: changed text is written to prompt_text', sql("select prompt_text like 'EXTRACTOR PROMPT v2%' from w2_gemini_caches where name='extractor'").stdout.strip() == 't')
check('cache: turn prompts still serve the text', 'EXTRACTOR PROMPT v2' in sql("select w2_turn_prompts()::text").stdout)

# ---- T5 rollbacks restore the exact ACLs and definitions
for f in (F4, F3, F2, F1):
    run_file(rollback_of(f))
restored = snap()
check('rollback: ACLs, view options and function definitions identical to the baseline', restored == base, '\n'.join(l for l in set(base.splitlines()) ^ set(restored.splitlines())))
# re-apply after rollback works (idempotent)
for f in (F1, F2, F3, F4): run_file(f)
check('re-apply after rollback succeeds', True)
print(f'\n{passed} passed, {failed} failed')
sys.exit(1 if failed else 0)
