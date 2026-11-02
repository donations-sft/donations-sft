-- Admin "Live" dashboard: per-(main)-head totals for Today and Cumulative,
-- plus enabling Postgres Realtime on receipts so the admin screen can
-- auto-refresh when a clerk saves a new receipt.

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
    where h.parent_id is null
    group by h.name, h.sort_order
    order by h.sort_order;
end;
$$;

grant execute on function get_live_totals to authenticated;

alter publication supabase_realtime add table receipts;
