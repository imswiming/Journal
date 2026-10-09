-- Cloud sync storage for the Journal app (index.html - see its "Cloud sync"
-- section). One key/value row per piece of a user's data:
--   notes                     -> { tabs: [{ id, name, content }] }
--   activity                  -> { entries: [{ type, book, chapter, verse, date }] }
--   hl:<book>:<chapter>       -> { html } (a chapter's saved highlights)
--
-- Every row belongs to the signed-in user who wrote it, and row level security
-- limits each user to their own rows - which is what makes it safe for the
-- app to ship the project's publishable key in public client-side code.

create table if not exists public.journal_sync (
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  key        text        not null,
  data       jsonb       not null,
  -- Bumped by the trigger below on every write, from one shared sequence, so
  -- it only ever increases. The app uses it to tell what's changed and as the
  -- compare-and-swap check on writes. It comes from the database rather than
  -- any device's clock, so a phone with a wrong clock can't produce an edit
  -- that looks older than it is.
  rev        bigint      not null default 0,
  updated_at timestamptz not null default now(),
  primary key (user_id, key)
);

create sequence if not exists public.journal_sync_rev_seq;

create or replace function public.journal_sync_bump_rev()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.rev := nextval('public.journal_sync_rev_seq');
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists journal_sync_bump_rev on public.journal_sync;
create trigger journal_sync_bump_rev
  before insert or update on public.journal_sync
  for each row execute function public.journal_sync_bump_rev();

alter table public.journal_sync enable row level security;

drop policy if exists "journal_sync: read own rows" on public.journal_sync;
create policy "journal_sync: read own rows"
  on public.journal_sync for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists "journal_sync: insert own rows" on public.journal_sync;
create policy "journal_sync: insert own rows"
  on public.journal_sync for insert to authenticated
  with check (user_id = (select auth.uid()));

drop policy if exists "journal_sync: update own rows" on public.journal_sync;
create policy "journal_sync: update own rows"
  on public.journal_sync for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists "journal_sync: delete own rows" on public.journal_sync;
create policy "journal_sync: delete own rows"
  on public.journal_sync for delete to authenticated
  using (user_id = (select auth.uid()));

-- Signed-out visitors get nothing at all, not even an empty, policy-filtered
-- result.
revoke all on public.journal_sync from anon;
grant select, insert, update, delete on public.journal_sync to authenticated;
grant usage on sequence public.journal_sync_rev_seq to authenticated;
