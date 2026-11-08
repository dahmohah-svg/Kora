# Kora

Kora lets street footballers in Egypt find a 5v5 or 6v6 game, fill a missing spot and pay fairly, with ranks built from attendance and ratings. This repository holds Version 1, built from the revised MVP plan.

| Folder | What it is |
| --- | --- |
| `supabase/` | Database, every rule from the plan (points, ratings, attendance, refunds, team balancing), security, scheduled jobs, and tests |
| `app/` | Flutter app for Android and iPhone. Arabic first (right-to-left), English second |
| `admin/` | Web panel for admins: pitches, booking confirmations, disputes, refunds, bans |
| `docs/` | How each rule is built, and what is left to build |

## What works today

- Sign in with phone number and SMS code, create a profile (18+).
- Browse upcoming matches by area, day and 5v5 or 6v6.
- Create a match at a partner pitch. The price per player is calculated on the server.
- Host confirms the pitch booking. Matches not confirmed 6 hours before kickoff are cancelled automatically.
- Join with a position and payment method. The host can add app players by phone number or guests by name, and mark "we came as a team".
- Teams are split automatically by skill when the match is full, with goalkeepers spread between teams.
- Leave a match, with a warning that says whether it is free or a late cancellation. Refunds follow the plan's table.
- After the match: rate players (anonymous, 24 hours), report late or no-show (2 reports needed), dispute, report the score.
- Matches are finalized 48 hours after kickoff: points, levels, on-time rate, and pauses for repeat no-shows.
- Profile with level, points, games played, on-time rate, and average rating (shown after 3 rated matches).
- Share a match on WhatsApp, get directions in Google Maps.

- Admin web panel: add pitches, confirm bookings, cancel matches, decide disputes, track refunds, ban players.

Not built yet: online payment, push/SMS delivery. See [docs/next-steps.md](docs/next-steps.md).

## Running the tests

Database tests need PostgreSQL 16 or newer installed locally (no Docker, no Supabase account):

```sh
supabase/rule-tests/run.sh
```

App tests need Flutter 3.47 or newer:

```sh
cd app
flutter test
```

Both run on every push through GitHub Actions (`.github/workflows/ci.yml`).

## Supabase

The database runs in the Supabase project **kora** (`wzezqpesoaecnmclrmaj`, Frankfurt). Everything in `supabase/migrations` is applied there, and the scheduled jobs (finalizing matches, cancelling unconfirmed matches, reminders) are running.

Still to do in the Supabase dashboard:

1. Authentication > Sign In / Providers > Phone: turn it on and connect an SMS provider that delivers to Egyptian numbers.
2. Open the admin panel (`admin/README.md`), sign in, and run the one-line SQL it shows to make yourself admin.
3. Add your partner pitches in the panel's Pitches tab.

To apply new migrations later: `supabase link --project-ref wzezqpesoaecnmclrmaj` then `supabase db push`.

You own the Supabase project, this repository and the app store accounts, as the plan requires.
