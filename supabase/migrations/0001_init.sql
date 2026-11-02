-- Shroffs Foundation Trust — Donation Receipts
-- Initial schema: heads hierarchy, profiles/roles, settings, receipts, RPCs, RLS

create extension if not exists pgcrypto;

-- ── Heads (Main Head / Sub Head / further Head, self-referencing) ──────────
create table heads (
  id uuid primary key default gen_random_uuid(),
  parent_id uuid references heads(id) on delete cascade,
  name text not null,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

-- ── Profiles (clerk/admin roles tied to Supabase Auth users) ───────────────
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text check (role in ('clerk', 'admin')), -- null = pending admin approval
  created_at timestamptz not null default now()
);

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, new.raw_user_meta_data->>'full_name', null);
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ── Settings (admin-configurable, e.g. next receipt number) ────────────────
create table app_settings (
  key text primary key,
  value text not null,
  updated_at timestamptz not null default now()
);

insert into app_settings (key, value) values ('next_receipt_no', '1');

-- ── Receipts ─────────────────────────────────────────────────────────────
create table receipts (
  id uuid primary key default gen_random_uuid(),
  receipt_no int not null unique,
  receipt_date date not null default current_date,
  donor_name text not null,
  donor_address text,
  donor_city text,
  donor_phone text,
  donor_pan text,
  amount numeric(12,2) not null check (amount > 0),
  payment_mode text not null check (payment_mode in ('cash', 'cheque', 'online')),
  cheque_dd_no text,
  cheque_date date,
  cheque_bank text,
  main_head_id uuid not null references heads(id),
  sub_head_id uuid references heads(id),
  further_head_id uuid references heads(id),
  created_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

create index receipts_donor_name_idx on receipts (donor_name);
create index receipts_receipt_date_idx on receipts (receipt_date);
create index receipts_main_head_idx on receipts (main_head_id);

-- ── RPCs ─────────────────────────────────────────────────────────────────

-- Admin-only: set the starting/next receipt number before go-live
create or replace function admin_set_next_receipt_no(p_value int)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;
  update app_settings set value = p_value::text, updated_at = now() where key = 'next_receipt_no';
end;
$$;

-- Admin-only: approve a pending user and assign their role
create or replace function admin_set_user_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;
  if p_role not in ('clerk', 'admin') then
    raise exception 'invalid role';
  end if;
  update profiles set role = p_role where id = p_user_id;
end;
$$;

-- Clerk/admin: create a receipt, atomically assigning the next receipt number
create or replace function create_receipt(
  p_donor_name text,
  p_donor_address text,
  p_donor_city text,
  p_donor_phone text,
  p_donor_pan text,
  p_amount numeric,
  p_payment_mode text,
  p_cheque_dd_no text,
  p_cheque_date date,
  p_cheque_bank text,
  p_main_head_id uuid,
  p_sub_head_id uuid,
  p_further_head_id uuid
)
returns receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_receipt_no int;
  v_row receipts;
begin
  if not exists (select 1 from profiles where id = auth.uid() and role in ('clerk', 'admin')) then
    raise exception 'not authorized';
  end if;

  update app_settings
    set value = (value::int + 1)::text, updated_at = now()
    where key = 'next_receipt_no'
    returning (value::int - 1) into v_receipt_no;

  insert into receipts (
    receipt_no, donor_name, donor_address, donor_city, donor_phone, donor_pan,
    amount, payment_mode, cheque_dd_no, cheque_date, cheque_bank,
    main_head_id, sub_head_id, further_head_id, created_by
  ) values (
    v_receipt_no, p_donor_name, p_donor_address, p_donor_city, p_donor_phone, p_donor_pan,
    p_amount, p_payment_mode, p_cheque_dd_no, p_cheque_date, p_cheque_bank,
    p_main_head_id, p_sub_head_id, p_further_head_id, auth.uid()
  ) returning * into v_row;

  return v_row;
end;
$$;

-- ── RLS ──────────────────────────────────────────────────────────────────
alter table heads enable row level security;
alter table profiles enable row level security;
alter table app_settings enable row level security;
alter table receipts enable row level security;

create policy heads_select on heads for select
  using (exists (select 1 from profiles where id = auth.uid() and role in ('clerk', 'admin')));

create policy profiles_select_own on profiles for select
  using (id = auth.uid());

create policy profiles_select_admin on profiles for select
  using (exists (select 1 from profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy receipts_select on receipts for select
  using (exists (select 1 from profiles where id = auth.uid() and role in ('clerk', 'admin')));

-- app_settings: no direct client access at all (only via SECURITY DEFINER RPCs above)

-- ── Grants ───────────────────────────────────────────────────────────────
-- Schema was hand-created via SQL editor, so default grants are NOT implicit — set them explicitly.
grant usage on schema public to authenticated;

grant select on heads to authenticated;
grant select on receipts to authenticated;
grant select on profiles to authenticated;

revoke all on app_settings from authenticated, anon;
revoke insert, update, delete on receipts from authenticated, anon;
revoke insert, update, delete on heads from authenticated, anon;
revoke insert, update, delete on profiles from authenticated, anon;

grant execute on function create_receipt to authenticated;
grant execute on function admin_set_next_receipt_no to authenticated;
grant execute on function admin_set_user_role to authenticated;

-- ── Seed: Head hierarchy (from "App Outcome.pdf") ───────────────────────
do $$
declare
  v_main_sft uuid;
  v_sub_mph uuid;
  v_sub_et uuid;
  v_sub_dl uuid;
begin
  insert into heads (parent_id, name, sort_order) values (null, 'One day Meal', 1);
  insert into heads (parent_id, name, sort_order) values (null, 'Corpus One day Meal', 2);
  insert into heads (parent_id, name, sort_order) values (null, 'SFT General Activities', 3) returning id into v_main_sft;
  insert into heads (parent_id, name, sort_order) values (null, 'Inkind Donation', 4);

  insert into heads (parent_id, name, sort_order) values (v_main_sft, 'MPH', 1) returning id into v_sub_mph;
  insert into heads (parent_id, name, sort_order) values (v_main_sft, 'E&T', 2) returning id into v_sub_et;
  insert into heads (parent_id, name, sort_order) values (v_main_sft, 'D&L', 3) returning id into v_sub_dl;

  insert into heads (parent_id, name, sort_order) values
    (v_sub_mph, 'Poor Patient Fund/Dialysis Support', 1),
    (v_sub_mph, 'Hospital Equipment', 2),
    (v_sub_mph, 'Geriatric Care', 3),
    (v_sub_mph, 'Canteen Block', 4),
    (v_sub_mph, 'Dialysis Van', 5),
    (v_sub_mph, 'Drug Lab', 6),
    (v_sub_mph, 'SMC Building', 7),
    (v_sub_mph, 'SMC Hodko Bhavna Vatika', 8),
    (v_sub_mph, 'SMC Hodko Building Expansion', 9),
    (v_sub_mph, 'Sneh Sanjivani', 10),
    (v_sub_mph, 'Flood R&M', 11),
    (v_sub_mph, 'Relief', 12),
    (v_sub_mph, 'Solar RKPH', 13);

  insert into heads (parent_id, name, sort_order) values
    (v_sub_et, 'Education Training', 1),
    (v_sub_et, 'Vivec Main. Fund', 2);

  insert into heads (parent_id, name, sort_order) values
    (v_sub_dl, 'Agri Diversification', 1),
    (v_sub_dl, 'Bio Inputs', 2);
end $$;
