# Calendar Booking System Archive

This document is a trimmed archive for the older Dogs & Llamas calendar and
booking system. It is not Moonlog architecture. For the current repo overview,
read [`MASTER.md`](MASTER.md).

## What It Described

- Static frontend calendar and booking flow.
- Supabase Postgres tables for availability, booking requests, and app config.
- PIN-gated RPCs for admin actions.
- Supabase Edge Function email relay through Gmail SMTP.
- Manual Venmo/Zelle payment handoff.

## Core Tables

- `availability`: one row per day with `available`, `booked`, or `unavailable`.
- `booking_requests`: request lifecycle from `pending` to approved, declined, or
  cancelled, with optional `paid_at`.
- `app_config`: locked key/value store for owner email, sender email, email
  function URL/secret, Venmo handle, and Zelle display value.

## Core Flow

1. Visitor selects available dates.
2. Visitor submits a booking request.
3. Supabase trigger notifies the owner.
4. Admin approves, declines, marks paid, or cancels through PIN-gated RPCs.
5. Client emails are sent by the Edge Function.
6. Payment confirmation is manual after Venmo/Zelle payment lands.

## Files From That System

- `schedule.html`
- `dal-subscriber.js`
- `supabase-schema.sql`
- `supabase/functions/send-email/index.ts`
- `supabase/config.toml`

These notes remain only so the older booking implementation can be understood or
ported later.
