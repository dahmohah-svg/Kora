-- Team balancing by skill, goalkeepers, and "We came as a team".
create temp table ctx (k text primary key, id uuid);

select t.at('2026-12-01 18:00+02');
insert into ctx values ('pitch', t.pitch(500));

-- Give a player a skill score by inserting rated results directly.
create or replace function pg_temp.set_skill(p_player uuid, p_stars numeric) returns void language sql as $$
  insert into public.matches (id, pitch_id, host_id, kickoff_at, format, total_cost_egp, price_per_player_egp, status, finalized_at)
  select gen_random_uuid(), (select id from ctx where k = 'pitch'), p_player, '2026-11-01'::timestamptz + (n || ' days')::interval, '5v5', 0, 0, 'closed', now()
  from generate_series(1, 3) n;
  insert into public.match_results (match_id, player_id, attendance, rating_count, avg_stars, points_delta, kickoff_at)
  select m.id, p_player, 'on_time', 3, p_stars, 0, m.kickoff_at
  from public.matches m where m.host_id = p_player and m.status = 'closed';
$$;

-- Ten players: 2 stars (x2), 5 stars (x2), the rest new (3.0). Two keepers.
insert into ctx values ('host', t.player('Host', 'forward'));
select t.login((select id from ctx where k = 'host'));
insert into ctx select 'match', (public.create_match((select id from ctx where k = 'pitch'),
  '2026-12-05 20:00+02', 60, '5v5', 'equal', false, false, 'forward')).id;

do $$
declare
  stars numeric[] := array[5, 5, 2, 2, null, null, null, null, null];
  pos public.position[] := array['midfielder','midfielder','midfielder','midfielder','goalkeeper','goalkeeper','defender','defender','defender']::public.position[];
  pid uuid;
begin
  for i in 1..9 loop
    pid := t.player('P' || i, pos[i]);
    if stars[i] is not null then perform pg_temp.set_skill(pid, stars[i]); end if;
    perform t.login(pid);
    perform public.join_match((select id from ctx where k = 'match'), pos[i]);
  end loop;
end $$;

select t.eq(public.skill_score((select player_id from public.match_players mp join public.profiles p on p.id = mp.player_id where p.display_name = 'P1')), 5.00, 'skill = average of rated matches');
select t.eq(public.skill_score((select id from ctx where k = 'host')), 3.0, 'new player counts as 3.0');

with teams as (
  select mp.team, sum(public.skill_score(mp.player_id)) skill,
         count(*) filter (where mp.position = 'goalkeeper') gk,
         count(*) filter (where p.display_name in ('P1', 'P2')) stars5
  from public.match_players mp join public.profiles p on p.id = mp.player_id
  where mp.match_id = (select id from ctx where k = 'match') group by mp.team
)
select t.eq((select max(skill) - min(skill) from teams), 0.00, 'teams have equal total skill'),
       t.eq((select max(gk) from teams), 1::bigint, 'one goalkeeper per team'),
       t.eq((select max(stars5) from teams), 1::bigint, 'the two 5-star players are split');

-- Three goalkeepers in a short game: spread as evenly as possible.
select t.login((select id from ctx where k = 'host'));
insert into ctx select 'short', (public.create_match((select id from ctx where k = 'pitch'),
  '2026-12-06 20:00+02', 60, '5v5', 'equal', false, false, 'goalkeeper')).id;
select t.fill((select id from ctx where k = 'short'), 2, 'goalkeeper');
select t.fill((select id from ctx where k = 'short'), 3, 'forward');
select t.login((select id from ctx where k = 'host'));
select public.split_teams((select id from ctx where k = 'short'));
with teams as (
  select team, count(*) n, count(*) filter (where position = 'goalkeeper') gk
  from public.match_players where match_id = (select id from ctx where k = 'short') group by team
)
select t.eq((select max(gk) - min(gk) from teams), 1::bigint, '3 keepers split 2 and 1'),
       t.eq((select max(n) - min(n) from teams), 0::bigint, '6 players split 3 and 3');

-- Came as a team: no auto-split; new players fill team A to 5, then B.
select t.login((select id from ctx where k = 'host'));
insert into ctx select 'team', (public.create_match((select id from ctx where k = 'pitch'),
  '2026-12-07 20:00+02', 60, '5v5', 'equal', false, true, 'forward')).id;
select public.host_add_guest((select id from ctx where k = 'team'), 'Mido', 'defender');
select public.host_add_guest((select id from ctx where k = 'team'), 'Hamada', 'defender');
select public.host_add_guest((select id from ctx where k = 'team'), 'Zizo', 'midfielder');
select t.fill((select id from ctx where k = 'team'), 3);
select t.eq((select count(*)::int from public.match_players where match_id = (select id from ctx where k = 'team') and team = 'A'), 5, 'team A filled to 5 first');
select t.eq((select count(*)::int from public.match_players where match_id = (select id from ctx where k = 'team') and team = 'B'), 2, 'then team B');
select t.login((select id from ctx where k = 'host'));
select t.fails($$select public.split_teams((select id from ctx where k = 'team'))$$, 'came_as_team_no_split', 'no auto-split for a team');

-- Host adds an app player by phone; unknown numbers are refused.
insert into ctx values ('friend', t.player('Friend'));
select t.login((select id from ctx where k = 'host'));
select public.host_add_player((select id from ctx where k = 'team'), (select phone from auth.users where id = (select id from ctx where k = 'friend')), 'forward');
select t.eq(public.is_in_match((select id from ctx where k = 'team'), (select id from ctx where k = 'friend')), true, 'host added app player by phone');
select t.fails($$select public.host_add_player((select id from ctx where k = 'team'), '+20 100 000 9999', 'forward')$$, 'player_not_on_app', 'unknown phone refused');

-- Host removes a guest: the spot is freed but the record is kept.
select t.login((select id from ctx where k = 'host'));
select public.host_remove_guest((select id from public.match_players where guest_name = 'Zizo'));
select t.eq((select status::text from public.match_players where guest_name = 'Zizo'), 'left_free', 'removed guest is marked as left, not deleted');
select t.eq(public.joined_count((select id from ctx where k = 'team')), 7, 'removed guest no longer counted (8 -> 7)');
select t.fails($$select public.host_remove_guest((select id from public.match_players where guest_name = 'Zizo'))$$, 'guest_not_found', 'cannot remove the same guest twice');
select t.login((select id from ctx where k = 'friend'));
select t.fails($$select public.host_remove_guest((select id from public.match_players where guest_name = 'Mido'))$$, 'host_only', 'only the host removes guests');
