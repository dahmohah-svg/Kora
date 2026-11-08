-- Kora: actions players, hosts and admins take. Every change to data goes
-- through one of these functions. They run as the database owner
-- (security definer) and check who is calling with auth.uid().

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.current_player()
returns uuid language plpgsql stable security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  banned boolean;
begin
  if uid is null then
    raise exception 'not_signed_in' using errcode = '28000';
  end if;
  select is_banned into banned from public.profiles where id = uid;
  if not found then
    raise exception 'no_profile' using errcode = 'P0001';
  end if;
  if banned then
    raise exception 'account_banned' using errcode = 'P0001';
  end if;
  return uid;
end;
$$;

create or replace function public.require_not_paused(p_player uuid)
returns void language plpgsql stable
set search_path = public
as $$
declare
  until_at timestamptz;
begin
  select paused_until into until_at from public.profiles where id = p_player;
  if until_at is not null and until_at > public.kora_now() then
    raise exception 'account_paused_until %', until_at using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer
set search_path = public
as $$ select coalesce((select is_admin from public.profiles where id = auth.uid()), false) $$;

create or replace function public.require_admin()
returns uuid language plpgsql stable security definer
set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'admin_only' using errcode = '42501';
  end if;
  return auth.uid();
end;
$$;

create or replace function public.joined_count(p_match uuid)
returns integer language sql stable
set search_path = public
as $$ select count(*)::integer from public.match_players where match_id = p_match and status = 'joined' $$;

create or replace function public.is_in_match(p_match uuid, p_player uuid)
returns boolean language sql stable
set search_path = public
as $$
  select exists (select 1 from public.match_players
                 where match_id = p_match and player_id = p_player and status = 'joined')
$$;

-- Payment status for a new spot in a match.
create or replace function public.initial_payment(p_match public.matches, p_player uuid, p_method public.payment_method)
returns public.payment_status language sql stable
as $$
  select case
    when p_match.cost_split = 'host_pays' and p_player is distinct from p_match.host_id then 'not_required'::public.payment_status
    when p_method = 'none' then 'not_required'
    else 'unpaid'
  end
$$;

create or replace function public.spot_amount(p_match public.matches, p_player uuid)
returns integer language sql stable
as $$
  select case
    when p_match.cost_split = 'equal' then p_match.price_per_player_egp
    when p_player = p_match.host_id then p_match.total_cost_egp
    else 0
  end
$$;

-- When a match fills and the host did not come as a team, split the teams.
create or replace function public.after_roster_change(p_match uuid)
returns void language plpgsql
set search_path = public
as $$
declare
  m public.matches;
begin
  select * into m from public.matches where id = p_match;
  if m.came_as_team then
    return;
  end if;
  if public.joined_count(p_match) = public.match_capacity(m.format) then
    perform public.balance_teams(p_match);
    perform public.notify(mp.player_id, 'teams_ready', jsonb_build_object('match_id', p_match))
      from public.match_players mp
     where mp.match_id = p_match and mp.status = 'joined' and mp.player_id is not null;
  else
    -- Teams are only shown for a full roster (or after the host splits).
    update public.match_players set team = null where match_id = p_match;
    update public.matches set teams_split_at = null where id = p_match;
  end if;
end;
$$;

