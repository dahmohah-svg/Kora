-- Kora: fixes from the Supabase security and performance advisors.

-- The match list can run with the caller's own permissions: every column it
-- reads is granted to signed-in players.
alter view public.match_list set (security_invoker = true);

-- player_stats and my_spots keep the owner's rights on purpose:
--   player_stats shows only public columns and totals of other players,
--   my_spots shows only the caller's own rows (filtered by auth.uid()).

-- Fixed search path for the small helper functions.
alter function public.initial_payment(public.matches, uuid, public.payment_method) set search_path = public;
alter function public.spot_amount(public.matches, uuid) set search_path = public;
alter function public.match_capacity(public.match_format) set search_path = public;
alter function public.level_for_points(integer) set search_path = public;
alter function public.kora_now() set search_path = public;

-- Evaluate auth.uid() once per query, not once per row.
alter policy profiles_own on public.profiles
  using (id = (select auth.uid()) or (select public.is_admin()));
alter policy ratings_own_given on public.ratings
  using (rater_id = (select auth.uid()));
alter policy reports_own_made on public.attendance_reports
  using (reporter_id = (select auth.uid()) or (select public.is_admin()));
alter policy disputes_own on public.attendance_disputes
  using (player_id = (select auth.uid()) or (select public.is_admin()));
alter policy match_results_own on public.match_results
  using (player_id = (select auth.uid()) or (select public.is_admin()));
alter policy notifications_own on public.notifications
  using (user_id = (select auth.uid()));
alter policy pitches_read on public.pitches
  using (is_active or (select public.is_admin()));

-- Indexes for lookups the rules make often.
create index if not exists matches_host_idx on public.matches (host_id);
create index if not exists matches_pitch_idx on public.matches (pitch_id);
create index if not exists attendance_reports_reported_idx on public.attendance_reports (reported_id, match_id);
create index if not exists attendance_disputes_player_idx on public.attendance_disputes (player_id);
create index if not exists ratings_rater_idx on public.ratings (rater_id);
