create policy audit_no_client_access on private.audit_log for all to anon,authenticated using(false) with check(false);
create or replace function private.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
 begin
 insert into private.audit_log(table_name,record_id,action,actor,before_data,after_data)
 values(TG_TABLE_NAME,coalesce(new.id,old.id),TG_OP,coalesce(auth.uid(),(to_jsonb(new)->>'created_by')::uuid),case when TG_OP<>'INSERT' then to_jsonb(old) end,case when TG_OP<>'DELETE' then to_jsonb(new) end);
 return coalesce(new,old);
 end;
$$;
revoke all on function private.audit_change() from public,anon,authenticated;
