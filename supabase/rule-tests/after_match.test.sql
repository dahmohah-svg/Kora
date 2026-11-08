-- Ratings, attendance, disputes, finalization and repeat offenders.
create temp table ctx (k text primary key, id uuid);
create temp table roster (n int primary key, id uuid);

select t.at('2026-12-01 18:00+02');
insert into ctx values ('host', t.player('Host')), ('pitch', t.pitch(500)), ('outsider', t.player('Outsider'));
select t.login((select id from ctx where k = 'host'));
insert into ctx select 'match', (public.create_match((select id from ctx where k = 'pitch'),
  '2026-12-05 20:00+02', 60, '5v5', 'equal', false, false, 'forward')).id;
select public.confirm_pitch((select id from ctx where k = 'match'));
insert into roster select ord, id from unnest(t.fill((select id from ctx where k = 'match'), 9)) with ordinality as u(id, ord);
insert into roster values (0, (select id from ctx where k = 'host'));

-- Ratings open at the end of the match (21:00) and close 24h after kickoff.
select t.at('2026-12-05 20:30+02');
select t.login((select id from roster where n = 1));
select t.fails($$select public.rate_player((select id from ctx where k = 'match'), (select id from roster where n = 2), 5)$$, 'rating_not_open_yet', 'no rating during the match');

select t.at('2026-12-05 21:05+02');
select t.fails($$select public.rate_player((select id from ctx where k = 'match'), (select id from roster where n = 1), 5)$$, 'cannot_rate_self', 'cannot rate yourself');
select t.fails($$select public.rate_player((select id from ctx where k = 'match'), (select id from ctx where k = 'outsider'), 5)$$, 'not_in_same_match', 'only players in the match');
select t.login((select id from ctx where k = 'outsider'));
select t.fails($$select public.rate_player((select id from ctx where k = 'match'), (select id from roster where n = 1), 1)$$, 'not_in_same_match', 'outsiders cannot rate');

-- Player 2 gets 5 stars from 1 and 3; player 1 rates twice (counts once).
select t.login((select id from roster where n = 1));
select public.rate_player((select id from ctx where k = 'match'), (select id from roster where n = 2), 3);
select public.rate_player((select id from ctx where k = 'match'), (select id from roster where n = 2), 5);
select t.login((select id from roster where n = 3));
select public.rate_player((select id from ctx where k = 'match'), (select id from roster where n = 2), 5);
select t.eq((select count(*)::int from public.ratings where rated_id = (select id from roster where n = 2)), 2, 'one rating per pair per match');
-- Player 4 gets 1 star.
select public.rate_player((select id from ctx where k = 'match'), (select id from roster where n = 4), 1);

-- Attendance: player 5 reported no-show by 2 players (one is the host);
-- player 6 reported late by only 1 (does not count).
select t.login((select id from ctx where k = 'host'));
select public.report_attendance((select id from ctx where k = 'match'), (select id from roster where n = 5), 'no_show');
select t.eq((select count(*)::int from public.notifications where kind = 'attendance_reported'), 0, 'one report does not notify');
select public.report_attendance((select id from ctx where k = 'match'), (select id from roster where n = 6), 'late');
select t.login((select id from roster where n = 1));
select public.report_attendance((select id from ctx where k = 'match'), (select id from roster where n = 5), 'no_show');
select t.eq((select count(*)::int from public.notifications where kind = 'attendance_reported' and user_id = (select id from roster where n = 5)), 1, 'player told when two reports count');
-- Player 7 reported late by 2 players and disputes it.
select public.report_attendance((select id from ctx where k = 'match'), (select id from roster where n = 7), 'late');
select t.login((select id from roster where n = 2));
select public.report_attendance((select id from ctx where k = 'match'), (select id from roster where n = 7), 'late');
-- The no-show is also rated 5 by someone; those ratings are ignored.
select public.rate_player((select id from ctx where k = 'match'), (select id from roster where n = 5), 5);

select t.eq(public.attendance_for((select id from ctx where k = 'match'), (select id from roster where n = 5)), 'no_show'::public.attendance, 'two no-show reports count');
select t.eq(public.attendance_for((select id from ctx where k = 'match'), (select id from roster where n = 6)), 'on_time'::public.attendance, 'one late report does not count');

select t.login((select id from roster where n = 6));
select t.fails($$select public.dispute_attendance((select id from ctx where k = 'match'), 'I was there')$$, 'nothing_to_dispute', 'cannot dispute without counted reports');
select t.login((select id from roster where n = 7));
select public.dispute_attendance((select id from ctx where k = 'match'), 'Traffic on the Ring Road, I called the host');

