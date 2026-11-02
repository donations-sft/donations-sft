-- Fixes "infinite recursion detected in policy for relation profiles":
-- profiles_select_admin's USING clause queried profiles from within a
-- policy that protects profiles itself. Replaced with a SECURITY DEFINER
-- helper function, which bypasses RLS for its own internal check.

create or replace function is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (select 1 from profiles where id = auth.uid() and role = 'admin');
$$;

grant execute on function is_admin to authenticated;

drop policy if exists profiles_select_admin on profiles;
create policy profiles_select_admin on profiles for select
  using (is_admin());
