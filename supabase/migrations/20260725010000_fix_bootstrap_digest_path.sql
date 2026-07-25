create or replace function public.claim_initial_admin(secret text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare expected_hash text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if exists(select 1 from public.profiles where role = 'admin') then raise exception 'Administrator already initialized'; end if;
  select value into expected_hash from public.app_settings where key = 'admin_bootstrap_hash';
  if encode(extensions.digest(secret, 'sha256'), 'hex') <> expected_hash then raise exception 'Invalid initialization code'; end if;
  perform set_config('app.claiming_initial_admin', 'true', true);
  update public.profiles set role = 'admin' where id = auth.uid();
  delete from public.app_settings where key = 'admin_bootstrap_hash';
  return true;
end;
$$;

revoke all on function public.claim_initial_admin(text) from public;
grant execute on function public.claim_initial_admin(text) to authenticated;
