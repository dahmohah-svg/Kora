-- What a signed-in player can and cannot see or do.
create temp table ctx (k text primary key, id uuid);
grant select on ctx to authenticated;

select t.at('2026-12-01 18:00+02');
insert into ctx values ('a', t.player('Ahmed')), ('b', t.player('Bassem')), ('c', t.player('Chady')), ('pitch', t.pitch(500));
update public.pitches set contact_phone = '+201234' where id = (select id from ctx where k = 'pitch');
select t.login((select id from ctx where k = 'a'));
insert into ctx select 'match', (public.create_match((select id from ctx where k = 'pitch'),
  '2026-12-05 20:00+02', 60, '5v5', 'equal', false, false, 'forward')).id;
select public.confirm_pitch((select id from ctx where k = 'match'));
select t.login((select id from ctx where k = 'b')); select public.join_match((select id from ctx where k = 'match'), 'defender');
select t.login((select id from ctx where k = 'c')); select public.join_match((select id from ctx where k = 'match'), 'defender');
select t.at('2026-12-05 21:30+02');
select t.login((select id from ctx where k = 'b')); select public.rate_player((select id from ctx where k = 'match'), (select id from ctx where k = 'a'), 2);
select t.login((select id from ctx where k = 'c')); select public.rate_player((select id from ctx where k = 'match'), (select id from ctx where k = 'a'), 4);

-- From here on, act as a client would.
set role authenticated;
select t.login((select id from ctx where k = 'a'));

select t.eq((select count(*)::int from public.ratings), 0, 'a player cannot see ratings they received');
select t.login((select id from ctx where k = 'b'));
select t.eq((select count(*)::int from public.ratings), 1, 'a player sees only ratings they gave');

select t.eq((select count(*)::int from public.profiles), 1, 'only own profile row readable');
select t.eq((select count(*)::int from public.player_stats), 3, 'other players visible through player_stats');
select t.fails($$select payment_status from public.match_players$$, 'permission denied', 'payment columns of others hidden');
select t.eq((select count(*)::int from public.my_spots), 1, 'own spot with payment visible');
select t.fails($$select contact_phone from public.pitches$$, 'permission denied', 'pitch contact phone hidden');
select t.eq((select count(*)::int from public.match_list), 1, 'match list readable');

select t.fails($$insert into public.ratings values ((select id from ctx where k = 'match'), (select id from ctx where k = 'b'), (select id from ctx where k = 'c'), 5)$$, 'permission denied', 'cannot write ratings directly');
select t.fails($$update public.profiles set points = 9999$$, 'permission denied', 'cannot change own points');
select t.fails($$select public.finalize_match((select id from ctx where k = 'match'))$$, 'permission denied', 'cannot run finalization');
select t.fails($$select public.payment_mark_paid((select id from public.my_spots limit 1), 1000)$$, 'permission denied', 'cannot mark own payment paid');
select t.fails($$select public.balance_teams((select id from ctx where k = 'match'))$$, 'permission denied', 'cannot call internal team split');
select t.fails($$select * from public.collusion_flags$$, 'permission denied', 'collusion flags hidden');
select t.fails($$select * from public.admin_collusion_flags()$$, 'admin_only', 'admin RPC refuses players');

reset role;
