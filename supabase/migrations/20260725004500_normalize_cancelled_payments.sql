create or replace function public.normalize_cancelled_order_payment()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'cancelled' and old.status is distinct from new.status then
    new.payment_status := case when old.payment_status = 'confirmed' then 'refunded' else 'cancelled' end;
  end if;
  return new;
end;
$$;

drop trigger if exists normalize_cancelled_order_payment_before_update on public.orders;
create trigger normalize_cancelled_order_payment_before_update
before update of status on public.orders
for each row execute procedure public.normalize_cancelled_order_payment();
