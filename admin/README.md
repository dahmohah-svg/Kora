# Kora admin panel

A web page for running Kora day to day:

| Tab | What you do there |
| --- | --- |
| Matches | See every match from 3 days ago onwards. Confirm pitch bookings (players can only pay after this). Cancel a match, which refunds everyone who paid. |
| Pitches | Add and edit partner pitches. Paste a Google Maps link or "lat, lng" for the location. The contact phone is only visible to admins. |
| Disputes | A player says a late or no-show report is wrong. Clear the reports or let them stand. Points for that match wait until you decide. |
| Refunds | Everyone owed money, with the total. Mark each one once you've paid it back. |
| Players | Search by name or phone, ban and lift bans, and see pairs who may be giving each other fake 5-star ratings. |

## Open it

It is plain HTML, CSS and JavaScript with no build step, connected to the `kora` Supabase project in `config.js`.

- **On your computer:** open `admin/index.html` in Chrome, Edge or Safari.
- **Online (recommended):** upload the `admin` folder to any static host, for example Netlify Drop (drag and drop the folder), Cloudflare Pages or GitHub Pages. It only works for admins, so the address can be public.

## Sign in

Sign in with the same phone number you use in the Kora app. The first time, the panel shows a one-line SQL command to make your account an admin; run it in the Supabase SQL editor and reload.

Phone sign-in must be turned on in Supabase first (Authentication > Sign In / Providers > Phone).

## Safety

- Every admin action is checked on the server: a signed-in player who isn't an admin gets "Only admins can do that."
- Player names and messages are always shown as text, so nothing a player types can run in the panel.
- The publishable key in `config.js` is meant to be public. Never put the `service_role` key here.

## Test

```sh
node admin/test/panel.test.mjs   # needs Playwright with Chromium
```
