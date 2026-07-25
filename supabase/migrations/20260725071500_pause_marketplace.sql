insert into public.app_settings (key, value)
values ('business_status', 'paused')
on conflict (key) do update set value = excluded.value;

create or replace function public.reject_new_business_while_paused()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.app_settings
    where key = 'business_status' and value = 'paused'
  ) then
    raise exception 'Marketplace is temporarily paused';
  end if;

  return new;
end;
$$;

drop trigger if exists reject_new_listing_while_paused on public.listings;
create trigger reject_new_listing_while_paused
before insert on public.listings
for each row execute procedure public.reject_new_business_while_paused();

drop trigger if exists reject_new_order_while_paused on public.orders;
create trigger reject_new_order_while_paused
before insert on public.orders
for each row execute procedure public.reject_new_business_while_paused();

revoke all on function public.reject_new_business_while_paused() from public;
