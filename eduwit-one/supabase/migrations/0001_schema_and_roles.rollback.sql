-- Rollback of 0001. Run only after the rollbacks of every later migration (schema one must be empty).
-- "drop owned by" revokes every privilege and default privilege granted to the roles in this database (they own no
-- objects, so nothing else is dropped). It needs the privileges of the roles, which a role's creator does not get by
-- default on Postgres 16+, hence the membership grant first.

grant eduwit_one_fixer, eduwit_one_reader to current_user;
drop owned by eduwit_one_fixer, eduwit_one_reader;
drop role if exists eduwit_one_fixer;
drop role if exists eduwit_one_reader;
drop schema if exists one;
