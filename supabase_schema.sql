-- ArrowPoint Archery Range database
-- Run this in Supabase SQL Editor. It is safe to re-run for the existing project.

create extension if not exists pgcrypto;

do $$ begin
  create type public.user_role as enum ('customer','admin');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.reservation_status as enum ('pending','confirmed','checked_in','in_progress','completed','cancelled','no_show');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.payment_method as enum ('gcash','cash');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.payment_status as enum ('unpaid','pending_verification','paid','refunded');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default 'New Customer',
  email text,
  phone text,
  role public.user_role not null default 'customer',
  created_at timestamptz not null default now()
);
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists role public.user_role not null default 'customer';

create table if not exists public.services (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  description text,
  duration_minutes int not null check(duration_minutes > 0),
  price numeric(10,2) not null check(price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.range_lanes (
  id uuid primary key default gen_random_uuid(),
  lane_number int unique not null check(lane_number between 1 and 10),
  name text not null,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now()
);

insert into public.range_lanes(lane_number,name)
select n,'Lane '||n from generate_series(1,10) n
on conflict(lane_number) do nothing;

insert into public.services(name,description,duration_minutes,price) values
('Lane Practice','Standard lane rental',60,250),
('Lane Practice - 90 min','Extended lane rental',90,350),
('Lane Practice - 120 min','Two-hour lane rental',120,450),
('Beginner Session','Guided beginner session',60,500)
on conflict(name) do nothing;

create table if not exists public.reservations (
  id uuid primary key default gen_random_uuid(),
  booking_code text unique not null default ('AR-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8))),
  user_id uuid not null references public.profiles(id) on delete cascade,
  service_id uuid references public.services(id) on delete set null,
  customer_name text not null,
  customer_phone text,
  start_time timestamptz not null,
  end_time timestamptz not null,
  lane_number int not null check(lane_number between 1 and 10),
  guests int not null default 1 check(guests between 1 and 10),
  status public.reservation_status not null default 'pending',
  payment_method public.payment_method not null default 'cash',
  payment_status public.payment_status not null default 'unpaid',
  amount_due numeric(10,2) not null default 0 check(amount_due >= 0),
  amount_paid numeric(10,2) not null default 0 check(amount_paid >= 0),
  payment_reference text,
  payment_confirmed_at timestamptz,
  checked_in_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  notes text,
  admin_notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(end_time > start_time)
);

-- Keep older databases compatible.
alter table public.reservations add column if not exists service_id uuid references public.services(id) on delete set null;
alter table public.reservations add column if not exists customer_name text;
alter table public.reservations add column if not exists customer_phone text;
alter table public.reservations add column if not exists guests int default 1;
alter table public.reservations add column if not exists payment_method public.payment_method default 'cash';
alter table public.reservations add column if not exists payment_status public.payment_status default 'unpaid';
alter table public.reservations add column if not exists amount_due numeric(10,2) default 0;
alter table public.reservations add column if not exists amount_paid numeric(10,2) default 0;
alter table public.reservations add column if not exists payment_reference text;
alter table public.reservations add column if not exists payment_confirmed_at timestamptz;
alter table public.reservations add column if not exists checked_in_at timestamptz;
alter table public.reservations add column if not exists started_at timestamptz;
alter table public.reservations add column if not exists completed_at timestamptz;
alter table public.reservations add column if not exists cancelled_at timestamptz;
alter table public.reservations add column if not exists admin_notes text;
alter table public.reservations add column if not exists updated_at timestamptz default now();

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  insert into public.profiles(id,full_name,email,phone)
  values(new.id,coalesce(new.raw_user_meta_data->>'full_name','New Customer'),new.email,new.raw_user_meta_data->>'phone')
  on conflict(id) do update set email=excluded.email;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

create or replace function public.prevent_lane_overlap()
returns trigger language plpgsql as $$
begin
  if new.status not in('cancelled','no_show') and exists(
    select 1 from public.reservations r
    where r.id<>new.id
      and r.lane_number=new.lane_number
      and r.status not in('cancelled','no_show')
      and new.start_time<r.end_time
      and new.end_time>r.start_time
  ) then
    raise exception 'That lane is already reserved during the selected time.';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_lane_overlap on public.reservations;
create trigger prevent_lane_overlap before insert or update on public.reservations
for each row execute procedure public.prevent_lane_overlap();

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at=now(); return new; end; $$;
drop trigger if exists set_reservations_updated_at on public.reservations;
create trigger set_reservations_updated_at before update on public.reservations
for each row execute procedure public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.services enable row level security;
alter table public.range_lanes enable row level security;
alter table public.reservations enable row level security;

drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
using(id=auth.uid() or public.is_admin());

drop policy if exists profiles_update_self on public.profiles;
create policy profiles_update_self on public.profiles for update to authenticated
using(id=auth.uid() or public.is_admin())
with check(id=auth.uid() or public.is_admin());

drop policy if exists services_select on public.services;
create policy services_select on public.services for select to authenticated
using(active=true or public.is_admin());

drop policy if exists services_admin_insert on public.services;
create policy services_admin_insert on public.services for insert to authenticated
with check(public.is_admin());

drop policy if exists services_admin_update on public.services;
create policy services_admin_update on public.services for update to authenticated
using(public.is_admin()) with check(public.is_admin());

drop policy if exists services_admin_delete on public.services;
create policy services_admin_delete on public.services for delete to authenticated
using(public.is_admin());

drop policy if exists lanes_select on public.range_lanes;
create policy lanes_select on public.range_lanes for select to authenticated
using(active=true or public.is_admin());

drop policy if exists lanes_admin_insert on public.range_lanes;
create policy lanes_admin_insert on public.range_lanes for insert to authenticated
with check(public.is_admin());

drop policy if exists lanes_admin_update on public.range_lanes;
create policy lanes_admin_update on public.range_lanes for update to authenticated
using(public.is_admin()) with check(public.is_admin());

drop policy if exists lanes_admin_delete on public.range_lanes;
create policy lanes_admin_delete on public.range_lanes for delete to authenticated
using(public.is_admin());

drop policy if exists reservations_select on public.reservations;
create policy reservations_select on public.reservations for select to authenticated
using(user_id=auth.uid() or public.is_admin());

drop policy if exists reservations_insert on public.reservations;
create policy reservations_insert on public.reservations for insert to authenticated
with check(user_id=auth.uid() or public.is_admin());

drop policy if exists reservations_update on public.reservations;
create policy reservations_update on public.reservations for update to authenticated
using(user_id=auth.uid() or public.is_admin())
with check(user_id=auth.uid() or public.is_admin());

drop policy if exists reservations_delete on public.reservations;
create policy reservations_delete on public.reservations for delete to authenticated
using(user_id=auth.uid() or public.is_admin());

-- Make your account an admin after it exists:
-- update public.profiles set role='admin' where email='YOUR_EMAIL_HERE';
