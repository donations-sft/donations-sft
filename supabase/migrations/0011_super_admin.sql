-- Introduces a super-admin tier: only the super admin can approve a new
-- admin or pause/resume an existing admin. Regular admins keep full
-- control over clerks, just not over other admins.

alter table profiles add column if not exists is_super_admin boolean not null default false;

create or replace function is_super_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin' and is_super_admin = true);
$$;

grant execute on function is_super_admin to authenticated;

create or replace function admin_set_user_active(p_user_id uuid, p_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_target_role text;
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot pause your own account';
  end if;

  select role into v_target_role from profiles where id = p_user_id;
  if v_target_role = 'admin' and not is_super_admin() then
    raise exception 'Only the super admin can pause or resume another admin';
  end if;

  update profiles set active = p_active where id = p_user_id;
end;
$$;

create or replace function admin_set_user_role(p_user_id uuid, p_role text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;
  if p_role not in ('clerk', 'admin') then
    raise exception 'invalid role';
  end if;
  if p_role = 'admin' and not is_super_admin() then
    raise exception 'Only the super admin can approve someone as admin';
  end if;
  update profiles set role = p_role where id = p_user_id;
end;
$$;

create or replace function admin_set_super_admin(p_user_id uuid, p_is_super boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not is_super_admin() then
    raise exception 'Only the super admin can change super-admin status';
  end if;
  if p_user_id = auth.uid() and p_is_super = false then
    raise exception 'You cannot remove your own super-admin status this way — have another super admin do it, or use SQL';
  end if;
  update profiles set is_super_admin = p_is_super where id = p_user_id and role = 'admin';
end;
$$;

grant execute on function admin_set_user_active to authenticated;
grant execute on function admin_set_user_role to authenticated;
grant execute on function admin_set_super_admin to authenticated;
