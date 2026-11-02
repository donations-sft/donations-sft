-- Inkind Donation receipts record an item description instead of an amount,
-- and are excluded from the Live Totals (no money involved).

alter table receipts alter column amount drop not null;

alter table receipts drop constraint receipts_amount_check;
alter table receipts add constraint receipts_amount_check check (amount is null or amount > 0);

alter table receipts drop constraint receipts_payment_mode_check;
alter table receipts add constraint receipts_payment_mode_check
  check (payment_mode in ('cash', 'cheque', 'online', 'inkind'));

alter table receipts add column item_description text;

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
  p_item_description text default null
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
    main_head_id, sub_head_id, further_head_id, item_description, created_by
  ) values (
    v_receipt_no, p_donor_name, p_donor_address, p_donor_city, p_donor_phone, p_donor_pan,
    p_amount, p_payment_mode, p_cheque_dd_no, p_cheque_date, p_cheque_bank,
    p_main_head_id, p_sub_head_id, p_further_head_id, p_item_description, auth.uid()
  ) returning * into v_row;

  return v_row;
end;
$$;

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
