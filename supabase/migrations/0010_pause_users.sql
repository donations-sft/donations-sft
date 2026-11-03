-- Lets admin pause/resume a clerk or admin account without deleting it
-- (deleting would break the foreign key from receipts.created_by).

alter table profiles add column if not exists active boolean not null default true;

create or replace function admin_set_user_active(p_user_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot pause your own account';
  end if;
  update profiles set active = p_active where id = p_user_id;
end;
$$;

grant execute on function admin_set_user_active to authenticated;
