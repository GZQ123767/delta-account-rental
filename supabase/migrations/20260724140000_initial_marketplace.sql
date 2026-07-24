create extension if not exists pgcrypto;

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '新用户',
  role text not null default 'user' check (role in ('user', 'admin')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 2 and 40),
  category text not null check (category in ('wealth', 'rank', 'starter')),
  game_mode text not null,
  rank_name text not null,
  coins bigint not null check (coins >= 1000),
  feature text not null check (char_length(feature) <= 80),
  unit_price numeric(10,2) not null check (unit_price > 0),
  max_days integer not null check (max_days in (1, 3, 7, 30)),
  deposit numeric(10,2) not null default 0 check (deposit >= 0),
  proof_path text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'paused')),
  available boolean not null default false,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  renter_id uuid not null references public.profiles(id) on delete restrict,
  listing_id uuid not null references public.listings(id) on delete restrict,
  coins_amount bigint not null check (coins_amount >= 1000),
  duration_days integer not null check (duration_days in (1, 3, 7, 30)),
  rental_fee numeric(10,2) not null check (rental_fee > 0),
  deposit numeric(10,2) not null default 0 check (deposit >= 0),
  payment_status text not null default 'pending' check (payment_status in ('pending', 'confirmed', 'refunded', 'cancelled')),
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'active', 'completed', 'cancelled')),
  starts_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.audit_logs (
  id bigint generated always as identity primary key,
  admin_id uuid not null references public.profiles(id) on delete restrict,
  action text not null,
  entity_type text not null,
  entity_id text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.app_settings (
  key text primary key,
  value text not null,
  created_at timestamptz not null default now()
);

insert into public.app_settings (key, value)
values ('admin_bootstrap_hash', '60f919eca807eba52c1725b72356833caa801cf1e6421f9df326f616065c1075');

create or replace function public.is_admin(check_user uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.profiles where id = check_user and role = 'admin');
$$;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', split_part(new.email, '@', 1)));
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_updated_at before update on public.profiles for each row execute procedure public.set_updated_at();
create trigger listings_updated_at before update on public.listings for each row execute procedure public.set_updated_at();
create trigger orders_updated_at before update on public.orders for each row execute procedure public.set_updated_at();

create or replace function public.protect_profile_role()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.role is distinct from old.role and not public.is_admin(auth.uid()) then
    raise exception 'Only administrators can change roles';
  end if;
  return new;
end;
$$;

create trigger protect_profile_role before update on public.profiles
for each row execute procedure public.protect_profile_role();

create or replace function public.claim_initial_admin(secret text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare expected_hash text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.profiles where role = 'admin') then raise exception 'Administrator already initialized'; end if;
  select value into expected_hash from public.app_settings where key = 'admin_bootstrap_hash';
  if encode(digest(secret, 'sha256'), 'hex') <> expected_hash then raise exception 'Invalid initialization code'; end if;
  update public.profiles set role = 'admin' where id = auth.uid();
  delete from public.app_settings where key = 'admin_bootstrap_hash';
  return true;
end;
$$;

revoke all on function public.claim_initial_admin(text) from public;
grant execute on function public.claim_initial_admin(text) to authenticated;

alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.orders enable row level security;
alter table public.audit_logs enable row level security;
alter table public.app_settings enable row level security;

create policy "profiles_read_own_or_admin" on public.profiles for select
using (id = auth.uid() or public.is_admin());
create policy "profiles_update_own_or_admin" on public.profiles for update
using (id = auth.uid() or public.is_admin()) with check (id = auth.uid() or public.is_admin());

create policy "approved_listings_are_public" on public.listings for select
using (status = 'approved' or owner_id = auth.uid() or public.is_admin());
create policy "owners_create_pending_listings" on public.listings for insert to authenticated
with check (owner_id = auth.uid() and status = 'pending' and available = false);
create policy "owners_edit_unapproved_listings" on public.listings for update to authenticated
using (owner_id = auth.uid() and status in ('pending', 'rejected'))
with check (owner_id = auth.uid() and status in ('pending', 'rejected') and available = false);
create policy "owners_delete_unapproved_listings" on public.listings for delete to authenticated
using (owner_id = auth.uid() and status in ('pending', 'rejected'));
create policy "admins_manage_listings" on public.listings for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "renters_create_orders" on public.orders for insert to authenticated
with check (renter_id = auth.uid() and status = 'pending' and payment_status = 'pending');
create policy "participants_read_orders" on public.orders for select to authenticated
using (renter_id = auth.uid() or exists(select 1 from public.listings l where l.id = listing_id and l.owner_id = auth.uid()) or public.is_admin());
create policy "admins_manage_orders" on public.orders for all to authenticated
using (public.is_admin()) with check (public.is_admin());

create policy "admins_read_audit_logs" on public.audit_logs for select to authenticated using (public.is_admin());
create policy "admins_create_audit_logs" on public.audit_logs for insert to authenticated with check (public.is_admin() and admin_id = auth.uid());

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-proofs', 'listing-proofs', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

create policy "users_upload_own_proofs" on storage.objects for insert to authenticated
with check (bucket_id = 'listing-proofs' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "users_read_own_proofs" on storage.objects for select to authenticated
using (bucket_id = 'listing-proofs' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));
create policy "users_delete_own_proofs" on storage.objects for delete to authenticated
using (bucket_id = 'listing-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

grant usage on schema public to anon, authenticated;
grant select on public.listings to anon;
grant select, insert, update, delete on public.listings to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update on public.orders to authenticated;
grant select, insert on public.audit_logs to authenticated;
