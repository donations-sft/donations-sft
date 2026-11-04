-- Lets any logged-in clerk/admin set their own display name
-- (needed for accounts created directly via the Supabase dashboard,
-- which never go through the signup form that normally collects it).

create or replace function update_my_full_name(p_name text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(trim(p_name), '') = '' then
    raise exception 'Name cannot be empty';
  end if;
  update profiles set full_name = trim(p_name) where id = auth.uid();
end;
$$;

grant execute on function update_my_full_name to authenticated;
