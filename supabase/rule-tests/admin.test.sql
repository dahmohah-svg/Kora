-- Admin read functions: only admins, and they show what the panel needs.
create temp table ctx (k text primary key, id uuid);

select t.at('2026-12-01 18:00+02');
insert into ctx values ('admin', t.player('Admin')), ('host', t.player('Host')), ('pitch', t.pitch(600));
update public.profiles set is_admin = true where id = (select id from ctx where k = 'admin');
update public.pitches set contact_phone = '+201111111111' where id = (select id from ctx where k = 'pitch');

select t.login((select id from ctx where k = 'host'));
insert into ctx select 'match', (public.create_match((select id from ctx where k = 'pitch'),
  '2026-12-05 20:00+02', 60, '5v5', 'equal', false, false, 'forward')).id;

-- Players are refused.
select t.fails($$select * from public.admin_pitches()$$, 'admin_only', 'players cannot list pitches as admin');
select t.fails($$select * from public.admin_matches()$$, 'admin_only', 'players cannot list matches as admin');
select t.fails($$select * from public.admin_disputes()$$, 'admin_only', 'players cannot list disputes');
select t.fails($$select * from public.admin_refunds_due()$$, 'admin_only', 'players cannot list refunds');
select t.fails($$select * from public.admin_players()$$, 'admin_only', 'players cannot list players');
select t.fails($$select * from public.admin_collusion_report()$$, 'admin_only', 'players cannot see collusion report');

select t.login((select id from ctx where k = 'admin'));
select t.eq((select contact_phone from public.admin_pitches() limit 1), '+201111111111', 'admin sees pitch contact phone');
select t.eq((select host_name from public.admin_matches()), 'Host', 'admin sees match with host name');
select t.eq((select pitch_confirmed from public.admin_matches()), false, 'admin sees the pitch is not confirmed');

-- Admin confirms the pitch, a player pays then the admin cancels: refund is listed.
select public.confirm_pitch((select id from ctx where k = 'match'));
insert into ctx values ('payer', t.player('Payer'));
select t.login((select id from ctx where k = 'payer'));
select public.join_match((select id from ctx where k = 'match'), 'defender');
select public.payment_mark_paid((select id from public.match_players where player_id = (select id from ctx where k = 'payer')), 65);
select t.login((select id from ctx where k = 'admin'));
select public.cancel_match((select id from ctx where k = 'match'), 'pitch_flooded');
select t.eq((select player_name || ' ' || amount_egp from public.admin_refunds_due()), 'Payer 65', 'refund due listed with name and amount');
select public.admin_mark_refunded((select spot_id from public.admin_refunds_due()));
select t.eq((select count(*)::int from public.admin_refunds_due()), 0, 'refund cleared after marking paid');

-- Player search by name and by phone digits.
select t.eq((select count(*)::int from public.admin_players('pay')), 1, 'search by name');
select t.eq((select display_name from public.admin_players((select right(phone, 6) from auth.users where id = (select id from ctx where k = 'host'))) limit 1), 'Host', 'search by phone digits');
select t.eq((select count(*)::int from public.admin_players()), 3, 'empty search lists everyone');

-- Ban shows up in the list.
select public.admin_set_banned((select id from ctx where k = 'payer'), true);
select t.eq((select is_banned from public.admin_players('Payer')), true, 'ban visible to admin');
