-- Creating, confirming and joining matches.
create temp table ctx (k text primary key, id uuid);

select t.at('2026-12-01 18:00+02');
insert into ctx values ('host', t.player('Host')), ('pitch', t.pitch(600));
select t.login((select id from ctx where k = 'host'));

insert into ctx select 'match', (public.create_match(
  (select id from ctx where k = 'pitch'), '2026-12-05 20:00+02', 60, '5v5', 'equal', false, false, 'forward')).id;

select t.eq((select total_cost_egp from public.matches where id = (select id from ctx where k = 'match')), 600, 'total cost = pitch price for 60 minutes');
select t.eq((select price_per_player_egp from public.matches where id = (select id from ctx where k = 'match')), 65, 'per player = 600/10 + 5 EGP fee');
select t.eq((select status::text from public.matches where id = (select id from ctx where k = 'match')), 'pending_pitch', 'new match waits for pitch confirmation');
select t.eq(public.joined_count((select id from ctx where k = 'match')), 1, 'host takes the first spot');

-- A player can join before the pitch is confirmed, but cannot pay yet.
insert into ctx values ('p1', t.player('P1'));
select t.login((select id from ctx where k = 'p1'));
select public.join_match((select id from ctx where k = 'match'), 'defender', 'online');
select t.eq(public.can_pay((select id from public.match_players where player_id = (select id from ctx where k = 'p1'))), false, 'no payment before pitch confirmed');
select t.fails($$select public.join_match((select id from ctx where k = 'match'), 'defender', 'online')$$, 'already_joined', 'cannot join twice');
select t.fails($$select public.join_match((select id from ctx where k = 'match'), 'defender', 'cash')$$, 'cash_not_allowed', 'cash only when host allows it');
select t.fails($$select public.confirm_pitch((select id from ctx where k = 'match'))$$, 'host_or_admin_only', 'only host or admin confirms the pitch');

select t.login((select id from ctx where k = 'host'));
select public.confirm_pitch((select id from ctx where k = 'match'));
select t.eq((select status::text from public.matches where id = (select id from ctx where k = 'match')), 'open', 'confirmed match is open');
select t.login((select id from ctx where k = 'p1'));
select t.eq(public.can_pay((select id from public.match_players where player_id = (select id from ctx where k = 'p1'))), true, 'payment allowed after confirmation');

-- Payment webhook.
select public.payment_mark_paid((select id from public.match_players where player_id = (select id from ctx where k = 'p1')), 65);
select t.eq((select payment_status::text from public.match_players where player_id = (select id from ctx where k = 'p1')), 'paid', 'webhook marks the spot paid');

-- Teams are not shown until the roster is full, then split automatically.
select t.eq((select count(*)::int from public.match_players where match_id = (select id from ctx where k = 'match') and team is not null), 0, 'no teams before full');
select t.fill((select id from ctx where k = 'match'), 8);
select t.eq(public.joined_count((select id from ctx where k = 'match')), 10, 'match full at 10 for 5v5');
select t.eq((select count(*)::int from public.match_players where match_id = (select id from ctx where k = 'match') and team = 'A'), 5, 'team A has 5');
select t.eq((select count(*)::int from public.match_players where match_id = (select id from ctx where k = 'match') and team = 'B'), 5, 'team B has 5');
select t.eq((select count(*)::int from public.notifications where kind = 'teams_ready'), 10, 'everyone told teams are ready');

insert into ctx values ('late', t.player('Late'));
select t.login((select id from ctx where k = 'late'));
select t.fails($$select public.join_match((select id from ctx where k = 'match'), 'forward', 'online')$$, 'match_full', 'cannot join a full match');

-- Paused players cannot join.
update public.profiles set paused_until = '2026-12-04 00:00+02' where id = (select id from ctx where k = 'late');
select t.login((select id from ctx where k = 'host'));
insert into ctx select 'match2', (public.create_match(
  (select id from ctx where k = 'pitch'), '2026-12-06 20:00+02', 90, '6v6', 'host_pays', true, false, 'goalkeeper')).id;
select t.eq((select total_cost_egp from public.matches where id = (select id from ctx where k = 'match2')), 900, '90 minutes costs 1.5 hours');
select t.eq((select amount_egp from public.match_players where match_id = (select id from ctx where k = 'match2') and player_id = (select id from ctx where k = 'host')), 900, 'host pays everything when host_pays');
select t.login((select id from ctx where k = 'late'));
select t.fails($$select public.join_match((select id from ctx where k = 'match2'), 'forward', 'cash')$$, 'account_paused', 'paused player cannot join');
select t.at('2026-12-04 01:00+02');
select public.join_match((select id from ctx where k = 'match2'), 'forward', 'cash');
select t.eq((select payment_status::text from public.match_players where match_id = (select id from ctx where k = 'match2') and player_id = (select id from ctx where k = 'late')), 'not_required', 'players pay nothing when host pays');

-- Kickoff in the past is refused; age limit at sign-up.
select t.login((select id from ctx where k = 'host'));
select t.fails($$select public.create_match((select id from ctx where k = 'pitch'), '2026-12-01 00:00+02', 60, '5v5', 'equal', false, false, 'forward')$$, 'kickoff_in_past', 'kickoff must be in the future');
insert into auth.users (id, phone) values ('00000000-0000-0000-0000-0000000000aa', '+201000000001');
select t.login('00000000-0000-0000-0000-0000000000aa');
select t.fails($$select public.create_profile('Kid', 'forward', '{}', '2010-01-01')$$, 'too_young', 'under 18 cannot sign up');
select t.eq((public.create_profile('Adult', 'forward', '{forward,defender}', '2000-01-01')).other_positions, '{defender}'::public.position[], 'favorite removed from other positions');
