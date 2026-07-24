alter table public.orders add column if not exists contact text;
alter table public.orders drop constraint if exists orders_contact_length;
alter table public.orders add constraint orders_contact_length check (contact is null or char_length(btrim(contact)) between 3 and 80);

create or replace function public.validate_new_order()
returns trigger language plpgsql security definer set search_path = public as $$
declare listing_record public.listings%rowtype;
declare expected_fee numeric(10,2);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if new.contact is null or char_length(btrim(new.contact)) not between 3 and 80 then raise exception 'A valid contact is required'; end if;
  select * into listing_record from public.listings where id = new.listing_id for update;
  if not found or listing_record.status <> 'approved' or not listing_record.available then raise exception 'Listing is not available'; end if;
  if new.coins_amount > listing_record.coins then raise exception 'Coin quota exceeds inventory'; end if;
  if new.duration_days > listing_record.max_days then raise exception 'Rental duration exceeds limit'; end if;
  expected_fee := ceil(listing_record.unit_price * new.coins_amount / 1000.0);
  new.rental_fee := expected_fee;
  new.deposit := listing_record.deposit;
  new.renter_id := auth.uid();
  new.contact := btrim(new.contact);
  new.status := 'pending';
  new.payment_status := 'pending';
  update public.listings set available = false where id = new.listing_id;
  return new;
end;
$$;

create or replace function public.sync_listing_availability_from_order()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.status in ('cancelled', 'completed') and old.status is distinct from new.status then
    update public.listings set available = (status = 'approved') where id = new.listing_id;
  elsif new.status in ('pending', 'confirmed', 'active') then
    update public.listings set available = false where id = new.listing_id;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_listing_availability_after_order_update on public.orders;
create trigger sync_listing_availability_after_order_update after update of status on public.orders for each row execute procedure public.sync_listing_availability_from_order();
