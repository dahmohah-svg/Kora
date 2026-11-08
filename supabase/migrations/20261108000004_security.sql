-- Kora: who can read what. Clients never write tables directly; every write
-- goes through the security definer functions in 0003.

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------
alter table public.app_config          enable row level security;
alter table public.profiles            enable row level security;
alter table public.pitches             enable row level security;
alter table public.matches             enable row level security;
alter table public.match_players       enable row level security;
alter table public.ratings             enable row level security;
alter table public.attendance_reports  enable row level security;
alter table public.attendance_disputes enable row level security;
alter table public.score_reports       enable row level security;
alter table public.match_results       enable row level security;
alter table public.notifications       enable row level security;

revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;

-- Settings: readable so the app can show the same numbers as the server.
grant select on public.app_config to authenticated;
create policy app_config_read on public.app_config for select to authenticated using (true);

-- Own profile in full (birth date, pause). Other players are read through
-- the player_stats view, which leaves out private columns.
grant select on public.profiles to authenticated;
create policy profiles_own on public.profiles for select to authenticated
  using (id = auth.uid() or public.is_admin());

-- Pitches: everyone signed in sees active pitches; the contact phone is
-- admin-only (column grant).
grant select (id, name, area, address, lat, lng, price_per_hour_egp, photo_urls, is_active, created_at)
  on public.pitches to authenticated;
create policy pitches_read on public.pitches for select to authenticated
  using (is_active or public.is_admin());

grant select on public.matches to authenticated;
create policy matches_read on public.matches for select to authenticated using (true);

-- Rosters are public to signed-in players; payment columns are not
-- (column grant). A player sees their own payment through my_spots.
grant select (id, match_id, player_id, guest_name, position, team, status, joined_at)
  on public.match_players to authenticated;
create policy match_players_read on public.match_players for select to authenticated using (true);

-- Ratings are anonymous: a player sees only the ratings they gave.
grant select on public.ratings to authenticated;
create policy ratings_own_given on public.ratings for select to authenticated
  using (rater_id = auth.uid());

grant select on public.attendance_reports to authenticated;
create policy reports_own_made on public.attendance_reports for select to authenticated
  using (reporter_id = auth.uid() or public.is_admin());

grant select on public.attendance_disputes to authenticated;
create policy disputes_own on public.attendance_disputes for select to authenticated
  using (player_id = auth.uid() or public.is_admin());

grant select on public.score_reports to authenticated;
create policy score_reports_read on public.score_reports for select to authenticated using (true);

grant select on public.match_results to authenticated;
create policy match_results_own on public.match_results for select to authenticated
  using (player_id = auth.uid() or public.is_admin());

grant select on public.notifications to authenticated;
create policy notifications_own on public.notifications for select to authenticated
  using (user_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Views. These run with the owner's rights on purpose: they expose only
-- aggregates and public columns.
-- ---------------------------------------------------------------------------
revoke all on public.player_stats from anon, public;
grant select on public.player_stats to authenticated;

revoke all on public.collusion_flags from anon, authenticated, public;

-- The calling player's own spots, with payment details.
create or replace view public.my_spots as
select mp.*
from public.match_players mp
where mp.player_id = auth.uid();
revoke all on public.my_spots from anon, public;
grant select on public.my_spots to authenticated;

-- Match list for browsing: one row per match with pitch and fill.
create or replace view public.match_list as
select
  m.id, m.kickoff_at, m.duration_minutes, m.format, m.cost_split, m.price_per_player_egp,
  m.allow_cash, m.came_as_team, m.status, m.pitch_confirmed_at is not null as pitch_confirmed,
  m.host_id, m.team_a_color, m.team_b_color, m.score_a, m.score_b,
  p.id as pitch_id, p.name as pitch_name, p.area, p.lat, p.lng,
  public.match_capacity(m.format) as capacity,
  public.joined_count(m.id) as joined
from public.matches m
join public.pitches p on p.id = m.pitch_id;
revoke all on public.match_list from anon, public;
grant select on public.match_list to authenticated;

-- ---------------------------------------------------------------------------
-- Functions: nothing is callable by default; then the client RPCs are
-- granted one by one.
-- ---------------------------------------------------------------------------
revoke execute on all functions in schema public from public, anon, authenticated;
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;

-- Used inside RLS policies and views, so the caller needs them.
grant execute on function public.is_admin() to authenticated;
grant execute on function public.joined_count(uuid) to authenticated;
grant execute on function public.match_capacity(public.match_format) to authenticated;
grant execute on function public.level_for_points(integer) to authenticated;
grant execute on function public.cfg_num(text) to authenticated;
grant execute on function public.kora_now() to authenticated;

-- Client RPCs.
grant execute on function public.create_profile(text, public.position, public.position[], date, text) to authenticated;
grant execute on function public.update_profile(text, text, public.position, public.position[], text) to authenticated;
grant execute on function public.create_match(uuid, timestamptz, integer, public.match_format, public.cost_split, boolean, boolean, public.position) to authenticated;
grant execute on function public.confirm_pitch(uuid) to authenticated;
grant execute on function public.join_match(uuid, public.position, public.payment_method) to authenticated;
grant execute on function public.host_add_player(uuid, text, public.position) to authenticated;
grant execute on function public.host_add_guest(uuid, text, public.position) to authenticated;
grant execute on function public.host_remove_guest(uuid) to authenticated;
grant execute on function public.leave_match(uuid) to authenticated;
grant execute on function public.leave_warning(uuid) to authenticated;
grant execute on function public.cancel_match(uuid, text) to authenticated;
grant execute on function public.split_teams(uuid) to authenticated;
grant execute on function public.host_mark_cash_paid(uuid) to authenticated;
grant execute on function public.rate_player(uuid, uuid, integer) to authenticated;
grant execute on function public.report_attendance(uuid, uuid, public.report_kind) to authenticated;
grant execute on function public.dispute_attendance(uuid, text) to authenticated;
grant execute on function public.report_score(uuid, integer, integer) to authenticated;
grant execute on function public.mark_notifications_read(bigint[]) to authenticated;
grant execute on function public.can_pay(uuid) to authenticated;

-- Admin RPCs (each checks is_admin itself).
grant execute on function public.admin_upsert_pitch(uuid, text, text, text, double precision, double precision, integer, text[], text, boolean) to authenticated;
grant execute on function public.admin_resolve_dispute(uuid, boolean) to authenticated;
grant execute on function public.admin_set_banned(uuid, boolean) to authenticated;
grant execute on function public.admin_mark_refunded(uuid) to authenticated;
grant execute on function public.admin_collusion_flags() to authenticated;

-- Server-only: payment webhook and scheduled jobs.
grant execute on function public.payment_mark_paid(uuid, integer) to service_role;
grant execute on function public.finalize_due_matches() to service_role;
grant execute on function public.cancel_unconfirmed_matches() to service_role;
grant execute on function public.queue_reminders() to service_role;
