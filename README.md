# Hall Booking Manager

Hall booking, lead pipeline, customer management, and dashboard for a single venue, with admin/staff roles.

## Stack
- **Next.js 14** (App Router) — frontend + server logic
- **Supabase** — Postgres database, auth, row-level security
- Deploy frontend on **Vercel** (free tier), database on **Supabase** (free tier)

## 1. Create your Supabase project
1. Go to https://supabase.com → New Project. Pick a name, password, region.
2. Once created, go to **SQL Editor** → New query, paste the entire contents of `supabase/schema.sql`, and run it. This creates all tables, the conflict-check function, and security policies.
3. Go to **Project Settings → API**. Copy the **Project URL** and **anon public** key.

## 2. Configure the app
1. Copy `.env.local.example` to `.env.local`.
2. Paste in your Project URL and anon key.

## 3. Run locally
```bash
npm install
npm run dev
```
Visit http://localhost:3000 — you'll land on `/login`.

## 4. Create your first account and make it admin
1. Click "Create account" on the login page, sign up with your email.
2. Every new signup defaults to the `staff` role. To promote yourself to `admin`:
   - In Supabase, go to **Table Editor → profiles**.
   - Find your row, change `role` from `staff` to `admin`, save.
3. Sign in again (or refresh) — you'll now see the **Staff** nav item and can manage other accounts' roles from the app itself going forward.

## 5. Deploy
1. Push this code to a GitHub repo.
2. Go to https://vercel.com → New Project → import the repo.
3. Add the same two environment variables (`NEXT_PUBLIC_SUPABASE_URL`, `NEXT_PUBLIC_SUPABASE_ANON_KEY`) in Vercel's project settings.
4. Deploy. Staff can now sign up and use the live URL from any device.

## How the pieces fit together

**Roles.** `profiles.role` is `admin` or `staff`. A Postgres trigger auto-creates a profile row on signup, defaulting to `staff`. Only admins can change roles (enforced by a row-level security policy, not just the UI) and only admins see the Staff management page.

**Booking conflicts.** The `check_booking_conflict` Postgres function checks for overlapping, non-cancelled bookings in the requested time range. The booking form calls this via `supabase.rpc(...)` before insert and blocks submission if conflicts are found, showing exactly which existing booking(s) overlap.

**Leads → Customers → Bookings.** Leads always reference a customer (you can create a new customer inline while creating a lead). Bookings also reference a customer, and optionally a lead (so you can trace which inquiry became a paying event). The customer detail page pulls both histories together.

**Dashboard.** Aggregates are computed server-side on each page load: revenue this month sums `total_price` across non-cancelled bookings in the current month, lead funnel counts group leads by status, and the upcoming events list queries bookings with `start_time >= now()`.

## Extending this
- **Email/SMS reminders**: add a Supabase Edge Function on a cron schedule that queries upcoming bookings and calls a provider like Resend or Twilio.
- **Payments**: the schema already tracks `deposit_paid`/`balance_paid` as booleans; wire these to a real payment provider (Stripe) via a webhook that flips them when a charge succeeds.
- **Multiple halls**: add a `venues` table and a `venue_id` column on `bookings`; update `check_booking_conflict` to filter by venue.
- **Reports/export**: add a server route that queries bookings/leads and returns CSV.

## Known limitations of this v1
- No password reset email customization (Supabase sends a default-styled email — customize this in Supabase Auth settings → Email Templates).
- No file/photo attachments on bookings or customers yet.
- Single hall only — see "Extending this" for multi-venue.
