# Kora app (Flutter)

Android and iPhone from one codebase. Arabic is the default language with right-to-left layout; players can switch to English from their profile.

## Run

The app is connected to the `kora` Supabase project (Frankfurt) through `config/kora.json`:

```sh
flutter run --dart-define-from-file=config/kora.json
```

The publishable key in that file is meant to ship inside the app; it can only do what the database security rules allow. Never put the `service_role` key in the app or this repository.

Optional: add `"SHARE_BASE_URL": "https://your-domain/m/"` to the file for the link in WhatsApp shares.

## Test

```sh
flutter test      # logic and screen tests, using an in-memory fake backend
flutter analyze
```

## Layout

| Path | What it is |
| --- | --- |
| `lib/data/kora_api.dart` | Everything the app asks the backend, as one interface |
| `lib/data/supabase_kora_api.dart` | The real implementation. All changes go through server functions (RPCs) |
| `lib/data/models.dart` | Matches, players, spots, stats |
| `lib/l10n/app_ar.arb`, `app_en.arb` | All text. Add a language by adding a file |
| `lib/ui/` | Screens: sign-in, profile creation, match list, match details, create match, profile |
| `test/fake_api.dart` | The fake backend used by the screen tests |

The app never decides a rule on its own. Points, refunds, team splits and who may rate whom are all decided by the server; the app only shows what the server returns, and server refusals (like `match_full`) are shown as messages in the player's language (`lib/ui/labels.dart`).
