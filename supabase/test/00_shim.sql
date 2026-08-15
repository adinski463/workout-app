-- Local-only shim for the parts of a Supabase instance the migrations depend on.
--
-- This is NOT applied to the real project — Supabase provides all of it. It
-- exists so `supabase/test/run.sh` can apply the migrations against a plain
-- Postgres and catch syntax errors, bad policies and broken functions without
-- needing a cloud project.

create schema if not exists auth;

create table if not exists auth.users (
  id    uuid primary key default gen_random_uuid(),
  email text unique
);

-- Supabase derives this from the request JWT. Locally we drive it from a GUC so
-- tests can switch identity with `set local request.jwt.claim.sub = '<uuid>'`.
create or replace function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$$;

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then
    create role anon nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then
    create role authenticated nologin;
  end if;
  if not exists (select 1 from pg_roles where rolname = 'service_role') then
    create role service_role nologin bypassrls;
  end if;
end
$$;
