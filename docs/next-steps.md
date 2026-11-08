# What is left for Version 1

The database, all the rules and the main player screens are done. These pieces are still needed before launch, roughly in this order.

1. **SMS sign-in.** The Supabase project is set up and all migrations are applied. Still needed: turn on the Phone provider and connect an SMS provider that delivers to Egyptian numbers (needs a provider account).
2. **Online payment (Paymob or Fawry).** An edge function that starts a payment only when `can_pay` is true, and a webhook that calls `payment_mark_paid`. Refunds marked `refund_due` are paid out through the provider, then marked `refunded`. Needs the company registration and a merchant account.
3. **Push and SMS reminders.** The server already writes every message to the `notifications` table (reminders, teams ready, reports, pauses, refunds). An edge function sends unsent rows by Firebase Cloud Messaging, with SMS as fallback, and the app registers for push.
4. ~~Admin web panel~~ Done: see `admin/README.md`. It still needs a home online (Netlify, Cloudflare Pages or GitHub Pages).
5. **Share links.** Make `https://<domain>/m/<match id>` open the match in the app (Android App Links, iOS Universal Links) or the store if it isn't installed.
6. **Pitch photos and map.** Upload photos to Supabase Storage and show pitches on a Google Map (needs a Maps API key).
7. **App store release.** App icon, Google Play and Apple developer accounts in your company's name (Apple needs a D-U-N-S number).
