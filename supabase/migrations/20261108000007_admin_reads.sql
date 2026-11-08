-- Kora: read functions for the admin panel. Each one checks is_admin first.
-- Admins need columns that players cannot read (pitch contact phone, phone
-- numbers, payment status), so these go through security definer functions.

create or replace function public.admin_pitches()
returns setof public.pitches
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.require_admin();
  return query select * from public.pitches order by is_active desc, area, name;
end;
$$;

create or replace function public.admin_matches(p_from timestamptz default null)
returns table (
  id uuid, kickoff_at timestamptz, duration_minutes integer, format public.match_format,
  status public.match_status, pitch_confirmed boolean, cost_split public.cost_split,
  price_per_player_egp integer, total_cost_egp integer,
  pitch_name text, pitch_area text, pitch_phone text,
  host_id uuid, host_name text, host_phone text,
  joined integer, capacity integer, cancelled_reason text, score_a integer, score_b integer
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.require_admin();
  return query
  select m.id, m.kickoff_at, m.duration_minutes, m.format, m.status, m.pitch_confirmed_at is not null,
         m.cost_split, m.price_per_player_egp, m.total_cost_egp,
         p.name, p.area, p.contact_phone,
         m.host_id, h.display_name, u.phone::text,
         public.joined_count(m.id), public.match_capacity(m.format), m.cancelled_reason, m.score_a, m.score_b
  from public.matches m
  join public.pitches p on p.id = m.pitch_id
  join public.profiles h on h.id = m.host_id
  left join auth.users u on u.id = m.host_id
  where m.kickoff_at >= coalesce(p_from, public.kora_now() - interval '3 days')
  order by m.kickoff_at;
end;
$$;

create or replace function public.admin_disputes()
returns table (
  id uuid, match_id uuid, kickoff_at timestamptz, pitch_name text,
  player_id uuid, player_name text, player_phone text, reason text, created_at timestamptz,
  late_reports integer, no_show_reports integer
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.require_admin();
  return query
  select d.id, d.match_id, m.kickoff_at, p.name,
         d.player_id, pr.display_name, u.phone::text, d.reason, d.created_at,
         (select count(*)::integer from public.attendance_reports r
           where r.match_id = d.match_id and r.reported_id = d.player_id and r.kind = 'late'),
         (select count(*)::integer from public.attendance_reports r
           where r.match_id = d.match_id and r.reported_id = d.player_id and r.kind = 'no_show')
  from public.attendance_disputes d
  join public.matches m on m.id = d.match_id
  join public.pitches p on p.id = m.pitch_id
  join public.profiles pr on pr.id = d.player_id
  left join auth.users u on u.id = d.player_id
  where d.status = 'open'
  order by d.created_at;
end;
$$;

create or replace function public.admin_refunds_due()
returns table (
  spot_id uuid, match_id uuid, kickoff_at timestamptz, pitch_name text, match_status public.match_status,
  player_id uuid, player_name text, player_phone text, amount_egp integer, payment_method public.payment_method
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.require_admin();
  return query
  select mp.id, m.id, m.kickoff_at, p.name, m.status,
         mp.player_id, pr.display_name, u.phone::text, mp.amount_egp, mp.payment_method
  from public.match_players mp
  join public.matches m on m.id = mp.match_id
  join public.pitches p on p.id = m.pitch_id
  left join public.profiles pr on pr.id = mp.player_id
  left join auth.users u on u.id = mp.player_id
  where mp.payment_status = 'refund_due'
  order by m.kickoff_at;
end;
$$;

create or replace function public.admin_players(p_query text default null)
returns table (
  id uuid, display_name text, phone text, points integer, level text,
  games_played bigint, no_shows_30d bigint, paused_until timestamptz,
  is_banned boolean, is_admin boolean, created_at timestamptz
)
language plpgsql stable security definer
set search_path = public
as $$
declare
  q text := nullif(trim(coalesce(p_query, '')), '');
begin
  perform public.require_admin();
  return query
  select pr.id, pr.display_name, u.phone::text, pr.points, public.level_for_points(pr.points),
         (select count(*) from public.match_results r where r.player_id = pr.id and r.attendance <> 'no_show'),
         (select count(*) from public.match_results r where r.player_id = pr.id and r.attendance = 'no_show'
            and r.kickoff_at > public.kora_now() - make_interval(days => public.cfg_num('no_show_window_days')::integer)),
         pr.paused_until, pr.is_banned, pr.is_admin, pr.created_at
  from public.profiles pr
  left join auth.users u on u.id = pr.id
  where q is null
     or pr.display_name ilike '%' || q || '%'
     or regexp_replace(coalesce(u.phone, ''), '\D', '', 'g') like '%' || regexp_replace(q, '\D', '', 'g') || '%'
        and regexp_replace(q, '\D', '', 'g') <> ''
  order by pr.created_at desc
  limit 200;
end;
$$;

create or replace function public.admin_collusion_report()
returns table (player_a uuid, name_a text, player_b uuid, name_b text, streak bigint, last_match_at timestamptz)
language plpgsql stable security definer
set search_path = public
as $$
begin
  perform public.require_admin();
  return query
  select f.player_a, a.display_name, f.player_b, b.display_name, f.streak, f.last_match_at
  from public.collusion_flags f
  join public.profiles a on a.id = f.player_a
  join public.profiles b on b.id = f.player_b
  order by f.last_match_at desc;
end;
$$;

revoke execute on function public.admin_pitches() from public, anon;
revoke execute on function public.admin_matches(timestamptz) from public, anon;
revoke execute on function public.admin_disputes() from public, anon;
revoke execute on function public.admin_refunds_due() from public, anon;
revoke execute on function public.admin_players(text) from public, anon;
revoke execute on function public.admin_collusion_report() from public, anon;

grant execute on function public.admin_pitches() to authenticated;
grant execute on function public.admin_matches(timestamptz) to authenticated;
grant execute on function public.admin_disputes() to authenticated;
grant execute on function public.admin_refunds_due() to authenticated;
grant execute on function public.admin_players(text) to authenticated;
grant execute on function public.admin_collusion_report() to authenticated;
