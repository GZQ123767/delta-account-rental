create or replace function public.validate_new_order()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare listing_record public.listings%rowtype;
declare expected_fee numeric(10,2);
begin
  select * into listing_record from public.listings where id = new.listing_id for update;
  if not found or listing_record.status <> 'approved' or not listing_record.available then
    raise exception 'Listing is not available';
  end if;
  if new.coins_amount > listing_record.coins then raise exception 'Coin quota exceeds inventory'; end if;
  if new.duration_days > listing_record.max_days then raise exception 'Rental duration exceeds limit'; end if;
  expected_fee := ceil(listing_record.unit_price * new.coins_amount / 1000.0);
  new.rental_fee := expected_fee;
  new.deposit := listing_record.deposit;
  new.renter_id := auth.uid();
  new.status := 'pending';
  new.payment_status := 'pending';
  return new;
end;
$$;

create trigger validate_new_order_before_insert
before insert on public.orders
for each row execute procedure public.validate_new_order();
