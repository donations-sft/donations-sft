-- Keeps profiles.email in sync whenever a user changes their auth email
-- (e.g. via the self-service "Update Email" button in Admin).

create or replace function handle_user_email_update()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.email is distinct from old.email then
    update public.profiles set email = new.email where id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_email_updated on auth.users;
create trigger on_auth_user_email_updated
  after update of email on auth.users
  for each row execute function handle_user_email_update();

-- One-time backfill in case any row is already stale
update profiles p set email = u.email
from auth.users u
where p.id = u.id and p.email is distinct from u.email;
