-- CX Studio · reviews
-- Run this once in Supabase: SQL Editor → New query → paste everything → Run.
-- It creates the reviews table, lets visitors read and add reviews (never edit or delete),
-- and adds the totals shown at the top of the Reviews section.

create table if not exists public.reviews (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  name        text not null check (char_length(btrim(name)) between 2 and 60),
  country     text check (country is null or char_length(country) <= 56),
  service     text check (service is null or char_length(service) <= 40),
  rating      smallint not null check (rating between 1 and 5),
  body        text not null check (char_length(btrim(body)) between 10 and 800),
  hidden      boolean not null default false   -- tick this in the Table Editor to hide a review from the site
);

create index if not exists reviews_newest on public.reviews (created_at desc, id desc) where hidden = false;

alter table public.reviews enable row level security;

-- Visitors can read every review that is not hidden
drop policy if exists "Visitors can read reviews" on public.reviews;
create policy "Visitors can read reviews" on public.reviews
  for select to anon, authenticated
  using (hidden = false);

-- Visitors can add a review; they cannot change or delete any
drop policy if exists "Visitors can add reviews" on public.reviews;
create policy "Visitors can add reviews" on public.reviews
  for insert to anon, authenticated
  with check (hidden = false);

revoke all on public.reviews from anon, authenticated;
grant select on public.reviews to anon, authenticated;
grant insert (name, country, service, rating, body) on public.reviews to anon, authenticated;

-- Tidy the text and stop floods: at most 30 new reviews in any 10 minutes
create or replace function public.reviews_before_insert()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.name := btrim(new.name);
  new.body := btrim(new.body);
  new.country := nullif(btrim(coalesce(new.country, '')), '');
  new.service := nullif(btrim(coalesce(new.service, '')), '');
  if (select count(*) from public.reviews r where r.created_at > now() - interval '10 minutes') >= 30 then
    raise exception 'Too many reviews right now, try again later';
  end if;
  return new;
end;
$$;

drop trigger if exists reviews_before_insert on public.reviews;
create trigger reviews_before_insert
  before insert on public.reviews
  for each row execute function public.reviews_before_insert();

-- Totals for the top of the section: number of reviews and the average rating
create or replace view public.review_stats
  with (security_invoker = on) as
  select count(*)::int as total,
         coalesce(round(avg(rating)::numeric, 1), 0) as average
  from public.reviews
  where hidden = false;

grant select on public.review_stats to anon, authenticated;
