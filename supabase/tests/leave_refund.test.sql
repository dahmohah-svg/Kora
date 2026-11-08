-- Leaving, refunds and cancellations (Payments and refunds table).
create temp table ctx (k text primary key, id uuid);

select t.at('2026-12-01 18:00+02');
insert into ctx values ('host', t.player('Host')), ('pitch', t.pitch(500));
select t.login((select id from ctx where k = 'host'));
insert into ctx select 'match', (public.create_match((select id from ctx where k = 'pitch'),
  '2026-12-05 20:00+02', 60, '5v5', 'equal', false, false, 'forward')).id;
select public.confirm_pitch((select id from ctx where k = 'match'));

insert into ctx values ('early', t.player('Early')), ('lateleaver', t.player('LateLeaver')), ('unpaid', t.player('Unpaid'));
select t.login((select id from ctx where k = 'early'));      select public.join_match((select id from ctx where k = 'match'), 'defender');
select t.login((select id from ctx where k = 'lateleaver')); select public.join_match((select id from ctx where k = 'match'), 'defender');
select t.login((select id from ctx where k = 'unpaid'));     select public.join_match((select id from ctx where k = 'match'), 'defender');
select public.payment_mark_paid(id, amount_egp) from public.match_players
 where player_id in ((select id from ctx where k = 'early'), (select id from ctx where k = 'lateleaver'));

-- Host cannot leave.
select t.login((select id from ctx where k = 'host'));
select t.fails($$select public.leave_match((select id from ctx where k = 'match'))$$, 'host_must_cancel', 'host cancels instead of leaving');

-- More than 3 hours before kickoff: free, full refund.
select t.login((select id from ctx where k = 'early'));
select t.eq((public.leave_warning((select id from ctx where k = 'match')) ->> 'free')::boolean, true, 'warning says leaving is free');
select public.leave_match((select id from ctx where k = 'match'));
select t.eq((select status::text || '/' || payment_status from public.match_players where player_id = (select id from ctx where k = 'early')), 'left_free/refund_due', 'free leave = full refund');

-- Within 3 hours: late, no refund unless someone takes the spot.
select t.at('2026-12-05 18:00+02');
select t.login((select id from ctx where k = 'lateleaver'));
select t.eq(public.leave_warning((select id from ctx where k = 'match')) ->> 'refund', 'only_if_replaced', 'warning says refund only if replaced');
select public.leave_match((select id from ctx where k = 'match'));
select t.eq((select status::text || '/' || payment_status from public.match_players where player_id = (select id from ctx where k = 'lateleaver')), 'left_late/paid', 'late leave keeps the payment');

select t.at('2026-12-05 18:05+02');
select t.login((select id from ctx where k = 'unpaid'));
select public.leave_match((select id from ctx where k = 'match'));

-- A new player takes a spot: the earliest late leaver is refunded.
insert into ctx values ('newcomer', t.player('Newcomer'));
select t.login((select id from ctx where k = 'newcomer'));
select public.join_match((select id from ctx where k = 'match'), 'forward');
select t.eq((select payment_status::text from public.match_players where player_id = (select id from ctx where k = 'lateleaver')), 'refund_due', 'replaced late leaver is refunded');
select t.eq((select replaced from public.match_players where player_id = (select id from ctx where k = 'unpaid')), false, 'second late leaver still waits');

-- Admin marks refunds done.
insert into ctx values ('admin', t.player('Admin'));
update public.profiles set is_admin = true where id = (select id from ctx where k = 'admin');
select t.login((select id from ctx where k = 'early'));
select t.fails($$select public.admin_mark_refunded((select id from public.match_players where player_id = (select id from ctx where k = 'early')))$$, 'admin_only', 'only admin marks refunds');
select t.login((select id from ctx where k = 'admin'));
select public.admin_mark_refunded((select id from public.match_players where player_id = (select id from ctx where k = 'early')));
select t.eq((select payment_status::text from public.match_players where player_id = (select id from ctx where k = 'early')), 'refunded', 'refund recorded');

-- Host cancels: everyone paid is refunded.
select t.login((select id from ctx where k = 'newcomer'));
select public.payment_mark_paid((select id from public.match_players where player_id = (select id from ctx where k = 'newcomer')), 55);
select t.login((select id from ctx where k = 'host'));
select public.cancel_match((select id from ctx where k = 'match'), 'rain');
select t.eq((select payment_status::text from public.match_players where player_id = (select id from ctx where k = 'newcomer')), 'refund_due', 'host cancel = full refund');
select t.eq((select count(*)::int from public.notifications where kind = 'match_cancelled'), 2, 'joined players told about the cancellation');

-- Pitch not confirmed 6 hours before kickoff: auto-cancelled.
select t.at('2026-12-01 18:00+02');
select t.login((select id from ctx where k = 'host'));
insert into ctx select 'unconfirmed', (public.create_match((select id from ctx where k = 'pitch'),
  '2026-12-02 20:00+02', 60, '5v5', 'equal', false, false, 'forward')).id;
select t.at('2026-12-02 13:59+02');
select t.eq(public.cancel_unconfirmed_matches(), 0, 'not cancelled before the 6-hour deadline');
select t.at('2026-12-02 14:00+02');
select t.eq(public.cancel_unconfirmed_matches(), 1, 'cancelled at the 6-hour deadline');
select t.eq((select cancelled_reason from public.matches where id = (select id from ctx where k = 'unconfirmed')), 'pitch_not_confirmed', 'reason recorded');

-- Late leaver never replaced: payment forfeited at finalization.
select t.at('2026-12-10 10:00+02');
select t.login((select id from ctx where k = 'host'));
insert into ctx select 'm3', (public.create_match((select id from ctx where k = 'pitch'),
  '2026-12-12 20:00+02', 60, '5v5', 'equal', false, false, 'forward')).id;
select public.confirm_pitch((select id from ctx where k = 'm3'));
select t.login((select id from ctx where k = 'early'));
select public.join_match((select id from ctx where k = 'm3'), 'defender');
select public.payment_mark_paid((select id from public.match_players where match_id = (select id from ctx where k = 'm3') and player_id = (select id from ctx where k = 'early')), 55);
select t.at('2026-12-12 19:00+02');
select public.leave_match((select id from ctx where k = 'm3'));
select t.at('2026-12-15 00:00+02');
select public.finalize_due_matches();
select t.eq((select payment_status::text from public.match_players where match_id = (select id from ctx where k = 'm3') and player_id = (select id from ctx where k = 'early')), 'forfeited', 'unreplaced late leaver forfeits');
select t.eq((select on_time_rate from public.player_stats where player_id = (select id from ctx where k = 'early')), 0.00, 'late cancellation lowers on-time rate');
