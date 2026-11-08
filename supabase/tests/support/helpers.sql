-- Test helpers, loaded before each test file.
create schema if not exists t;

-- Make an app player directly (as if they signed up).
create or replace function t.player(
  p_name text,
  p_position public.position default 'midfielder',
  p_points integer default 0
) returns uuid language plpgsql as $$
declare
  uid uuid := gen_random_uuid();
begin
  insert into auth.users (id, phone) values (uid, '+2010' || lpad((floor(random() * 1e8))::bigint::text, 8, '0'));
  insert into public.profiles (id, display_name, favorite_position, birth_date, points)
  values (uid, p_name, p_position, date '1995-01-01', p_points);
  return uid;
end $$;

create or replace function t.login(p_user uuid) returns void language sql as $$
  select set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false)
$$;

create or replace function t.at(p_time timestamptz) returns void language sql as $$
  select set_config('kora.now', p_time::text, false)
$$;

create or replace function t.pitch(p_price integer default 600) returns uuid language sql as $$
  insert into public.pitches (name, area, address, lat, lng, price_per_hour_egp)
  values ('Test pitch', 'Maadi', 'Street 9', 29.96, 31.25, p_price)
  returning id
$$;

create or replace function t.eq(p_actual anyelement, p_expected anyelement, p_what text)
returns void language plpgsql as $$
begin
  if p_actual is distinct from p_expected then
    raise exception 'FAIL %: expected %, got %', p_what, p_expected, p_actual;
  end if;
  raise notice 'ok - %', p_what;
end $$;

-- Assert that a statement fails with an error message containing p_error.
create or replace function t.fails(p_sql text, p_error text, p_what text)
returns void language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    if position(p_error in sqlerrm) > 0 then
      raise notice 'ok - %', p_what;
      return;
    end if;
    raise exception 'FAIL %: expected error "%", got "%"', p_what, p_error, sqlerrm;
  end;
  raise exception 'FAIL %: expected error "%", but it succeeded', p_what, p_error;
end $$;

-- Fill a match with new players (each joins themselves). Returns their ids.
create or replace function t.fill(p_match uuid, p_count integer, p_position public.position default 'midfielder')
returns uuid[] language plpgsql as $$
declare
  ids uuid[] := '{}';
  pid uuid;
  i integer;
begin
  for i in 1..p_count loop
    pid := t.player('Player ' || i, p_position);
    perform t.login(pid);
    perform public.join_match(p_match, p_position, 'online');
    ids := ids || pid;
  end loop;
  return ids;
end $$;

grant usage on schema t to authenticated;
grant execute on all functions in schema t to authenticated;
