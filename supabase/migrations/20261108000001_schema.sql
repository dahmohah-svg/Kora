-- Kora: core schema.
-- All rules from the MVP plan are enforced on the server (see 0002 and later).
-- Clients read through RLS-protected tables and views, and change data only
-- through the RPC functions; they never write tables directly.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Settings that the plan says to tune after the first month.
-- ---------------------------------------------------------------------------
create table public.app_config (
  key   text primary key,
  value jsonb not null
);

insert into public.app_config (key, value) values
  ('points_played',            '10'),
  ('points_on_time',           '5'),
  ('points_late',              '-3'),
  ('points_no_show',           '-20'),
  ('rating_points_multiplier', '3'),     -- points = multiplier * (avg stars - 3)
  ('free_leave_hours',         '3'),     -- leave earlier than this = free
  ('rating_window_hours',      '24'),    -- after kickoff
  ('dispute_window_hours',     '24'),    -- after the rating/report window closes
  ('reports_needed',           '2'),     -- reports from different players
  ('min_rated_matches_shown',  '3'),     -- before an average is shown
  ('skill_recent_matches',     '10'),
  ('skill_default',            '3.0'),
  ('no_show_window_days',      '30'),
  ('no_show_warning_at',       '2'),
  ('no_show_pause_at',         '3'),
  ('pause_days',               '7'),
  ('pitch_confirm_deadline_hours', '6'), -- before kickoff, else auto-cancel
  ('service_fee_egp',          '5'),
  ('min_age_years',            '18'),
  ('collusion_streak',         '3');

create or replace function public.cfg_num(p_key text)
returns numeric
language sql stable
set search_path = public
as $$ select (value #>> '{}')::numeric from public.app_config where key = p_key $$;

-- Clock used by every rule. Tests can set `kora.now` to move time; in
-- production the setting is never set, so it is plain now().
create or replace function public.kora_now()
returns timestamptz
language sql stable
as $$
  select coalesce(nullif(current_setting('kora.now', true), '')::timestamptz, now())
$$;

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.position as enum ('goalkeeper', 'defender', 'midfielder', 'forward');
create type public.match_format as enum ('5v5', '6v6');
create type public.cost_split as enum ('equal', 'host_pays');
create type public.match_status as enum ('pending_pitch', 'open', 'cancelled', 'closed');
create type public.player_status as enum ('joined', 'left_free', 'left_late');
create type public.payment_method as enum ('online', 'cash', 'none');
create type public.payment_status as enum ('not_required', 'unpaid', 'paid', 'refund_due', 'refunded', 'forfeited');
create type public.team_side as enum ('A', 'B');
create type public.report_kind as enum ('late', 'no_show');
create type public.attendance as enum ('on_time', 'late', 'no_show');
create type public.dispute_status as enum ('open', 'upheld', 'rejected');

-- ---------------------------------------------------------------------------
-- People and places
-- ---------------------------------------------------------------------------
create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  display_name      text not null check (char_length(display_name) between 2 and 40),
  photo_url         text,
  favorite_position public.position not null,
  other_positions   public.position[] not null default '{}',
  birth_date        date not null,
  language          text not null default 'ar' check (language in ('ar', 'en')),
  points            integer not null default 0 check (points >= 0),
  paused_until      timestamptz,
  is_admin          boolean not null default false,
  is_banned         boolean not null default false,
  created_at        timestamptz not null default now()
);

