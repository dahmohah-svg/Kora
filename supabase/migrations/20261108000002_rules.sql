-- Kora: rule functions (no side effects). See docs/rules.md for the rules
-- as written in the MVP plan.

-- Levels: Rookie 0, Regular 50, Starter 150, Captain 300, Legend 600.
create or replace function public.level_for_points(p_points integer)
returns text language sql immutable
as $$
  select case
    when p_points >= 600 then 'legend'
    when p_points >= 300 then 'captain'
    when p_points >= 150 then 'starter'
    when p_points >= 50  then 'regular'
    else 'rookie'
  end
$$;

-- Rating points for one match: multiplier * (average stars - 3), rounded half
-- away from zero. 1 star = -6, 3 stars = 0, 5 stars = +6. No ratings = 0.
create or replace function public.rating_points(p_avg_stars numeric)
returns integer language sql stable
set search_path = public
as $$
  select case when p_avg_stars is null then 0
    else round(public.cfg_num('rating_points_multiplier') * (p_avg_stars - 3))::integer
  end
$$;

-- Points for one player in one finalized match.
create or replace function public.match_points(p_attendance public.attendance, p_avg_stars numeric)
returns integer language sql stable
set search_path = public
as $$
  select case p_attendance
    when 'no_show' then public.cfg_num('points_no_show')::integer
    when 'late'    then (public.cfg_num('points_played') + public.cfg_num('points_late'))::integer
                        + public.rating_points(p_avg_stars)
    else                (public.cfg_num('points_played') + public.cfg_num('points_on_time'))::integer
                        + public.rating_points(p_avg_stars)
  end
$$;

-- Attendance from reports: on time unless at least `reports_needed` different
-- players reported the same thing. No-show wins over late. An upheld dispute
-- (the admin agreed with the player) clears the reports.
create or replace function public.attendance_for(p_match uuid, p_player uuid)
returns public.attendance language sql stable
set search_path = public
as $$
  with needed as (select public.cfg_num('reports_needed')::integer as n),
  cleared as (
    select exists (select 1 from public.attendance_disputes d
                   where d.match_id = p_match and d.player_id = p_player and d.status = 'upheld') as yes
  ),
  counts as (
    select
      count(*) filter (where kind = 'no_show') as no_show,
      count(*) filter (where kind = 'late')    as late
    from public.attendance_reports
    where match_id = p_match and reported_id = p_player
  )
  select case
    when (select yes from cleared) then 'on_time'::public.attendance
    when c.no_show >= (select n from needed) then 'no_show'
    when c.late    >= (select n from needed) then 'late'
    else 'on_time'
  end
  from counts c
$$;

-- Skill score used for team balancing: average of the per-match average stars
-- over the last `skill_recent_matches` rated matches. Fewer than
-- `min_rated_matches_shown` rated matches = `skill_default` (3.0).
create or replace function public.skill_score(p_player uuid)
returns numeric language sql stable
set search_path = public
as $$
  with recent as (
    select avg_stars from public.match_results
    where player_id = p_player and rating_count > 0
    order by kickoff_at desc
    limit public.cfg_num('skill_recent_matches')::integer
  )
  select case
    when p_player is null then public.cfg_num('skill_default')
    when (select count(*) from recent) < public.cfg_num('min_rated_matches_shown') then public.cfg_num('skill_default')
    else (select round(avg(avg_stars), 2) from recent)
  end
$$;

-- ---------------------------------------------------------------------------
-- Team balancing.
-- Splits the joined spots of a match into teams A and B so that:
--   1. team sizes differ by at most 1,
--   2. goalkeepers are spread as evenly as possible (|A - B| <= 1),
--   3. the difference in total skill is as small as possible,
--   4. ties go to the split with the closer total points.
-- Guests count as skill 3.0 and 0 points. At most 12 spots, so every split is
-- checked (at most 2^11 = 2048).
-- Returns the chosen skill difference.
-- ---------------------------------------------------------------------------
create or replace function public.balance_teams(p_match uuid)
returns numeric language plpgsql
set search_path = public
as $$
declare
  ids     uuid[];
  skills  numeric[];
  pts     integer[];
  gk      boolean[];
  n       integer;
  mask    integer;
  best_mask integer := null;
  best_skill numeric;
  best_pts  integer;
  size_a  integer;
  gk_a    integer;
  gk_b    integer;
  sk_a    numeric;
  sk_b    numeric;
  p_a     integer;
  p_b     integer;
  d_sk    numeric;
  d_pts   integer;
  i       integer;
