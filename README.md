# TargeTara Archery Range Reservation System

A single-page archery range reservation and front-desk operations system.

## Main workflow

Customer:
1. Register / log in
2. Choose a service
3. Choose date, time, lane and number of archers
4. Select GCash or cash
5. Create, edit or cancel their reservation
6. View payment and reservation status

Admin:
1. Log in using an account whose `profiles.role` is `admin`
2. See the operations dashboard
3. Manage all reservations
4. Review/confirm payments
5. Confirm reservations
6. Check customers in
7. Start and complete lane sessions
8. Mark no-shows and cancellations
9. Edit schedules, lanes, services, amounts and admin notes
10. Open/close lanes
11. Manage service pricing and duration
12. Review users and assign the admin role

## Tech stack

- HTML/CSS/JavaScript
- Supabase Auth
- Supabase PostgreSQL
- Supabase Row Level Security
- Express for local/static hosting and deployment

## Setup

1. Create/open a Supabase project.
2. Open Supabase SQL Editor.
3. Run `supabase_schema.sql`.
4. Register your account through `index.html`.
5. In Supabase Table Editor, open `public.profiles` and change your account's `role` to `admin`, or run:

```sql
update public.profiles
set role='admin'
where email='YOUR_EMAIL_HERE';
```

6. Open `public/index.html`.
7. Replace:
   - `YOUR_SUPABASE_URL`
   - `YOUR_SUPABASE_ANON_OR_PUBLISHABLE_KEY`
8. Run locally:

```bash
npm install
npm start
```

Then open `http://localhost:3000`.

## GitHub

Upload the project files to your repository. Do not upload `.env` files or Supabase service-role/secret keys.

## Admin security

The admin interface is part of the same `index.html`, but the interface is not the security boundary. Supabase RLS policies check the user's role before allowing admin operations.

Do not put a Supabase `service_role` key in browser code or GitHub.

## AI disclosure

AI tools were used to assist with UI structure, JavaScript implementation, database schema drafting, documentation and debugging. The student should review and understand the code before submission.

## Suggested future upgrades

- GCash QR upload/receipt storage using Supabase Storage
- SMS/email booking notifications
- Digital waiver
- Equipment inventory
- Maintenance schedule
- Walk-in bookings
- Daily cash/revenue report
- Audit log for admin changes
- Memberships and discounts
- Multiple range branches
- More granular staff permissions
