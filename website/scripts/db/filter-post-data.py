#!/usr/bin/env python3
"""Filters pg_dump post-data for the minimal snapshot: keeps indexes, PK/unique/check constraints, RLS enablement and
only those triggers / foreign keys whose targets are included. Policies on shared tables are dropped (they reference CRM
helper functions); RLS stays enabled, so only privileged roles read them — as the website does in production."""
import re, sys
tables = set(sys.argv[1].split(","))
funcs = set(sys.argv[2].split(","))
sql = sys.stdin.read()
stmts = re.split(r";\s*\n", sql)
kept_triggers = set()
for s in stmts:
    t = s.strip()
    if not t:
        continue
    if t.startswith("CREATE POLICY"):
        continue
    m = re.search(r"EXECUTE FUNCTION ([a-z0-9_.]+)\(", t)
    if t.startswith("CREATE TRIGGER") and m:
        fn = m.group(1) if "." in m.group(1) else "public." + m.group(1)
        if fn not in funcs:
            continue
        kept_triggers.add(re.match(r"CREATE TRIGGER (\S+)", t).group(1))
    m = re.search(r"(?:DISABLE|ENABLE) (?:ALWAYS |REPLICA )?TRIGGER (\S+)", t)
    if m and m.group(1) not in kept_triggers:
        continue
    m = re.search(r"REFERENCES ([a-z0-9_.\"]+)\(", t)
    if "FOREIGN KEY" in t and m:
        ref = m.group(1).replace('"', "")
        ref = ref if "." in ref else "public." + ref
        if ref not in tables:
            continue
    print(t + ";\n")
