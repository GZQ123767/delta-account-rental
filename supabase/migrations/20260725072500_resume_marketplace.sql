insert into public.app_settings (key, value)
values ('business_status', 'active')
on conflict (key) do update set value = excluded.value;

drop trigger if exists reject_new_listing_while_paused on public.listings;
drop trigger if exists reject_new_order_while_paused on public.orders;
drop function if exists public.reject_new_business_while_paused();
