# How the rules are built

Every rule from the MVP plan runs on the server, in `supabase/migrations`. The numbers live in the `app_config` table, so they can be adjusted after the first month without changing code.

| Rule in the plan | Where it is | Test |
| --- | --- | --- |
| Rank points (+10 played, +5 on time, -3 late, -20 no-show, 3 x (stars - 3)), never below 0 | `match_points`, `rating_points`, `finalize_match` | `points`, `after_match` |
| Levels (Rookie 0, Regular 50, Starter 150, Captain 300, Legend 600) | `level_for_points` | `points` |
| Team balancing by skill, goalkeepers spread, came as a team | `balance_teams`, `team_for_new_spot` | `teams` |
| Skill = average of last 10 rated matches, 3.0 under 3 rated matches | `skill_score` | `teams` |
| Ratings: same match only, 24-hour window, once per pair, anonymous, shown after 3 matches | `rate_player`, RLS on `ratings`, `player_stats` | `after_match`, `security` |
| Collusion flag (mutual 5 stars in 3+ matches in a row) | `collusion_flags` view, `admin_collusion_flags` | - |
| Attendance: on time unless 2 different players report, host included | `report_attendance`, `attendance_for` | `after_match` |
| Disputes, decided by admin, points wait | `dispute_attendance`, `admin_resolve_dispute`, `finalize_match` | `after_match` |
| Cancellations: free more than 3 hours before, late lowers on-time rate | `leave_match`, `leave_warning`, `player_stats` | `leave_refund` |
| Repeat offenders: warning at 2, 7-day pause at 3 no-shows in 30 days | `finalize_match` | `after_match` |
| Pitch confirmed before payment, auto-cancel 6 hours before kickoff | `confirm_pitch`, `can_pay`, `cancel_unconfirmed_matches` | `match_flow`, `leave_refund` |
| Refund table | `leave_match`, `release_one_late_leaver`, `cancel_match_internal`, `finalize_match` | `leave_refund` |
| Minimum age 18 | `create_profile` | `match_flow` |
| Score confirmed by both teams (kept for Version 2) | `report_score` | - |

## Choices made where the plan was silent

These are decisions taken while building. Each is easy to change; say if one is wrong.

- **When points are given.** Ratings and reports close 24 hours after kickoff, then players have 24 more hours to dispute. Points are given at 48 hours, or later if a dispute is still open.
- **A no-show's ratings don't count**, even if someone rated them.
- **Rating the same player twice** in one match replaces the first rating, so it still counts once.
- **Teams are shown only when the match is full**, or when the host presses "Split teams now" to play short. If someone leaves after that, the split is cleared and redone when the match fills again.
- **Guests** (added by name) count as skill 3.0, are never rated, and pay the host directly. When the host removes a guest, the spot is marked as left, not deleted, so there is a record.
- **Late leavers and refunds.** When a new player takes a spot, the player who left late first gets the refund.
- **The host cannot leave** their own match; they cancel it instead, which refunds everyone.
- **Repeat offenders.** The 30 days are counted back from each no-show's kickoff. A pause that is already running is extended by 7 days.
- **Host pays.** When the host pays for the pitch, other players pay nothing and the host's spot carries the full cost.
- **Service fee** (5 EGP) is added into each player's price when the cost is split equally.

## Open decisions

- **Unpaid online spots.** A player who joins and never pays keeps their spot. Decide a payment deadline (for example 2 hours after the pitch is confirmed, or 6 hours before kickoff) before launch.
- **Refund method.** Back to the original payment method or as Kora credit (from the plan).
- **Minimum age.** Set to 18 until the lawyer confirms.
