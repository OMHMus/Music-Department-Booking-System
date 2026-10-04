# Music-Department-Booking-System

## Foyer display board (`display.html`)

A live, full-screen board for the TV in the Music Department foyer: today's Break and Lunch for every room, who is booked (first name + surname initial, or band name), closures, free Music Tech seats, and a QR code to the booking site. It switches to the next school day once lunch has finished.

* **Data:** calls the `display_board()` function in Supabase (`supabase/migrations/20261004_foyer_display.sql`) every 30 seconds. RLS on `bookings` is unchanged; the screen proves itself with a secret key that lives only in the TV's URL, never in this repo.
* **Open on the TV:** `display.html?key=<screen key>`. Options: `&refresh=30` (seconds), `&book=<booking site URL>`, `&night=0` (turn off evening dimming). Preview with sample data: `display.html?demo=1`.
* **Add / revoke a screen:** see the notes at the top of the migration. Check a screen is alive: `select name, last_seen from display_screens;`
* **Looks after itself:** keeps showing the last data (with an "Offline" warning) if the network drops, backs off and retries, reloads itself at 03:00 daily and after 30 minutes without data, keeps the screen awake, dims outside 07:30–17:30, and nudges the layout a few pixels every 5 minutes to avoid burn-in.
* **Session times** are in `SESS` in `display.html` and must match `SN` in `index.html`.

## Band invitation emails (`supabase/functions/band-invite-email`)

When a band leader invites someone, the booking site asks this Supabase Edge Function to email them: "*[pupil] is inviting you to join the band [band]*", with either "log in and open My bands" (they have an account) or "create an account with this school email" (they don't). The database function `band_invite_email()` checks the caller leads the band and the invite is still open, and limits re-sending to once every 10 minutes (`supabase/migrations/20261004_band_invite_list_and_email.sql`).

* **Email service:** [Brevo](https://www.brevo.com) (free plan, 300 emails a day). Set these secrets in Supabase → Edge Functions → Secrets: `BREVO_API_KEY` and `BREVO_SENDER_EMAIL` (a sender address verified in Brevo). Optional: `SITE_URL`.
* **Until those are set**, invites still work: pupils chosen from the list see the invitation in My bands, and email invites open the leader's own email app with the same message ready to send.
* **Redeploy after editing:** the deployed function must match `index.ts` in this folder.
