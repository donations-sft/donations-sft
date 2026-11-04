-- Lets admin rename or delete a head (at any level). Delete is blocked
-- by the existing foreign keys if the head (or a cascaded child) is
-- already used on a receipt — caught and surfaced as a clear message.

create or replace function admin_rename_head(p_head_id uuid, p_name text)
returns heads
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row heads;
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;
  if coalesce(trim(p_name), '') = '' then
    raise exception 'Head name cannot be empty';
  end if;

  update heads set name = trim(p_name) where id = p_head_id returning * into v_row;
  if v_row.id is null then
    raise exception 'Head not found';
  end if;
  return v_row;
end;
$$;

create or replace function admin_delete_head(p_head_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;

  delete from heads where id = p_head_id;
exception
  when foreign_key_violation then
    raise exception 'Cannot delete — this head (or one of its sub-heads) is already used on one or more receipts.';
end;
$$;

grant execute on function admin_rename_head to authenticated;
grant execute on function admin_delete_head to authenticated;
