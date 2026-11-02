-- Print-lock: once a receipt is marked printed, the clerk who created it can
-- no longer edit it — only admin can, same as Panjrapole's behaviour.

alter table receipts add column printed boolean not null default false;

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
