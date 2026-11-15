-- AfroVows database setup.
-- Run once in the Supabase SQL editor (or with `supabase db push`).
-- Public: the vendor directory, About us, site text, reviews.
-- Private: each couple's planner (only the couple and people they invite),
--          vendors' own listings, contact messages (site owner only).

create extension if not exists pgcrypto;

-- ---------- Profiles (one per login) ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  role text not null default 'couple' check (role in ('couple','vendor','admin')),
  biz text,
  wedding_id uuid,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from profiles where id = auth.uid() and role = 'admin')
$$;

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare r text := coalesce(new.raw_user_meta_data->>'role','couple');
begin
  if r not in ('couple','vendor') then r := 'couple'; end if;   -- nobody can sign up as admin
  insert into profiles(id,email,role,biz)
  values (new.id, lower(new.email), r, left(new.raw_user_meta_data->>'biz',200));
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.guard_profile() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  -- signed-in users can't change their own role, email or wedding link (the database's own functions can)
  if current_user in ('authenticated','anon') and not is_admin() then
    new.role := old.role; new.email := old.email; new.wedding_id := old.wedding_id;
  end if;
  return new;
end $$;
create trigger guard_profile before update on public.profiles
  for each row execute function public.guard_profile();

create policy "own profile" on public.profiles for select using (id = auth.uid() or is_admin());
create policy "update own profile" on public.profiles for update using (id = auth.uid() or is_admin());

