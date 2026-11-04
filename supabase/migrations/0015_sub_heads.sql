-- Lets admin add a Sub Head under an existing Main Head, not just new
-- top-level Main Heads. Drops the old 1-param overload first (same
-- lesson as the create_receipt overload gotcha).

drop function if exists admin_add_head(text);

create or replace function admin_add_head(p_name text, p_parent_id uuid default null)
returns heads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row heads;
  v_next_sort int;
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'Head name cannot be empty';
  end if;

  select coalesce(max(sort_order), 0) + 1 into v_next_sort
    from heads where parent_id is not distinct from p_parent_id;

  insert into heads (parent_id, name, sort_order)
  values (p_parent_id, trim(p_name), v_next_sort)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function admin_add_head to authenticated;
