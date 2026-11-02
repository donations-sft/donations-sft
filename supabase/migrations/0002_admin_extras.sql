-- Adds email to profiles (so admin can identify pending users) and an
-- admin-only RPC to read the current next-receipt-number setting.

alter table profiles add column if not exists email text;

create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role, email)
  values (new.id, new.raw_user_meta_data->>'full_name', null, new.email);
  return new;
end;
$$;

update profiles p set email = u.email
from auth.users u
where p.id = u.id and p.email is null;

create or replace function admin_get_next_receipt_no()
returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from profiles where id = auth.uid() and role = 'admin') then
    raise exception 'not authorized';
  end if;
  return (select value::int from app_settings where key = 'next_receipt_no');
end;
$$;

grant execute on function admin_get_next_receipt_no to authenticated;
