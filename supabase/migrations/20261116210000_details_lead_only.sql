-- Only the bride and groom (or whoever created the wedding) can change Story & details:
-- the couple's names, the events, Our story and the gift details. Other team members,
-- including the bridal party, can still view them.
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
      -- Story & details (names, events, our story, gift details) are also bride/groom only.
      new.data := jsonb_set(new.data, '{wedding}', coalesce(old.data->'wedding','{}'::jsonb));
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
