alter table receipts add column donor_email text;

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
