-- New team members must type the first and last name on their invite, and
-- the bride or groom approves them before they can open the planner.
--
-- Flow: invited -> (join link + matching name) requested -> (bride/groom approves) joined.
-- A request does not give access. Only an approval by the couple does.

-- Same rules as nameMatches() in public/index.html.
create or replace function public.norm_name(x text) returns text
language sql immutable as $$
  select trim(regexp_replace(replace(lower(coalesce(x,'')),'.',''),'\s+',' ','g'))
$$;

create or replace function public.invite_name_ok(t jsonb, first_name text, last_name text) returns boolean
language sql immutable as $$
  select case
    when norm_name(first_name) = '' then false
    when coalesce(t->>'first','') <> '' then
      norm_name(first_name) = norm_name(t->>'first')
      and (norm_name(t->>'last') = '' or norm_name(last_name) = norm_name(t->>'last'))
    else norm_name(t->>'name') in (norm_name(first_name || ' ' || coalesce(last_name,'')), norm_name(first_name))
  end
$$;

-- Before sign-up: is this code open, and does the name match? Returns 'ok', 'name' or 'invalid'.
create or replace function public.invite_check(invite text, first_name text, last_name text) returns text
language plpgsql stable security definer set search_path = public as $$
declare t jsonb;
begin
  select x into t from weddings w, jsonb_array_elements(coalesce(w.data->'team','[]')) x
   where x->>'code' = upper(invite) and x->>'status' = 'invited' limit 1;
  if t is null then return 'invalid'; end if;
  if not invite_name_ok(t, first_name, last_name) then return 'name'; end if;
  return 'ok';
end $$;
grant execute on function public.invite_check(text,text,text) to anon, authenticated;

-- After sign-up: ask to join. Returns 'requested', 'name' or 'invalid'. Gives no access.
create or replace function public.request_join(invite text, first_name text, last_name text) returns text
language plpgsql security definer set search_path = public as $$
declare w weddings; em text; t jsonb; newteam jsonb;
begin
  if auth.uid() is null then raise exception 'not signed in'; end if;
  select email into em from profiles where id = auth.uid() and role = 'couple' and wedding_id is null;
  if em is null then return 'invalid'; end if;
  select * into w from weddings
   where data->'team' @> jsonb_build_array(jsonb_build_object('code', upper(invite), 'status', 'invited')) limit 1;
  if w.id is null then return 'invalid'; end if;
  select x into t from jsonb_array_elements(w.data->'team') x where x->>'code' = upper(invite) and x->>'status' = 'invited' limit 1;
  if not invite_name_ok(t, first_name, last_name) then return 'name'; end if;
  select jsonb_agg(case when x->>'code' = upper(invite) and x->>'status' = 'invited'
           then x || jsonb_build_object('status','requested','email',em,'uid',auth.uid()::text,'code','',
                  'asked', left(trim(coalesce(first_name,'') || ' ' || coalesce(last_name,'')),120),
                  'askedAt', (extract(epoch from now())*1000)::bigint)
           else x end order by i)
    into newteam from jsonb_array_elements(w.data->'team') with ordinality as y(x,i);
  perform set_config('afrovows.sys', '1', true);
  update weddings set data = jsonb_set(data,'{team}',newteam) where id = w.id;
  perform set_config('afrovows.sys', '', true);
  return 'requested';
end $$;
grant execute on function public.request_join(text,text,text) to authenticated;
revoke execute on function public.request_join(text,text,text) from anon;

-- For someone waiting: whose wedding they asked to join. Null if nothing is waiting.
create or replace function public.my_join_request() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('p1', w.data->'wedding'->>'p1', 'p2', w.data->'wedding'->>'p2', 'role', x->>'role')
    from weddings w, jsonb_array_elements(coalesce(w.data->'team','[]')) x
   where x->>'uid' = auth.uid()::text and x->>'status' = 'requested' limit 1
$$;
grant execute on function public.my_join_request() to authenticated;

-- The old join skipped approval, so remove it.
drop function if exists public.join_wedding(text, text);

-- Only the bride, groom or wedding creator can change the team list. When they
-- approve a request, that person becomes a member.
create or replace function public.wedding_updated() returns trigger
language plpgsql security definer set search_path = public as $$
declare me_email text; lead boolean;
begin
  new.updated_at := now(); new.owner := old.owner; new.code := old.code;
  -- request_join sets afrovows.sys for its own update; every other change made by a
  -- signed-in person or a guest keeps the team list unless they are the bride or groom.
  if coalesce(current_setting('afrovows.sys', true), '') <> '1' and not is_admin() then
    select email into me_email from profiles where id = auth.uid();
    lead := auth.uid() = old.owner or exists (
      select 1 from jsonb_array_elements(coalesce(old.data->'team','[]')) t
       where lower(t->>'email') = me_email and t->>'status' = 'joined' and t->>'role' in ('Bride','Groom'));
    if not lead then
      new.data := jsonb_set(new.data, '{team}', coalesce(old.data->'team','[]'::jsonb));
    end if;
  end if;
  -- Approvals: a person who was 'requested' in the old list and is 'joined' now.
  insert into wedding_members (wedding_id, user_id)
  select new.id, (n->>'uid')::uuid
    from jsonb_array_elements(coalesce(new.data->'team','[]')) n
   where n->>'status' = 'joined' and coalesce(n->>'uid','') <> ''
     and exists (select 1 from jsonb_array_elements(coalesce(old.data->'team','[]')) o
                  where o->>'uid' = n->>'uid' and o->>'status' = 'requested')
     and exists (select 1 from profiles p where p.id::text = n->>'uid' and lower(n->>'email') = p.email and p.wedding_id is null)
  on conflict do nothing;
  update profiles p set wedding_id = new.id
   where p.wedding_id is null and exists (select 1 from wedding_members m where m.wedding_id = new.id and m.user_id = p.id);
  -- Removals: anyone no longer 'joined' loses access.
  delete from wedding_members m using profiles p
   where m.wedding_id = new.id and p.id = m.user_id and m.user_id <> new.owner
     and not exists (select 1 from jsonb_array_elements(coalesce(new.data->'team','[]')) t
                     where lower(t->>'email') = p.email and t->>'status' = 'joined');
  update profiles set wedding_id = null
   where wedding_id = new.id and id not in (select user_id from wedding_members where wedding_id = new.id);
  return new;
end $$;
