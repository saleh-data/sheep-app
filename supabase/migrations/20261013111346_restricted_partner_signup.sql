-- Public source uses placeholder emails. Configure these for a NEW database only.
-- Existing hosted database already has the private approved addresses; do not rerun this migration.
-- Server-owned allowlist. Never authorize from user-editable metadata.
create table private.signup_allowlist (
 email text primary key check (email = lower(email)),
 slot smallint not null unique check (slot in (1,2)),
 display_name text not null
);
alter table private.signup_allowlist enable row level security;
revoke all on private.signup_allowlist from public, anon, authenticated;
insert into private.signup_allowlist values
 ('partner1@example.test',1,'الشريك الأول'),
 ('partner2@example.test',2,'الشريك الثاني');
create function private.guard_partner_signup() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if not exists(select 1 from private.signup_allowlist where email=lower(new.email)) then
  raise exception 'SIGNUP_NOT_ALLOWED';
 end if;
 return new;
end $$;
revoke all on function private.guard_partner_signup() from public, anon, authenticated;
create trigger restricted_partner_signup before insert on auth.users
for each row execute function private.guard_partner_signup();
create function private.enroll_confirmed_partner() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
 if new.email_confirmed_at is not null then
  insert into public.partners(id,slot,email,display_name)
  select new.id,a.slot,a.email,a.display_name from private.signup_allowlist a
  where a.email=lower(new.email)
  on conflict (id) do nothing;
 end if;
 return new;
end $$;
revoke all on function private.enroll_confirmed_partner() from public, anon, authenticated;
create trigger enroll_confirmed_partner after insert or update of email_confirmed_at on auth.users
for each row execute function private.enroll_confirmed_partner();
insert into public.partners(id,slot,email,display_name)
select u.id,a.slot,a.email,a.display_name from auth.users u
join private.signup_allowlist a on a.email=lower(u.email)
where u.email_confirmed_at is not null on conflict (id) do nothing;