create table public.pitches (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  area           text not null,
  address        text not null,
  lat            double precision not null,
  lng            double precision not null,
  price_per_hour_egp integer not null check (price_per_hour_egp >= 0),
  photo_urls     text[] not null default '{}',
  contact_phone  text,                       -- admin-only, see RLS
  is_active      boolean not null default true,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Matches
-- ---------------------------------------------------------------------------
create table public.matches (
  id                 uuid primary key default gen_random_uuid(),
  pitch_id           uuid not null references public.pitches (id),
  host_id            uuid not null references public.profiles (id),
  kickoff_at         timestamptz not null,
  duration_minutes   integer not null default 60 check (duration_minutes between 30 and 180),
  format             public.match_format not null,
  cost_split         public.cost_split not null default 'equal',
  total_cost_egp     integer not null check (total_cost_egp >= 0),
  price_per_player_egp integer not null check (price_per_player_egp >= 0),
  allow_cash         boolean not null default false,
  came_as_team       boolean not null default false,
  status             public.match_status not null default 'pending_pitch',
  pitch_confirmed_at timestamptz,
  pitch_confirmed_by uuid references public.profiles (id),
  cancelled_reason   text,
  team_a_color       text not null default 'white',
  team_b_color       text not null default 'black',
  teams_split_at     timestamptz,
  score_a            integer,
  score_b            integer,
  finalized_at       timestamptz,
  reminder_sent_at   timestamptz,
  created_at         timestamptz not null default now()
);

create index matches_kickoff_idx on public.matches (kickoff_at);
create index matches_status_idx on public.matches (status);

create or replace function public.match_capacity(p_format public.match_format)
returns integer language sql immutable
as $$ select case p_format when '5v5' then 10 else 12 end $$;

-- A spot in a match: an app player, or a guest added by name only.
create table public.match_players (
  id             uuid primary key default gen_random_uuid(),
  match_id       uuid not null references public.matches (id) on delete cascade,
  player_id      uuid references public.profiles (id),
  guest_name     text,
  added_by       uuid references public.profiles (id),
  position       public.position not null,
  team           public.team_side,
  status         public.player_status not null default 'joined',
  payment_method public.payment_method not null default 'online',
  payment_status public.payment_status not null default 'unpaid',
  amount_egp     integer not null default 0,
  joined_at      timestamptz not null default now(),
  left_at        timestamptz,
  replaced       boolean not null default false,  -- a late leaver whose spot was refilled
  check ((player_id is null) <> (guest_name is null))
);

create unique index match_players_unique_player
  on public.match_players (match_id, player_id) where player_id is not null;
create index match_players_player_idx on public.match_players (player_id);

-- ---------------------------------------------------------------------------
-- After the match
-- ---------------------------------------------------------------------------
create table public.ratings (
  match_id   uuid not null references public.matches (id) on delete cascade,
  rater_id   uuid not null references public.profiles (id),
  rated_id   uuid not null references public.profiles (id),
  stars      smallint not null check (stars between 1 and 5),
  created_at timestamptz not null default now(),
  primary key (match_id, rater_id, rated_id),
  check (rater_id <> rated_id)
);
create index ratings_rated_idx on public.ratings (rated_id);

create table public.attendance_reports (
  match_id    uuid not null references public.matches (id) on delete cascade,
  reporter_id uuid not null references public.profiles (id),
  reported_id uuid not null references public.profiles (id),
  kind        public.report_kind not null,
  created_at  timestamptz not null default now(),
  primary key (match_id, reporter_id, reported_id),
  check (reporter_id <> reported_id)
);

create table public.attendance_disputes (
  id          uuid primary key default gen_random_uuid(),
  match_id    uuid not null references public.matches (id) on delete cascade,
  player_id   uuid not null references public.profiles (id),
  reason      text not null,
  status      public.dispute_status not null default 'open',
  resolved_by uuid references public.profiles (id),
  resolved_at timestamptz,
  created_at  timestamptz not null default now(),
  unique (match_id, player_id)
);

create table public.score_reports (
  match_id    uuid not null references public.matches (id) on delete cascade,
  reporter_id uuid not null references public.profiles (id),
  team        public.team_side not null,
  score_a     integer not null check (score_a >= 0),
  score_b     integer not null check (score_b >= 0),
  created_at  timestamptz not null default now(),
  primary key (match_id, reporter_id)
);

-- One row per player per finalized match: the audit trail behind points.
create table public.match_results (
  match_id       uuid not null references public.matches (id) on delete cascade,
  player_id      uuid not null references public.profiles (id),
  attendance     public.attendance not null,
  rating_count   integer not null default 0,
  avg_stars      numeric(3,2),
  points_delta   integer not null,
  kickoff_at     timestamptz not null,
  primary key (match_id, player_id)
);
create index match_results_player_idx on public.match_results (player_id, kickoff_at desc);

-- Late cancellations count against the on-time rate (see player_stats).
-- They are read from match_players (status = 'left_late') of closed matches.

-- ---------------------------------------------------------------------------
-- Notifications: written by the rules, delivered by an edge function
-- (push first, SMS fallback).
-- ---------------------------------------------------------------------------
create table public.notifications (
  id         bigint generated always as identity primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  kind       text not null,
  payload    jsonb not null default '{}',
  created_at timestamptz not null default now(),
  sent_at    timestamptz,
  read_at    timestamptz
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_unsent_idx on public.notifications (created_at) where sent_at is null;

create or replace function public.notify(p_user uuid, p_kind text, p_payload jsonb default '{}')
returns void language sql
set search_path = public
as $$ insert into public.notifications (user_id, kind, payload) values (p_user, p_kind, p_payload) $$;