-- When the host came as a team, new players fill team A (the host's team)
-- up to half the capacity, then team B.
create or replace function public.team_for_new_spot(p_match public.matches)
returns public.team_side language sql stable
set search_path = public
as $$
  select case
    when not p_match.came_as_team then null
    when (select count(*) from public.match_players
           where match_id = p_match.id and status = 'joined' and team = 'A')
         < public.match_capacity(p_match.format) / 2 then 'A'::public.team_side
    else 'B'::public.team_side
  end
$$;

-- A late leaver's spot was taken: the earliest unreplaced late leaver is
-- marked replaced and, if they paid, is owed a refund.
create or replace function public.release_one_late_leaver(p_match uuid)
returns void language plpgsql
set search_path = public
as $$
declare
  leaver public.match_players;
begin
  select * into leaver from public.match_players
   where match_id = p_match and status = 'left_late' and not replaced
   order by left_at, id
   limit 1;
  if found then
    update public.match_players
       set replaced = true,
           payment_status = case when payment_status = 'paid' then 'refund_due'::public.payment_status
                                 else payment_status end
     where id = leaver.id;
    if leaver.player_id is not null then
      perform public.notify(leaver.player_id, 'spot_refilled', jsonb_build_object('match_id', p_match));
    end if;
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Profile
-- ---------------------------------------------------------------------------
create or replace function public.create_profile(
  p_display_name text,
  p_favorite_position public.position,
  p_other_positions public.position[],
  p_birth_date date,
  p_language text default 'ar'
) returns public.profiles
language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  result public.profiles;
begin
  if uid is null then
    raise exception 'not_signed_in' using errcode = '28000';
  end if;
  if p_birth_date > (public.kora_now() - make_interval(years => public.cfg_num('min_age_years')::integer))::date then
    raise exception 'too_young' using errcode = 'P0001';
  end if;
  insert into public.profiles (id, display_name, favorite_position, other_positions, birth_date, language)
  values (uid, trim(p_display_name), p_favorite_position,
          array_remove(coalesce(p_other_positions, '{}'), p_favorite_position), p_birth_date, p_language)
  returning * into result;
  return result;
end;
$$;

create or replace function public.update_profile(
  p_display_name text,
  p_photo_url text,
  p_favorite_position public.position,
  p_other_positions public.position[],
  p_language text
) returns public.profiles
language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  result public.profiles;
begin
  update public.profiles set
    display_name      = coalesce(trim(p_display_name), display_name),
    photo_url         = coalesce(p_photo_url, photo_url),
    favorite_position = coalesce(p_favorite_position, favorite_position),
    other_positions   = array_remove(coalesce(p_other_positions, other_positions),
                                     coalesce(p_favorite_position, favorite_position)),
    language          = coalesce(p_language, language)
  where id = uid
  returning * into result;
  return result;
end;
$$;

-- ---------------------------------------------------------------------------
-- Matches
-- ---------------------------------------------------------------------------
create or replace function public.create_match(
  p_pitch_id uuid,
  p_kickoff_at timestamptz,
  p_duration_minutes integer,
  p_format public.match_format,
  p_cost_split public.cost_split,
  p_allow_cash boolean,
  p_came_as_team boolean,
  p_host_position public.position
) returns public.matches
language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  pitch public.pitches;
  total integer;
  per_player integer;
  m public.matches;
begin
  perform public.require_not_paused(uid);
  select * into pitch from public.pitches where id = p_pitch_id and is_active;
  if not found then
    raise exception 'pitch_not_found' using errcode = 'P0002';
  end if;
  if p_kickoff_at <= public.kora_now() then
    raise exception 'kickoff_in_past' using errcode = 'P0001';
  end if;

  total := ceil(pitch.price_per_hour_egp * p_duration_minutes / 60.0)::integer;
  per_player := case p_cost_split
    when 'equal' then ceil(total::numeric / public.match_capacity(p_format))::integer
                      + public.cfg_num('service_fee_egp')::integer
    else 0
  end;

  insert into public.matches (pitch_id, host_id, kickoff_at, duration_minutes, format, cost_split,
                              total_cost_egp, price_per_player_egp, allow_cash, came_as_team)
  values (p_pitch_id, uid, p_kickoff_at, p_duration_minutes, p_format, p_cost_split,
          total, per_player, coalesce(p_allow_cash, false), coalesce(p_came_as_team, false))
  returning * into m;

  insert into public.match_players (match_id, player_id, added_by, position, team,
                                    payment_method, payment_status, amount_egp)
  values (m.id, uid, uid, p_host_position, case when m.came_as_team then 'A'::public.team_side end,
          'online', public.initial_payment(m, uid, 'online'), public.spot_amount(m, uid));

  return m;
end;
$$;

-- The host or an admin confirms the pitch booking. Until then players can
-- join, but payment is not taken.
create or replace function public.confirm_pitch(p_match uuid)
returns public.matches
language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.host_id <> uid and not public.is_admin() then
    raise exception 'host_or_admin_only' using errcode = '42501';
  end if;
  if m.status <> 'pending_pitch' then
    raise exception 'match_not_pending' using errcode = 'P0001';
  end if;
  update public.matches
     set status = 'open', pitch_confirmed_at = public.kora_now(), pitch_confirmed_by = uid
   where id = p_match
  returning * into m;
  perform public.notify(mp.player_id, 'pitch_confirmed', jsonb_build_object('match_id', p_match))
    from public.match_players mp
   where mp.match_id = p_match and mp.status = 'joined' and mp.player_id is not null;
  return m;
end;
$$;

create or replace function public.join_match(
  p_match uuid,
  p_position public.position,
  p_payment_method public.payment_method default 'online'
) returns public.match_players
language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
  spot public.match_players;
  previous public.match_players;
begin
  perform public.require_not_paused(uid);
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.status not in ('pending_pitch', 'open') then
    raise exception 'match_not_open' using errcode = 'P0001';
  end if;
  if m.kickoff_at <= public.kora_now() then
    raise exception 'match_started' using errcode = 'P0001';
  end if;
  if p_payment_method = 'cash' and not m.allow_cash then
    raise exception 'cash_not_allowed' using errcode = 'P0001';
  end if;
  if p_payment_method = 'none' then
    raise exception 'payment_method_required' using errcode = 'P0001';
  end if;
  if public.is_in_match(p_match, uid) then
    raise exception 'already_joined' using errcode = 'P0001';
  end if;
  if public.joined_count(p_match) >= public.match_capacity(m.format) then
    raise exception 'match_full' using errcode = 'P0001';
  end if;

  -- A player who left and comes back reuses their row.
  select * into previous from public.match_players where match_id = p_match and player_id = uid;
  if found then
    update public.match_players set
      status = 'joined', position = p_position, team = public.team_for_new_spot(m),
      payment_method = p_payment_method,
      payment_status = case when payment_status = 'paid' then 'paid'::public.payment_status
                            else public.initial_payment(m, uid, p_payment_method) end,
      amount_egp = public.spot_amount(m, uid),
      joined_at = public.kora_now(), left_at = null, replaced = false
    where id = previous.id
    returning * into spot;
  else
    insert into public.match_players (match_id, player_id, added_by, position, team,
                                      payment_method, payment_status, amount_egp, joined_at)
    values (p_match, uid, uid, p_position, public.team_for_new_spot(m),
            p_payment_method, public.initial_payment(m, uid, p_payment_method),
            public.spot_amount(m, uid), public.kora_now())
    returning * into spot;
  end if;

  perform public.release_one_late_leaver(p_match);
  perform public.after_roster_change(p_match);
  select * into spot from public.match_players where id = spot.id;
  return spot;
end;
$$;

-- The host adds a player who is already coming. If the phone number belongs
-- to an app player they get a real spot; otherwise the host adds a guest.
create or replace function public.host_add_player(
  p_match uuid,
  p_phone text,
  p_position public.position
) returns public.match_players
language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
  target uuid;
  spot public.match_players;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.host_id <> uid then raise exception 'host_only' using errcode = '42501'; end if;
  if m.status not in ('pending_pitch', 'open') or m.kickoff_at <= public.kora_now() then
    raise exception 'match_not_open' using errcode = 'P0001';
  end if;
  if public.joined_count(p_match) >= public.match_capacity(m.format) then
    raise exception 'match_full' using errcode = 'P0001';
  end if;

  select u.id into target from auth.users u
   join public.profiles p on p.id = u.id
   where regexp_replace(u.phone, '\D', '', 'g') = regexp_replace(p_phone, '\D', '', 'g');
  if target is null then
    raise exception 'player_not_on_app' using errcode = 'P0002';
  end if;
  if public.is_in_match(p_match, target) then
    raise exception 'already_joined' using errcode = 'P0001';
  end if;
  perform public.require_not_paused(target);

  insert into public.match_players (match_id, player_id, added_by, position, team,
                                    payment_method, payment_status, amount_egp, joined_at)
  values (p_match, target, uid, p_position, public.team_for_new_spot(m),
          'online', public.initial_payment(m, target, 'online'), public.spot_amount(m, target), public.kora_now())
  on conflict (match_id, player_id) where player_id is not null do update set
    status = 'joined', position = excluded.position, team = excluded.team,
    joined_at = excluded.joined_at, left_at = null, replaced = false, added_by = excluded.added_by
  returning * into spot;

  perform public.notify(target, 'added_to_match', jsonb_build_object('match_id', p_match, 'by', uid));
  perform public.release_one_late_leaver(p_match);
  perform public.after_roster_change(p_match);
  return spot;
end;
$$;

-- A guest: name only. Guests count as skill 3.0, are never rated, and pay the
-- host directly.
create or replace function public.host_add_guest(
  p_match uuid,
  p_guest_name text,
  p_position public.position
) returns public.match_players
language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
  spot public.match_players;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.host_id <> uid then raise exception 'host_only' using errcode = '42501'; end if;
  if m.status not in ('pending_pitch', 'open') or m.kickoff_at <= public.kora_now() then
    raise exception 'match_not_open' using errcode = 'P0001';
  end if;
  if public.joined_count(p_match) >= public.match_capacity(m.format) then
    raise exception 'match_full' using errcode = 'P0001';
  end if;
  if char_length(trim(coalesce(p_guest_name, ''))) < 2 then
    raise exception 'guest_name_required' using errcode = 'P0001';
  end if;

  insert into public.match_players (match_id, guest_name, added_by, position, team,
                                    payment_method, payment_status, amount_egp, joined_at)
  values (p_match, trim(p_guest_name), uid, p_position, public.team_for_new_spot(m),
          'none', 'not_required', 0, public.kora_now())
  returning * into spot;

  perform public.release_one_late_leaver(p_match);
  perform public.after_roster_change(p_match);
  return spot;
end;
$$;

-- The host removes a guest they added.
create or replace function public.host_remove_guest(p_spot uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  spot public.match_players;
  m public.matches;
begin
  select * into spot from public.match_players where id = p_spot;
  if not found or spot.guest_name is null then raise exception 'guest_not_found' using errcode = 'P0002'; end if;
  select * into m from public.matches where id = spot.match_id;
  if m.host_id <> uid then raise exception 'host_only' using errcode = '42501'; end if;
  delete from public.match_players where id = p_spot;
  perform public.after_roster_change(m.id);
end;
$$;

-- Leave a match. More than `free_leave_hours` before kickoff: free, and a
-- paid spot is refunded. Later: a late cancellation, refunded only if another
-- player takes the spot. The host cannot leave; they cancel instead.
create or replace function public.leave_match(p_match uuid)
returns public.match_players
language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
  spot public.match_players;
  is_free boolean;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.host_id = uid then raise exception 'host_must_cancel' using errcode = 'P0001'; end if;
  if m.kickoff_at <= public.kora_now() then raise exception 'match_started' using errcode = 'P0001'; end if;
  select * into spot from public.match_players
   where match_id = p_match and player_id = uid and status = 'joined' for update;
  if not found then raise exception 'not_in_match' using errcode = 'P0002'; end if;

  is_free := m.kickoff_at - public.kora_now() > make_interval(hours => public.cfg_num('free_leave_hours')::integer);

  update public.match_players set
    status = case when is_free then 'left_free' else 'left_late' end::public.player_status,
    left_at = public.kora_now(),
    team = null,
    payment_status = case
      when is_free and payment_status = 'paid' then 'refund_due'::public.payment_status
      when is_free and payment_status = 'unpaid' then 'not_required'
      else payment_status end
  where id = spot.id
  returning * into spot;

  perform public.after_roster_change(p_match);
  return spot;
end;
$$;

-- What the app shows before the player confirms leaving.
create or replace function public.leave_warning(p_match uuid)
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
declare
  m public.matches;
  is_free boolean;
begin
  select * into m from public.matches where id = p_match;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  is_free := m.kickoff_at - public.kora_now() > make_interval(hours => public.cfg_num('free_leave_hours')::integer);
  return jsonb_build_object(
    'free', is_free,
    'free_until', m.kickoff_at - make_interval(hours => public.cfg_num('free_leave_hours')::integer),
    'refund', case when is_free then 'full' else 'only_if_replaced' end,
    'lowers_on_time_rate', not is_free
  );
end;
$$;

create or replace function public.cancel_match_internal(p_match uuid, p_reason text)
returns void language plpgsql
set search_path = public
as $$
begin
  update public.matches set status = 'cancelled', cancelled_reason = p_reason where id = p_match;
  update public.match_players
     set payment_status = case when payment_status = 'paid' then 'refund_due'::public.payment_status
                               when payment_status = 'unpaid' then 'not_required'
                               else payment_status end
   where match_id = p_match;
  perform public.notify(mp.player_id, 'match_cancelled',
                        jsonb_build_object('match_id', p_match, 'reason', p_reason))
    from public.match_players mp
   where mp.match_id = p_match and mp.status = 'joined' and mp.player_id is not null;
end;
$$;

create or replace function public.cancel_match(p_match uuid, p_reason text default 'host_cancelled')
returns void language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.host_id <> uid and not public.is_admin() then
    raise exception 'host_or_admin_only' using errcode = '42501';
  end if;
  if m.status not in ('pending_pitch', 'open') then
    raise exception 'match_not_open' using errcode = 'P0001';
  end if;
  if m.kickoff_at <= public.kora_now() and not public.is_admin() then
    raise exception 'match_started' using errcode = 'P0001';
  end if;
  perform public.cancel_match_internal(p_match, coalesce(p_reason, 'host_cancelled'));
end;
$$;

-- The host splits teams before the roster is full (to play short).
create or replace function public.split_teams(p_match uuid)
returns numeric language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.host_id <> uid and not public.is_admin() then raise exception 'host_only' using errcode = '42501'; end if;
  if m.came_as_team then raise exception 'came_as_team_no_split' using errcode = 'P0001'; end if;
  if m.status not in ('pending_pitch', 'open') then raise exception 'match_not_open' using errcode = 'P0001'; end if;
  return public.balance_teams(p_match);
end;
$$;

-- The host marks that a cash player paid them at the pitch.
create or replace function public.host_mark_cash_paid(p_spot uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  spot public.match_players;
begin
  select * into spot from public.match_players where id = p_spot;
  if not found then raise exception 'spot_not_found' using errcode = 'P0002'; end if;
  if (select host_id from public.matches where id = spot.match_id) <> uid then
    raise exception 'host_only' using errcode = '42501';
  end if;
  if spot.payment_method <> 'cash' then raise exception 'not_cash' using errcode = 'P0001'; end if;
  update public.match_players set payment_status = 'paid' where id = p_spot and payment_status = 'unpaid';
end;
$$;

-- ---------------------------------------------------------------------------
-- After the match: ratings, attendance, disputes, score
-- ---------------------------------------------------------------------------
create or replace function public.rate_player(p_match uuid, p_rated uuid, p_stars integer)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
  now_at timestamptz := public.kora_now();
begin
  select * into m from public.matches where id = p_match;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.status <> 'open' then raise exception 'match_not_played' using errcode = 'P0001'; end if;
  if now_at < m.kickoff_at + make_interval(mins => m.duration_minutes) then
    raise exception 'rating_not_open_yet' using errcode = 'P0001';
  end if;
  if now_at > m.kickoff_at + make_interval(hours => public.cfg_num('rating_window_hours')::integer) then
    raise exception 'rating_closed' using errcode = 'P0001';
  end if;
  if uid = p_rated then raise exception 'cannot_rate_self' using errcode = 'P0001'; end if;
  if not public.is_in_match(p_match, uid) or not public.is_in_match(p_match, p_rated) then
    raise exception 'not_in_same_match' using errcode = 'P0001';
  end if;
  if p_stars not between 1 and 5 then raise exception 'stars_1_to_5' using errcode = 'P0001'; end if;

  -- One rating per pair per match; rating again before the window closes
  -- replaces it, so it still counts once.
  insert into public.ratings (match_id, rater_id, rated_id, stars, created_at)
  values (p_match, uid, p_rated, p_stars, now_at)
  on conflict (match_id, rater_id, rated_id) do update set stars = excluded.stars, created_at = excluded.created_at;
end;
$$;

create or replace function public.report_attendance(p_match uuid, p_reported uuid, p_kind public.report_kind)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
  now_at timestamptz := public.kora_now();
  needed integer := public.cfg_num('reports_needed')::integer;
  total integer;
begin
  select * into m from public.matches where id = p_match;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.status <> 'open' then raise exception 'match_not_played' using errcode = 'P0001'; end if;
  if now_at < m.kickoff_at then raise exception 'match_not_started' using errcode = 'P0001'; end if;
  if now_at > m.kickoff_at + make_interval(hours => public.cfg_num('rating_window_hours')::integer) then
    raise exception 'reporting_closed' using errcode = 'P0001';
  end if;
  if uid = p_reported then raise exception 'cannot_report_self' using errcode = 'P0001'; end if;
  if not public.is_in_match(p_match, uid) or not public.is_in_match(p_match, p_reported) then
    raise exception 'not_in_same_match' using errcode = 'P0001';
  end if;

  insert into public.attendance_reports (match_id, reporter_id, reported_id, kind, created_at)
  values (p_match, uid, p_reported, p_kind, now_at)
  on conflict (match_id, reporter_id, reported_id) do update set kind = excluded.kind, created_at = excluded.created_at;

  -- Tell the player once the report counts, so they can dispute it.
  select count(*) into total from public.attendance_reports
   where match_id = p_match and reported_id = p_reported and kind = p_kind;
  if total = needed then
    perform public.notify(p_reported, 'attendance_reported',
                          jsonb_build_object('match_id', p_match, 'kind', p_kind,
                                             'dispute_until', m.kickoff_at + make_interval(hours =>
                                               (public.cfg_num('rating_window_hours') + public.cfg_num('dispute_window_hours'))::integer)));
  end if;
end;
$$;

create or replace function public.dispute_attendance(p_match uuid, p_reason text)
returns public.attendance_disputes
language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
  d public.attendance_disputes;
begin
  select * into m from public.matches where id = p_match;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.finalized_at is not null then raise exception 'match_finalized' using errcode = 'P0001'; end if;
  if public.kora_now() > m.kickoff_at + make_interval(hours =>
       (public.cfg_num('rating_window_hours') + public.cfg_num('dispute_window_hours'))::integer) then
    raise exception 'dispute_closed' using errcode = 'P0001';
  end if;
  if public.attendance_for(p_match, uid) = 'on_time' then
    raise exception 'nothing_to_dispute' using errcode = 'P0001';
  end if;
  insert into public.attendance_disputes (match_id, player_id, reason)
  values (p_match, uid, coalesce(nullif(trim(p_reason), ''), '-'))
  returning * into d;
  return d;
end;
$$;

-- Score is saved for Version 2 (loser pays). It is set once one player from
-- each team reports the same score.
create or replace function public.report_score(p_match uuid, p_score_a integer, p_score_b integer)
returns jsonb language plpgsql security definer
set search_path = public
as $$
declare
  uid uuid := public.current_player();
  m public.matches;
  my_team public.team_side;
  agreed boolean;
begin
  select * into m from public.matches where id = p_match for update;
  if not found then raise exception 'match_not_found' using errcode = 'P0002'; end if;
  if m.status <> 'open' or public.kora_now() < m.kickoff_at + make_interval(mins => m.duration_minutes) then
    raise exception 'match_not_played' using errcode = 'P0001';
  end if;
  select team into my_team from public.match_players
   where match_id = p_match and player_id = uid and status = 'joined';
  if my_team is null then raise exception 'not_on_a_team' using errcode = 'P0001'; end if;

  insert into public.score_reports (match_id, reporter_id, team, score_a, score_b)
  values (p_match, uid, my_team, p_score_a, p_score_b)
  on conflict (match_id, reporter_id) do update set score_a = excluded.score_a, score_b = excluded.score_b,
                                                     created_at = now();

  select exists (
    select 1 from public.score_reports a
    join public.score_reports b on b.match_id = a.match_id and b.team = 'B'
                               and b.score_a = a.score_a and b.score_b = a.score_b
    where a.match_id = p_match and a.team = 'A' and a.score_a = p_score_a and a.score_b = p_score_b
  ) into agreed;

  if agreed then
    update public.matches set score_a = p_score_a, score_b = p_score_b where id = p_match;
  end if;
  return jsonb_build_object('confirmed', agreed);
end;
$$;

create or replace function public.mark_notifications_read(p_ids bigint[])
returns void language sql security definer
set search_path = public
as $$
  update public.notifications set read_at = now()
   where user_id = auth.uid() and id = any(p_ids) and read_at is null
$$;

-- ---------------------------------------------------------------------------
-- Finalizing a match: runs on a schedule once the rating, report and dispute
-- windows have closed and no dispute is open.
-- ---------------------------------------------------------------------------
create or replace function public.finalize_match(p_match uuid)
returns integer language plpgsql
set search_path = public
as $$
declare
  m public.matches;
  spot record;
  att public.attendance;
  r_count integer;
  r_avg numeric;
  delta integer;
  recent_no_shows integer;
  done integer := 0;
begin
  select * into m from public.matches where id = p_match for update;
  if m.status <> 'open' or m.finalized_at is not null then
    return 0;
  end if;
  if exists (select 1 from public.attendance_disputes where match_id = p_match and status = 'open') then
    return 0;
  end if;

  for spot in
    select * from public.match_players
     where match_id = p_match and status = 'joined' and player_id is not null
  loop
    att := public.attendance_for(p_match, spot.player_id);
    select count(*), avg(stars) into r_count, r_avg
      from public.ratings where match_id = p_match and rated_id = spot.player_id;
    -- A no-show's ratings never count.
    if att = 'no_show' then r_count := 0; r_avg := null; end if;
    delta := public.match_points(att, r_avg);

    insert into public.match_results (match_id, player_id, attendance, rating_count, avg_stars, points_delta, kickoff_at)
    values (p_match, spot.player_id, att, r_count, round(r_avg, 2), delta, m.kickoff_at);

    update public.profiles set points = greatest(0, points + delta) where id = spot.player_id;

    if att = 'no_show' then
      select count(*) into recent_no_shows from public.match_results
       where player_id = spot.player_id and attendance = 'no_show'
         and kickoff_at > m.kickoff_at - make_interval(days => public.cfg_num('no_show_window_days')::integer)
         and kickoff_at <= m.kickoff_at;
      if recent_no_shows >= public.cfg_num('no_show_pause_at') then
        update public.profiles
           set paused_until = greatest(coalesce(paused_until, public.kora_now()), public.kora_now())
                              + make_interval(days => public.cfg_num('pause_days')::integer)
         where id = spot.player_id;
        perform public.notify(spot.player_id, 'account_paused',
                              jsonb_build_object('no_shows', recent_no_shows, 'days', public.cfg_num('pause_days')));
      elsif recent_no_shows >= public.cfg_num('no_show_warning_at') then
        perform public.notify(spot.player_id, 'no_show_warning', jsonb_build_object('no_shows', recent_no_shows));
      end if;
    end if;

    perform public.notify(spot.player_id, 'match_result',
                          jsonb_build_object('match_id', p_match, 'attendance', att, 'points', delta));
    done := done + 1;
  end loop;

  -- Late leavers whose spot was never taken keep no refund.
  update public.match_players set payment_status = 'forfeited'
   where match_id = p_match and status = 'left_late' and not replaced and payment_status = 'paid';

  update public.matches set status = 'closed', finalized_at = public.kora_now() where id = p_match;
  return done;
end;
$$;

-- Scheduled jobs (pg_cron, see 0005). Each returns how many matches it touched.
create or replace function public.finalize_due_matches()
returns integer language plpgsql
set search_path = public
as $$
declare
  mid uuid;
  n integer := 0;
begin
  for mid in
    select id from public.matches
     where status = 'open' and finalized_at is null
       and kickoff_at + make_interval(hours =>
             (public.cfg_num('rating_window_hours') + public.cfg_num('dispute_window_hours'))::integer)
           <= public.kora_now()
     order by kickoff_at
  loop
    perform public.finalize_match(mid);
    if exists (select 1 from public.matches where id = mid and status = 'closed') then
      n := n + 1;
    end if;
  end loop;
  return n;
end;
$$;

create or replace function public.cancel_unconfirmed_matches()
returns integer language plpgsql
set search_path = public
as $$
declare
  mid uuid;
  n integer := 0;
begin
  for mid in
    select id from public.matches
     where status = 'pending_pitch'
       and kickoff_at - make_interval(hours => public.cfg_num('pitch_confirm_deadline_hours')::integer) <= public.kora_now()
  loop
    perform public.cancel_match_internal(mid, 'pitch_not_confirmed');
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Queue a reminder about 2 hours before kickoff, and tell the host if the
-- match is not full 3 hours before kickoff (play short or cancel).
create or replace function public.queue_reminders()
returns integer language plpgsql
set search_path = public
as $$
declare
  m public.matches;
  n integer := 0;
begin
  for m in
    select * from public.matches
     where status = 'open' and reminder_sent_at is null
       and kickoff_at > public.kora_now()
       and kickoff_at - interval '3 hours' <= public.kora_now()
  loop
    perform public.notify(mp.player_id, 'kickoff_reminder', jsonb_build_object('match_id', m.id, 'kickoff_at', m.kickoff_at))
      from public.match_players mp
     where mp.match_id = m.id and mp.status = 'joined' and mp.player_id is not null;
    if public.joined_count(m.id) < public.match_capacity(m.format) then
      perform public.notify(m.host_id, 'match_not_full',
                            jsonb_build_object('match_id', m.id, 'joined', public.joined_count(m.id)));
    end if;
    update public.matches set reminder_sent_at = public.kora_now() where id = m.id;
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- ---------------------------------------------------------------------------
-- Payments: called by the payment webhook (edge function, service role).
-- ---------------------------------------------------------------------------
create or replace function public.payment_mark_paid(p_spot uuid, p_amount_egp integer)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  spot public.match_players;
  m public.matches;
begin
  select * into spot from public.match_players where id = p_spot for update;
  if not found then raise exception 'spot_not_found' using errcode = 'P0002'; end if;
  select * into m from public.matches where id = spot.match_id;
  if p_amount_egp < spot.amount_egp then raise exception 'amount_too_low' using errcode = 'P0001'; end if;
  if spot.status = 'joined' and m.status = 'open' then
    update public.match_players set payment_status = 'paid' where id = p_spot;
  else
    -- Paid after leaving or after the match was cancelled: owe it back.
    update public.match_players set payment_status = 'refund_due' where id = p_spot;
  end if;
end;
$$;

-- Whether the payment provider may take payment for this spot now.
create or replace function public.can_pay(p_spot uuid)
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.match_players mp join public.matches m on m.id = mp.match_id
     where mp.id = p_spot and mp.player_id = auth.uid() and mp.status = 'joined'
       and mp.payment_method = 'online' and mp.payment_status = 'unpaid' and m.status = 'open'
  )
$$;

-- ---------------------------------------------------------------------------
-- Admin
-- ---------------------------------------------------------------------------
create or replace function public.admin_upsert_pitch(
  p_id uuid, p_name text, p_area text, p_address text, p_lat double precision, p_lng double precision,
  p_price_per_hour_egp integer, p_photo_urls text[], p_contact_phone text, p_is_active boolean
) returns public.pitches
language plpgsql security definer
set search_path = public
as $$
declare
  result public.pitches;
begin
  perform public.require_admin();
  insert into public.pitches (id, name, area, address, lat, lng, price_per_hour_egp, photo_urls, contact_phone, is_active)
  values (coalesce(p_id, gen_random_uuid()), p_name, p_area, p_address, p_lat, p_lng, p_price_per_hour_egp,
          coalesce(p_photo_urls, '{}'), p_contact_phone, coalesce(p_is_active, true))
  on conflict (id) do update set
    name = excluded.name, area = excluded.area, address = excluded.address, lat = excluded.lat, lng = excluded.lng,
    price_per_hour_egp = excluded.price_per_hour_egp, photo_urls = excluded.photo_urls,
    contact_phone = excluded.contact_phone, is_active = excluded.is_active
  returning * into result;
  return result;
end;
$$;

create or replace function public.admin_resolve_dispute(p_dispute uuid, p_upheld boolean)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  admin_id uuid := public.require_admin();
  d public.attendance_disputes;
begin
  update public.attendance_disputes
     set status = case when p_upheld then 'upheld' else 'rejected' end::public.dispute_status,
         resolved_by = admin_id, resolved_at = public.kora_now()
   where id = p_dispute and status = 'open'
  returning * into d;
  if not found then raise exception 'dispute_not_open' using errcode = 'P0002'; end if;
  perform public.notify(d.player_id, 'dispute_resolved',
                        jsonb_build_object('match_id', d.match_id, 'upheld', p_upheld));
end;
$$;

create or replace function public.admin_set_banned(p_player uuid, p_banned boolean)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  perform public.require_admin();
  update public.profiles set is_banned = p_banned where id = p_player;
end;
$$;

create or replace function public.admin_mark_refunded(p_spot uuid)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  perform public.require_admin();
  update public.match_players set payment_status = 'refunded' where id = p_spot and payment_status = 'refund_due';
  if not found then raise exception 'no_refund_due' using errcode = 'P0001'; end if;
end;
$$;

create or replace function public.admin_collusion_flags()
returns setof public.collusion_flags language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.require_admin();
  return query select * from public.collusion_flags order by last_match_at desc;
end;
$$;
