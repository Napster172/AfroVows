-- Guests confirm how many of their plus-ones they're bringing.
drop function if exists public.guest_rsvp(text, text, jsonb, text);

create or replace function public.guest_rsvp(wcode text, guest_id text, answers jsonb, note text, plus_used int default null) returns boolean
language plpgsql security definer set search_path = public as $$
declare w weddings; newg jsonb; clean jsonb := '{}'; k text; v text;
begin
  select * into w from weddings where code = upper(wcode);
  if w.id is null then return false; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(coalesce(answers,'{}')) loop
    if v in ('yes','no') and length(k) < 40 then clean := clean || jsonb_build_object(k, v); end if;
  end loop;
  select jsonb_agg(case when x->>'id' = guest_id
           then x || jsonb_build_object('rsvp', coalesce(x->'rsvp','{}') || clean, 'note', left(coalesce(note,''),1000))
                  || case when plus_used is null then '{}'::jsonb
                          else jsonb_build_object('plusUsed', greatest(0, least(plus_used, coalesce((x->>'plus')::int, 0)))) end
           else x end order by i)
    into newg from jsonb_array_elements(coalesce(w.data->'guests','[]')) with ordinality as t(x,i);
  if newg is null then return false; end if;
  update weddings set data = jsonb_set(data,'{guests}',newg) where id = w.id;
  return true;
end $$;
grant execute on function public.guest_rsvp(text,text,jsonb,text,int) to anon, authenticated;

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
  return jsonb_build_object('id',g->'id','name',g->'name','events',g->'events','plus',g->'plus','plusUsed',g->'plusUsed','rsvp',coalesce(g->'rsvp','{}'),'note',g->'note');
end $$;