select t.at('2026-12-06 20:01+02');
select t.login((select id from roster where n = 1));
select t.fails($$select public.rate_player((select id from ctx where k = 'match'), (select id from roster where n = 3), 4)$$, 'rating_closed', 'ratings close 24h after kickoff');

-- Finalization waits for the dispute window and for open disputes.
select t.at('2026-12-07 19:59+02');
select t.eq(public.finalize_due_matches(), 0, 'not finalized inside dispute window');
select t.at('2026-12-07 20:01+02');
select t.eq(public.finalize_due_matches(), 0, 'not finalized while a dispute is open');

insert into ctx values ('admin', t.player('Admin'));
update public.profiles set is_admin = true where id = (select id from ctx where k = 'admin');
select t.login((select id from ctx where k = 'admin'));
select public.admin_resolve_dispute((select id from public.attendance_disputes limit 1), true);
select t.eq(public.finalize_due_matches(), 1, 'finalized after dispute resolved');

select t.eq((select points from public.profiles where id = (select id from roster where n = 2)), 21, 'on time + 5 stars = 21 points');
select t.eq((select points from public.profiles where id = (select id from roster where n = 4)), 9,  'on time + 1 star = 9 points');
select t.eq((select points from public.profiles where id = (select id from roster where n = 5)), 0,  'no-show floors at 0');
select t.eq((select points_delta from public.match_results where player_id = (select id from roster where n = 5)), -20, 'no-show recorded as -20');
select t.eq((select rating_count from public.match_results where player_id = (select id from roster where n = 5)), 0, 'no-show ratings ignored');
select t.eq((select attendance::text from public.match_results where player_id = (select id from roster where n = 7)), 'on_time', 'upheld dispute clears late reports');
select t.eq((select points from public.profiles where id = (select id from roster where n = 6)), 15, 'unrated on-time player = 15');
select t.eq((select status::text from public.matches where id = (select id from ctx where k = 'match')), 'closed', 'match closed');

-- Profile stats: average hidden until 3 rated matches.
select t.eq((select games_played from public.player_stats where player_id = (select id from roster where n = 2)), 1::bigint, 'games played counted');
select t.eq((select on_time_rate from public.player_stats where player_id = (select id from roster where n = 2)), 1.00, 'on-time rate 100%');
select t.eq((select avg_rating from public.player_stats where player_id = (select id from roster where n = 2)), null::numeric, 'average hidden after 1 rated match');
select t.eq((select on_time_rate from public.player_stats where player_id = (select id from roster where n = 5)), 0.00, 'no-show lowers on-time rate');

-- Repeat offenders: second no-show in 30 days warns, third pauses 7 days.
create or replace function pg_temp.no_show_match(p_kickoff timestamptz, p_target uuid) returns void language plpgsql as $$
declare
  mid uuid;
  ids uuid[];
begin
  perform t.at(p_kickoff - interval '2 days');
  perform t.login((select id from ctx where k = 'host'));
  mid := (public.create_match((select id from ctx where k = 'pitch'), p_kickoff, 60, '5v5', 'equal', false, false, 'forward')).id;
  perform public.confirm_pitch(mid);
  perform t.login(p_target);
  perform public.join_match(mid, 'defender');
  ids := t.fill(mid, 2);
  perform t.at(p_kickoff + interval '2 hours');
  perform t.login(ids[1]); perform public.report_attendance(mid, p_target, 'no_show');
  perform t.login(ids[2]); perform public.report_attendance(mid, p_target, 'no_show');
  perform t.at(p_kickoff + interval '49 hours');
  perform public.finalize_due_matches();
end $$;

select pg_temp.no_show_match('2026-12-12 20:00+02', (select id from roster where n = 5));
select t.eq((select count(*)::int from public.notifications where kind = 'no_show_warning' and user_id = (select id from roster where n = 5)), 1, 'second no-show in 30 days warns');
select pg_temp.no_show_match('2026-12-20 20:00+02', (select id from roster where n = 5));
select t.eq((select paused_until from public.profiles where id = (select id from roster where n = 5)), timestamptz '2026-12-22 21:00+02' + interval '7 days', 'third no-show pauses for 7 days');
select t.login((select id from roster where n = 5));
select t.fails($$select public.create_match((select id from ctx where k = 'pitch'), '2026-12-30 20:00+02', 60, '5v5', 'equal', false, false, 'forward')$$, 'account_paused', 'paused player cannot host');
