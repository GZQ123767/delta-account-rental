alter table public.orders add column if not exists payment_expires_at timestamptz;

update public.orders
set payment_expires_at = created_at + interval '30 minutes'
where payment_expires_at is null and status = 'pending';

alter table public.orders alter column payment_expires_at set default (now() + interval '30 minutes');

insert into public.app_settings (key, value) values
  ('support_contact', '644373420@qq.com'),
  ('payment_instructions', '订单提交后由管理员通过订单联系方式联系。未核对订单编号和金额前，请勿转账。')
on conflict (key) do nothing;

create or replace function public.release_expired_orders()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare released integer;
begin
  update public.orders
  set status = 'cancelled', payment_status = 'cancelled'
  where status = 'pending'
    and payment_status = 'pending'
    and payment_expires_at is not null
    and payment_expires_at <= now();
  get diagnostics released = row_count;
  return released;
end;
$$;

create or replace function public.cancel_my_pending_order(target_order uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  update public.orders
  set status = 'cancelled', payment_status = 'cancelled'
  where id = target_order
    and renter_id = auth.uid()
    and status = 'pending'
    and payment_status = 'pending';
  if not found then raise exception 'Order cannot be cancelled'; end if;
  return true;
end;
$$;

create or replace function public.get_public_settings()
returns table(key text, value text)
language sql
stable
security definer
set search_path = public
as $$
  select s.key, s.value
  from public.app_settings s
  where s.key in ('support_contact', 'payment_instructions');
$$;

create or replace function public.update_public_settings(support_contact text, payment_instructions text)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'Administrator required'; end if;
  if char_length(btrim(support_contact)) not between 3 and 100 then raise exception 'Invalid support contact'; end if;
  if char_length(btrim(payment_instructions)) not between 10 and 300 then raise exception 'Invalid payment instructions'; end if;
  insert into public.app_settings (key, value) values
    ('support_contact', btrim(support_contact)),
    ('payment_instructions', btrim(payment_instructions))
  on conflict (key) do update set value = excluded.value;
  return true;
end;
$$;

revoke all on function public.release_expired_orders() from public;
revoke all on function public.cancel_my_pending_order(uuid) from public;
revoke all on function public.get_public_settings() from public;
revoke all on function public.update_public_settings(text, text) from public;
grant execute on function public.release_expired_orders() to anon, authenticated;
grant execute on function public.cancel_my_pending_order(uuid) to authenticated;
grant execute on function public.get_public_settings() to anon, authenticated;
grant execute on function public.update_public_settings(text, text) to authenticated;
