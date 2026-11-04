-- Lets admin add a new top-level (Main) donation Head from the app,
-- instead of needing a SQL migration every time.

create or replace function admin_add_head(p_name text)
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

  select coalesce(max(sort_order), 0) + 1 into v_next_sort from heads where parent_id is null;

  insert into heads (parent_id, name, sort_order)
  values (null, trim(p_name), v_next_sort)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function admin_add_head to authenticated;
