-- Dashboard stats: total receipts and donation amounts, today + cumulative.
-- Available to clerk and admin alike (not admin-only, unlike get_live_totals).

create or replace function get_dashboard_stats()
returns table (
  receipts_today bigint,
  receipts_cumulative bigint,
  donations_today numeric,
  donations_cumulative numeric
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role in ('clerk', 'admin')) then
    raise exception 'not authorized';
  end if;

  return query
    select
      count(*) filter (where receipt_date = current_date),
      count(*),
      coalesce(sum(amount) filter (where receipt_date = current_date), 0),
      coalesce(sum(amount), 0)
    from receipts;
end;
$$;

grant execute on function get_dashboard_stats to authenticated;
