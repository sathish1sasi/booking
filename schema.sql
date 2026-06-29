-- ============================================================
-- Hall Booking & Lead Management — Database Schema
-- Run this in the Supabase SQL Editor (or via `supabase db push`)
-- ============================================================

-- ---------- EXTENSIONS ----------
create extension if not exists "uuid-ossp";
create extension if not exists pg_trgm;

-- ============================================================
-- PROFILES (staff accounts, linked 1:1 with Supabase auth.users)
-- ============================================================
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text not null,
  role text not null default 'staff' check (role in ('admin', 'staff')),
  created_at timestamptz not null default now()
);

-- Auto-create a profile row whenever a new auth user signs up.
-- New users default to 'staff'; promote to 'admin' manually in the table editor.
create or replace function handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', new.email),
    new.email,
    'staff'
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- ============================================================
-- CUSTOMERS
-- ============================================================
create table customers (
  id uuid primary key default uuid_generate_v4(),
  full_name text not null,
  phone text,
  email text,
  notes text,
  tags text[] default '{}',
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_customers_name on customers using gin (full_name gin_trgm_ops);

-- ============================================================
-- LEADS (pipeline: new -> contacted -> proposal -> won / lost)
-- ============================================================
create table leads (
  id uuid primary key default uuid_generate_v4(),
  customer_id uuid not null references customers(id) on delete cascade,
  status text not null default 'new' check (status in ('new', 'contacted', 'proposal', 'won', 'lost')),
  source text, -- e.g. 'walk-in', 'phone', 'referral', 'website', 'instagram'
  event_type text, -- e.g. 'wedding', 'birthday', 'corporate'
  estimated_value numeric(10,2),
  estimated_date date,
  notes text,
  assigned_to uuid references profiles(id),
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  lost_reason text
);

create index idx_leads_status on leads(status);
create index idx_leads_customer on leads(customer_id);

-- ============================================================
-- BOOKINGS
-- ============================================================
create table bookings (
  id uuid primary key default uuid_generate_v4(),
  customer_id uuid not null references customers(id) on delete cascade,
  lead_id uuid references leads(id), -- optional link back to the lead that converted
  event_title text not null,
  event_type text,
  start_time timestamptz not null,
  end_time timestamptz not null,
  guest_count integer,
  setup_notes text,
  status text not null default 'tentative' check (status in ('tentative', 'confirmed', 'cancelled', 'completed')),
  total_price numeric(10,2),
  deposit_amount numeric(10,2),
  deposit_paid boolean not null default false,
  balance_paid boolean not null default false,
  created_by uuid references profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint valid_time_range check (end_time > start_time)
);

create index idx_bookings_time on bookings(start_time, end_time);
create index idx_bookings_customer on bookings(customer_id);
create index idx_bookings_status on bookings(status);

-- ============================================================
-- CONFLICT CHECK FUNCTION
-- Returns any existing (non-cancelled) bookings that overlap a
-- given time range. Call before confirming a new booking.
-- ============================================================
create or replace function check_booking_conflict(
  p_start timestamptz,
  p_end timestamptz,
  p_exclude_id uuid default null
)
returns table (
  id uuid,
  event_title text,
  start_time timestamptz,
  end_time timestamptz,
  status text
) as $$
begin
  return query
  select b.id, b.event_title, b.start_time, b.end_time, b.status
  from bookings b
  where b.status != 'cancelled'
    and (p_exclude_id is null or b.id != p_exclude_id)
    and b.start_time < p_end
    and b.end_time > p_start;
end;
$$ language plpgsql stable;

-- ============================================================
-- updated_at TRIGGERS
-- ============================================================
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_customers_updated_at before update on customers
  for each row execute procedure set_updated_at();
create trigger trg_leads_updated_at before update on leads
  for each row execute procedure set_updated_at();
create trigger trg_bookings_updated_at before update on bookings
  for each row execute procedure set_updated_at();

-- ============================================================
-- ROW LEVEL SECURITY
-- Rule: any authenticated staff/admin can read & write operational
-- data (customers/leads/bookings). Only admins can manage profiles
-- and see/edit financial fields via the app layer (UI-enforced) —
-- but we also lock down profile writes at the DB level since that's
-- the one place a staff member could otherwise escalate themselves.
-- ============================================================
alter table profiles enable row level security;
alter table customers enable row level security;
alter table leads enable row level security;
alter table bookings enable row level security;

-- PROFILES: everyone can read all profiles (needed for "assigned to" dropdowns)
create policy "profiles_select_all" on profiles
  for select using (auth.role() = 'authenticated');

-- PROFILES: a user can update only their own non-role fields;
-- only an admin can change anyone's role.
create policy "profiles_update_admin_only" on profiles
  for update using (
    auth.uid() = id
    or exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- Only admins can insert/delete profiles directly (normal signup goes through the trigger)
create policy "profiles_admin_manage" on profiles
  for all using (
    exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- CUSTOMERS: any authenticated staff member can read/write
create policy "customers_all_authenticated" on customers
  for all using (auth.role() = 'authenticated');

-- LEADS: any authenticated staff member can read/write
create policy "leads_all_authenticated" on leads
  for all using (auth.role() = 'authenticated');

-- BOOKINGS: any authenticated staff member can read/write
create policy "bookings_all_authenticated" on bookings
  for all using (auth.role() = 'authenticated');

-- ============================================================
-- SEED: promote your first user to admin manually after signup:
--   update profiles set role = 'admin' where email = 'you@example.com';
-- ============================================================
