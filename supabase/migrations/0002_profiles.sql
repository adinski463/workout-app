-- User profiles, mirrored from auth.users.
--
-- Supabase's auth.users table is not directly queryable by clients, so public
-- identity (username, avatar) lives here.

create table profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  username    text not null unique
                check (char_length(username) between 3 and 24
                       and username ~ '^[a-zA-Z0-9_]+$'),
  avatar_url  text,
  bio         text check (char_length(bio) <= 300),
  -- Weight is always stored in kg; this only controls display (Change 4).
  unit_pref   text not null default 'kg' check (unit_pref in ('kg', 'lb')),
  created_at  timestamptz not null default now()
);

alter table profiles enable row level security;

create policy "profiles are world readable"
  on profiles for select using (true);

create policy "users insert their own profile"
  on profiles for insert with check (auth.uid() = id);

create policy "users update their own profile"
  on profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- Create a profile automatically on signup so the app never has to handle a
-- logged-in user without a profile row.
create function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    -- Derive a starting username from the email local part, de-duplicated with
    -- a short random suffix. Users can change it later.
    regexp_replace(split_part(new.email, '@', 1), '[^a-zA-Z0-9_]', '', 'g')
      || '_' || substr(replace(new.id::text, '-', ''), 1, 6)
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Account deletion is a Google Play requirement for any app with accounts
-- (docs/01-plan-review.md). Deleting the auth user cascades to everything the
-- user owns via the foreign keys declared throughout this schema.
create function delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function delete_own_account() from public, anon;
grant execute on function delete_own_account() to authenticated;
