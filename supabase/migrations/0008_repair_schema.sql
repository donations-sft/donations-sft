-- Idempotent repair: brings receipts/functions to the correct final state
-- regardless of which earlier migrations fully applied. Safe to run any
-- number of times.

-- Postgres treats an added parameter as a NEW overload, not a replacement
-- of the old one, even with CREATE OR REPLACE — so earlier migrations left
-- 3 versions of create_receipt stacked up. Drop the obsolete ones first.
drop function if exists create_receipt(text, text, text, text, text, numeric, text, text, date, text, uuid, uuid, uuid);
drop function if exists create_receipt(text, text, text, text, text, numeric, text, text, date, text, uuid, uuid, uuid, text);

alter table receipts alter column amount drop not null;
alter table receipts add column if not exists item_description text;
alter table receipts add column if not exists donor_email text;
alter table receipts add column if not exists printed boolean not null default false;

alter table receipts drop constraint if exists receipts_amount_check;
alter table receipts add constraint receipts_amount_check check (amount is null or amount > 0);

alter table receipts drop constraint if exists receipts_payment_mode_check;
alter table receipts add constraint receipts_payment_mode_check
  check (payment_mode in ('cash', 'cheque', 'online', 'inkind'));

alter table receipts drop constraint if exists receipts_amount_or_item;
alter table receipts add constraint receipts_amount_or_item check (
  (payment_mode = 'inkind' and item_description is not null)
  or (payment_mode <> 'inkind' and amount is not null)
);

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
  p_further_head_id uuid,
  p_item_description text default null,
  p_donor_email text default null
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
    receipt_no, donor_name, donor_address, donor_city, donor_phone, donor_pan, donor_email,
    amount, payment_mode, cheque_dd_no, cheque_date, cheque_bank,
    main_head_id, sub_head_id, further_head_id, item_description, created_by
  ) values (
    v_receipt_no, p_donor_name, p_donor_address, p_donor_city, p_donor_phone, p_donor_pan, p_donor_email,
    p_amount, p_payment_mode, p_cheque_dd_no, p_cheque_date, p_cheque_bank,
    p_main_head_id, p_sub_head_id, p_further_head_id, p_item_description, auth.uid()
  ) returning * into v_row;

  return v_row;
end;
$$;

grant execute on function create_receipt to authenticated;

create or replace function get_live_totals()
returns table (head_name text, today_total numeric, cumulative_total numeric)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;

  return query
    select h.name,
      coalesce(sum(r.amount) filter (where r.receipt_date = current_date), 0),
      coalesce(sum(r.amount), 0)
    from heads h
    left join receipts r on r.main_head_id = h.id
    where h.parent_id is null and h.name <> 'Inkind Donation'
    group by h.name, h.sort_order
    order by h.sort_order;
end;
$$;

grant execute on function get_live_totals to authenticated;

create or replace function mark_printed(p_receipt_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role in ('clerk', 'admin')) then
    raise exception 'not authorized';
  end if;
  update receipts set printed = true where id = p_receipt_id;
end;
$$;

grant execute on function mark_printed to authenticated;

create or replace function update_receipt(
  p_receipt_id uuid,
  p_donor_name text,
  p_donor_address text,
  p_donor_city text,
  p_donor_phone text,
  p_donor_pan text,
  p_donor_email text,
  p_amount numeric,
  p_payment_mode text,
  p_cheque_dd_no text,
  p_cheque_date date,
  p_cheque_bank text,
  p_main_head_id uuid,
  p_sub_head_id uuid,
  p_further_head_id uuid,
  p_item_description text,
  p_receipt_date date
)
returns receipts
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role text;
  v_created_by uuid;
  v_printed boolean;
  v_row receipts;
begin
  select role into v_role from profiles where id = auth.uid();
  if v_role is null or v_role not in ('clerk', 'admin') then
    raise exception 'not authorized';
  end if;

  select created_by, printed into v_created_by, v_printed from receipts where id = p_receipt_id;
  if v_created_by is null then
    raise exception 'receipt not found';
  end if;

  if v_role = 'clerk' and (v_printed or v_created_by <> auth.uid()) then
    raise exception 'This receipt is locked (already printed/shared). Only an admin can edit it now.';
  end if;

  update receipts set
    donor_name = p_donor_name,
    donor_address = p_donor_address,
    donor_city = p_donor_city,
    donor_phone = p_donor_phone,
    donor_pan = p_donor_pan,
    donor_email = p_donor_email,
    amount = p_amount,
    payment_mode = p_payment_mode,
    cheque_dd_no = p_cheque_dd_no,
    cheque_date = p_cheque_date,
    cheque_bank = p_cheque_bank,
    main_head_id = p_main_head_id,
    sub_head_id = p_sub_head_id,
    further_head_id = p_further_head_id,
    item_description = p_item_description,
    receipt_date = p_receipt_date
  where id = p_receipt_id
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function update_receipt to authenticated;
