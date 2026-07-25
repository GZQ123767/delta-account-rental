update public.app_settings set value = '微信 G644373420' where key = 'support_contact';
update public.app_settings set value = '请核对订单金额后使用官方微信收款码付款，并上传付款凭证。管理员核验后开始租用。' where key = 'payment_instructions';
insert into public.app_settings (key, value) values ('payment_qr_url', '') on conflict (key) do nothing;

alter table public.orders add column if not exists payment_proof_path text;
alter table public.orders add column if not exists payment_submitted_at timestamptz;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('platform-assets', 'platform-assets', true, 5242880, array['image/jpeg','image/png','image/webp']),
  ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "admins_manage_platform_assets" on storage.objects;
create policy "admins_manage_platform_assets" on storage.objects for all to authenticated
using (bucket_id = 'platform-assets' and public.is_admin())
with check (bucket_id = 'platform-assets' and public.is_admin());

drop policy if exists "users_upload_payment_proofs" on storage.objects;
create policy "users_upload_payment_proofs" on storage.objects for insert to authenticated
with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "users_read_payment_proofs" on storage.objects;
create policy "users_read_payment_proofs" on storage.objects for select to authenticated
using (bucket_id = 'payment-proofs' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

drop policy if exists "users_delete_payment_proofs" on storage.objects;
create policy "users_delete_payment_proofs" on storage.objects for delete to authenticated
using (bucket_id = 'payment-proofs' and ((storage.foldername(name))[1] = auth.uid()::text or public.is_admin()));

create or replace function public.get_public_settings()
returns table(key text, value text)
language sql stable security definer set search_path = public as $$
  select s.key, s.value from public.app_settings s
  where s.key in ('support_contact', 'payment_instructions', 'payment_qr_url');
$$;

create or replace function public.update_payment_qr_url(qr_url text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin(auth.uid()) then raise exception 'Administrator required'; end if;
  if qr_url is null or char_length(qr_url) > 500 then raise exception 'Invalid payment QR URL'; end if;
  insert into public.app_settings (key, value) values ('payment_qr_url', qr_url)
  on conflict (key) do update set value = excluded.value;
  return true;
end;
$$;

create or replace function public.submit_payment_proof(target_order uuid, proof_path text)
returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if proof_path not like auth.uid()::text || '/%' then raise exception 'Invalid proof path'; end if;
  update public.orders set payment_proof_path = proof_path, payment_submitted_at = now()
  where id = target_order and renter_id = auth.uid() and status = 'pending' and payment_status = 'pending';
  if not found then raise exception 'Order cannot accept payment proof'; end if;
  return true;
end;
$$;

revoke all on function public.update_payment_qr_url(text) from public;
revoke all on function public.submit_payment_proof(uuid, text) from public;
grant execute on function public.update_payment_qr_url(text) to authenticated;
grant execute on function public.submit_payment_proof(uuid, text) to authenticated;