-- ---------- Weddings (each couple's whole planner) ----------
create table public.weddings (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  code text not null unique check (code ~ '^[A-Z0-9]{4,16}$'),
  data jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.wedding_members (
  wedding_id uuid references public.weddings(id) on delete cascade,
  user_id uuid references public.profiles(id) on delete cascade,
  primary key (wedding_id, user_id)
);
alter table public.weddings enable row level security;
alter table public.wedding_members enable row level security;

create or replace function public.is_member(w uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from wedding_members where wedding_id = w and user_id = auth.uid())
$$;

create or replace function public.wedding_created() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into wedding_members values (new.id, new.owner) on conflict do nothing;
  update profiles set wedding_id = new.id where id = new.owner;
  return new;
end $$;
create trigger wedding_created after insert on public.weddings
  for each row execute function public.wedding_created();

-- When the couple removes someone from their team, they lose access.
create or replace function public.wedding_updated() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  new.updated_at := now(); new.owner := old.owner; new.code := old.code;
  delete from wedding_members m using profiles p
   where m.wedding_id = new.id and p.id = m.user_id and m.user_id <> new.owner
     and not exists (select 1 from jsonb_array_elements(coalesce(new.data->'team','[]')) t
                     where lower(t->>'email') = p.email and t->>'status' = 'joined');
  update profiles set wedding_id = null
   where wedding_id = new.id and id not in (select user_id from wedding_members where wedding_id = new.id);
  return new;
end $$;
create trigger wedding_updated before update on public.weddings
  for each row execute function public.wedding_updated();

create policy "members read" on public.weddings for select using (is_member(id) or owner = auth.uid());
create policy "couples create" on public.weddings for insert with check (
  owner = auth.uid() and exists(select 1 from profiles where id = auth.uid() and role = 'couple' and wedding_id is null));
create policy "members edit" on public.weddings for update using (is_member(id));
create policy "members list" on public.wedding_members for select using (user_id = auth.uid() or is_member(wedding_id));

-- Join a wedding with an invite code from the couple.
create or replace function public.join_wedding(invite text, display_name text) returns uuid
language plpgsql security definer set search_path = public as $$
declare w weddings; em text; newteam jsonb;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select email into em from profiles where id = auth.uid();
  select * into w from weddings
   where data->'team' @> jsonb_build_array(jsonb_build_object('code', upper(invite), 'status', 'invited')) limit 1;
  if w.id is null then return null; end if;
  select jsonb_agg(case when t->>'code' = upper(invite) and t->>'status' = 'invited'
           then t || jsonb_build_object('status','joined','email',em,'code','','name',coalesce(nullif(trim(display_name),''),t->>'name'))
           else t end order by i)
    into newteam from jsonb_array_elements(w.data->'team') with ordinality as x(t,i);
  insert into wedding_members values (w.id, auth.uid()) on conflict do nothing;
  update weddings set data = jsonb_set(data,'{team}',newteam) where id = w.id;
  update profiles set wedding_id = w.id where id = auth.uid();
  return w.id;
end $$;

-- ---------- Guests (no account, just the wedding code) ----------
create or replace function public.guest_wedding(wcode text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('code', code, 'wedding', data->'wedding', 'photos', coalesce(data->'photos','[]'))
  from weddings where code = upper(wcode)
$$;

create or replace function public.guest_find(wcode text, q text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare d jsonb; g jsonb; qd text := right(regexp_replace(coalesce(q,''),'\D','','g'),9);
begin
  select data into d from weddings where code = upper(wcode);
  if d is null then return null; end if;
  select x into g from jsonb_array_elements(coalesce(d->'guests','[]')) x
   where lower(trim(x->>'name')) = lower(trim(q))
      or (length(qd) = 9 and right(regexp_replace(coalesce(x->>'phone',''),'\D','','g'),9) = qd)
   limit 1;
  if g is null then return null; end if;
  return jsonb_build_object('id',g->'id','name',g->'name','events',g->'events','plus',g->'plus','rsvp',coalesce(g->'rsvp','{}'),'note',g->'note');
end $$;

create or replace function public.guest_rsvp(wcode text, guest_id text, answers jsonb, note text) returns boolean
language plpgsql security definer set search_path = public as $$
declare w weddings; newg jsonb; clean jsonb := '{}';  k text; v text;
begin
  select * into w from weddings where code = upper(wcode);
  if w.id is null then return false; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(coalesce(answers,'{}')) loop
    if v in ('yes','no') and length(k) < 40 then clean := clean || jsonb_build_object(k, v); end if;
  end loop;
  select jsonb_agg(case when x->>'id' = guest_id
           then x || jsonb_build_object('rsvp', coalesce(x->'rsvp','{}') || clean, 'note', left(coalesce(note,''),1000))
           else x end order by i)
    into newg from jsonb_array_elements(coalesce(w.data->'guests','[]')) with ordinality as t(x,i);
  if newg is null then return false; end if;
  update weddings set data = jsonb_set(data,'{guests}',newg) where id = w.id;
  return true;
end $$;

create or replace function public.guest_add_photo(wcode text, by_name text, url text) returns boolean
language plpgsql security definer set search_path = public as $$
declare w weddings;
begin
  if url !~ '^https://[^ ]+/storage/v1/object/public/media/guest/' and url !~ '^http://(127\.0\.0\.1|localhost):[0-9]+/storage/v1/object/public/media/guest/' then return false; end if;
  select * into w from weddings where code = upper(wcode);
  if w.id is null then return false; end if;
  update weddings set data = jsonb_set(data,'{photos}',
     jsonb_build_array(jsonb_build_object('id',substr(md5(random()::text),1,7),'by',left(by_name,80),'src',url,'at',(extract(epoch from now())*1000)::bigint))
     || coalesce(data->'photos','[]'))
   where id = w.id;
  return true;
end $$;

-- ---------- Vendor listings ----------
create table public.listings (
  id text primary key,
  owner uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  owner_email text,
  status text not null default 'draft' check (status in ('draft','pending','approved','rejected','removed')),
  note text,
  data jsonb not null default '{}'::jsonb,      -- the vendor's own details (includes private registration no.)
  live jsonb,                                    -- the approved public version
  plan text not null default 'basic' check (plan in ('basic','verified','featured')),
  plan_until timestamptz,
  plan_req jsonb,
  submitted_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.listings enable row level security;
create unique index one_listing_per_vendor on public.listings(owner);

create or replace function public.guard_listing() returns trigger
language plpgsql security invoker set search_path = public as $$
begin
  new.updated_at := now();
  new.owner_email := (select email from profiles where id = new.owner);
  if is_admin() or current_user not in ('authenticated','anon') then return new; end if;
  if tg_op = 'INSERT' then
    if not exists(select 1 from profiles where id = auth.uid() and role = 'vendor') then raise exception 'vendors only'; end if;
    new.owner := auth.uid(); new.live := null; new.plan := 'basic'; new.plan_until := null; new.note := null;
  else
    new.owner := old.owner; new.live := old.live; new.plan := old.plan; new.plan_until := old.plan_until;
    if new.status is distinct from old.status then new.note := null; else new.note := old.note; end if;
  end if;
  if new.status not in ('draft','pending') then
    new.status := case when tg_op = 'UPDATE' then old.status else 'draft' end;
  end if;
  return new;
end $$;
create trigger guard_listing before insert or update on public.listings
  for each row execute function public.guard_listing();

create policy "vendor reads own" on public.listings for select using (owner = auth.uid() or is_admin());
create policy "vendor adds own" on public.listings for insert with check (owner = auth.uid() or is_admin());
create policy "vendor edits own" on public.listings for update using (owner = auth.uid() or is_admin());
create policy "admin deletes" on public.listings for delete using (is_admin());

-- What everyone can see: only approved listings, only the public version.
create view public.public_listings as
  select id, live, case when plan_until is null or plan_until > now() then plan else 'basic' end as plan, plan_until
  from public.listings where status = 'approved' and live is not null;
grant select on public.public_listings to anon, authenticated;

-- ---------- Reviews ----------
create table public.reviews (
  id text primary key,
  vendor_id text not null,
  author uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  name text, rating int not null check (rating between 1 and 5),
  text text check (length(text) <= 2000), hired boolean default false,
  at timestamptz not null default now(),
  unique (vendor_id, author)
);
alter table public.reviews enable row level security;
create policy "anyone reads reviews" on public.reviews for select using (true);
create policy "couples write own" on public.reviews for insert with check (
  author = auth.uid() and exists(select 1 from profiles where id = auth.uid() and role = 'couple'));
create policy "couples edit own" on public.reviews for update using (author = auth.uid());
create policy "author or owner deletes" on public.reviews for delete using (author = auth.uid() or is_admin());

-- ---------- Contact messages ----------
create table public.messages (
  id text primary key default substr(md5(random()::text),1,10),
  name text not null check (length(name) <= 120), who text check (length(who) <= 40),
  email text check (length(email) <= 200), phone text check (length(phone) <= 40),
  msg text not null check (length(msg) <= 4000),
  read boolean not null default false,
  at timestamptz not null default now()
);
alter table public.messages enable row level security;
create policy "anyone sends" on public.messages for insert with check (read = false);
create policy "owner reads" on public.messages for select using (is_admin());
create policy "owner updates" on public.messages for update using (is_admin());
create policy "owner deletes" on public.messages for delete using (is_admin());

-- ---------- Site text, About us ----------
create table public.site_content (key text primary key, value jsonb not null, updated_at timestamptz default now());
alter table public.site_content enable row level security;
create policy "anyone reads site" on public.site_content for select using (true);
create policy "owner writes site" on public.site_content for all using (is_admin()) with check (is_admin());

-- ---------- Vendor stats ----------
create table public.vendor_stats (vendor_id text, month text, views int not null default 0, wa int not null default 0, primary key (vendor_id, month));
alter table public.vendor_stats enable row level security;
create policy "vendor or owner reads stats" on public.vendor_stats for select using (
  is_admin() or exists(select 1 from listings l where l.id = vendor_id and l.owner = auth.uid()));
create or replace function public.bump_stat(vid text, kind text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists(select 1 from listings where id = vid and status = 'approved') then return; end if;
  insert into vendor_stats(vendor_id, month, views, wa)
  values (vid, to_char(now(),'YYYY-MM'), (kind='views')::int, (kind='wa')::int)
  on conflict (vendor_id, month) do update set views = vendor_stats.views + (kind='views')::int, wa = vendor_stats.wa + (kind='wa')::int;
end $$;

grant execute on function public.guest_wedding(text), public.guest_find(text,text), public.guest_rsvp(text,text,jsonb,text),
  public.guest_add_photo(text,text,text), public.bump_stat(text,text) to anon, authenticated;
grant execute on function public.join_wedding(text,text) to authenticated;
revoke execute on function public.join_wedding(text,text) from anon;

-- ---------- File storage ----------
-- media: photos shown on pages (public links with random names)
-- docs:  invoices and receipts (private, only the couple's team)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('media','media',true,5242880,array['image/jpeg','image/png','image/webp','image/gif']),
       ('docs','docs',false,2097152,array['image/jpeg','image/png','application/pdf'])
on conflict (id) do nothing;

create policy "signed-in users upload own photos" on storage.objects for insert to authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = 'u' and (storage.foldername(name))[2] = auth.uid()::text);
create policy "guests upload wedding photos" on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'media' and (storage.foldername(name))[1] = 'guest');
create policy "team reads docs" on storage.objects for select to authenticated
  using (bucket_id = 'docs' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "team uploads docs" on storage.objects for insert to authenticated
  with check (bucket_id = 'docs' and public.is_member(((storage.foldername(name))[1])::uuid));
create policy "team deletes docs" on storage.objects for delete to authenticated
  using (bucket_id = 'docs' and public.is_member(((storage.foldername(name))[1])::uuid));

-- Check an invite code before someone signs up with it.
create or replace function public.invite_valid(invite text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists(select 1 from weddings
   where data->'team' @> jsonb_build_array(jsonb_build_object('code', upper(invite), 'status', 'invited')))
$$;
grant execute on function public.invite_valid(text) to anon, authenticated;