begin
  select array_agg(mp.id order by mp.joined_at, mp.id),
         array_agg(public.skill_score(mp.player_id) order by mp.joined_at, mp.id),
         array_agg(coalesce(pr.points, 0) order by mp.joined_at, mp.id),
         array_agg(mp.position = 'goalkeeper' order by mp.joined_at, mp.id)
    into ids, skills, pts, gk
  from public.match_players mp
  left join public.profiles pr on pr.id = mp.player_id
  where mp.match_id = p_match and mp.status = 'joined';

  n := coalesce(array_length(ids, 1), 0);
  if n = 0 then
    return 0;
  end if;
  if n = 1 then
    update public.match_players set team = 'A' where id = ids[1];
    return 0;
  end if;

  -- Bit i (0-based) set = spot i+1 on team A. The first spot is always on A,
  -- which removes mirror-image duplicates.
  mask := 1;
  while mask < (1 << n) loop
    if (mask & 1) = 1 then
      size_a := 0; gk_a := 0; gk_b := 0; sk_a := 0; sk_b := 0; p_a := 0; p_b := 0;
      for i in 1..n loop
        if (mask >> (i - 1)) & 1 = 1 then
          size_a := size_a + 1;
          sk_a := sk_a + skills[i];
          p_a := p_a + pts[i];
          if gk[i] then gk_a := gk_a + 1; end if;
        else
          sk_b := sk_b + skills[i];
          p_b := p_b + pts[i];
          if gk[i] then gk_b := gk_b + 1; end if;
        end if;
      end loop;

      if abs(size_a - (n - size_a)) <= 1 and abs(gk_a - gk_b) <= 1 then
        d_sk := abs(sk_a - sk_b);
        d_pts := abs(p_a - p_b);
        if best_mask is null
           or d_sk < best_skill
           or (d_sk = best_skill and d_pts < best_pts) then
          best_mask := mask; best_skill := d_sk; best_pts := d_pts;
        end if;
      end if;
    end if;
    mask := mask + 1;
  end loop;

  for i in 1..n loop
    update public.match_players
       set team = case when (best_mask >> (i - 1)) & 1 = 1 then 'A' else 'B' end::public.team_side
     where id = ids[i];
  end loop;

  update public.matches set teams_split_at = public.kora_now() where id = p_match;
  return best_skill;
end;
$$;

-- ---------------------------------------------------------------------------
-- Player statistics shown on profiles.
-- on_time_rate = on-time matches / (finalized matches + late cancellations).
-- The average rating is shown only after `min_rated_matches_shown` rated
-- matches; single ratings are never exposed.
-- ---------------------------------------------------------------------------
create or replace view public.player_stats as
with res as (
  select player_id,
         count(*)                                         as finalized,
         count(*) filter (where attendance <> 'no_show')  as games_played,
         count(*) filter (where attendance = 'on_time')   as on_time,
         count(*) filter (where attendance = 'no_show')   as no_shows,
         count(*) filter (where rating_count > 0)         as rated_matches
  from public.match_results group by player_id
),
late_cancels as (
  select mp.player_id, count(*) as n
  from public.match_players mp
  join public.matches m on m.id = mp.match_id
  where mp.status = 'left_late' and m.status = 'closed' and mp.player_id is not null
  group by mp.player_id
),
stars as (
  select r.rated_id as player_id, round(avg(r.stars), 2) as avg_stars, count(*) as rating_count
  from public.ratings r
  join public.matches m on m.id = r.match_id and m.finalized_at is not null
  group by r.rated_id
)
select
  p.id                                   as player_id,
  p.display_name,
  p.photo_url,
  p.favorite_position,
  p.other_positions,
  p.points,
  public.level_for_points(p.points)      as level,
  coalesce(res.games_played, 0)          as games_played,
  case when coalesce(res.finalized, 0) + coalesce(lc.n, 0) = 0 then null
       else round(coalesce(res.on_time, 0)::numeric / (coalesce(res.finalized, 0) + coalesce(lc.n, 0)), 2)
  end                                    as on_time_rate,
  coalesce(res.rated_matches, 0)         as rated_matches,
  case when coalesce(res.rated_matches, 0) >= public.cfg_num('min_rated_matches_shown')
       then s.avg_stars end              as avg_rating,
  case when coalesce(res.rated_matches, 0) >= public.cfg_num('min_rated_matches_shown')
       then s.rating_count end           as rating_count
from public.profiles p
left join res          on res.player_id = p.id
left join late_cancels lc on lc.player_id = p.id
left join stars s      on s.player_id = p.id
where not p.is_banned;

-- Pairs of players who gave each other 5 stars in `collusion_streak` or more
-- shared matches in a row. For the admin panel only.
create or replace view public.collusion_flags as
with shared as (
  -- every finalized match two app players were both in, a < b
  select m.id as match_id, m.kickoff_at, a.player_id as a, b.player_id as b
  from public.matches m
  join public.match_players a on a.match_id = m.id and a.status = 'joined' and a.player_id is not null
  join public.match_players b on b.match_id = m.id and b.status = 'joined' and b.player_id is not null
                              and a.player_id < b.player_id
  where m.finalized_at is not null
),
marked as (
  select s.*,
         exists (select 1 from public.ratings r where r.match_id = s.match_id and r.rater_id = s.a and r.rated_id = s.b and r.stars = 5)
     and exists (select 1 from public.ratings r where r.match_id = s.match_id and r.rater_id = s.b and r.rated_id = s.a and r.stars = 5)
         as mutual_five
  from shared s
),
grouped as (
  select *,
         row_number() over (partition by a, b order by kickoff_at)
       - row_number() over (partition by a, b, mutual_five order by kickoff_at) as grp
  from marked
)
select a as player_a, b as player_b, count(*) as streak, max(kickoff_at) as last_match_at
from grouped
where mutual_five
group by a, b, grp
having count(*) >= public.cfg_num('collusion_streak');
