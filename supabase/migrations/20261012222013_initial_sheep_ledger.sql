-- إدارة الأغنام: private authorization/commands, public RLS reads and invoker RPCs.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;

create table public.partners (
 id uuid primary key references auth.users(id) on delete restrict,
 slot smallint not null unique check (slot in (1,2)),
 email text not null unique check(email = lower(trim(email))),
 display_name text not null check(length(trim(display_name)) between 1 and 80),
 created_at timestamptz not null default now()
);
create table public.business_settings (
 id boolean primary key default true check(id),
 opening_sheep_count bigint not null default 0 check(opening_sheep_count=0),
 opening_cash_balance numeric(14,2) not null default 0 check(opening_cash_balance=0),
 inventory bigint not null default 0 check(inventory between 0 and 1000000000)
);
insert into public.business_settings(id) values(true);
create table public.transactions (
 id uuid primary key,
 type text not null check(type in ('purchase','sale','expense','loss')),
 transaction_date date not null check(transaction_date >= date '2000-01-01'),
 sheep_count integer,
 amount numeric(14,2),
 expense_category text,
 breed_description text check(length(breed_description)<=200),
 notes text check(length(notes)<=2000),
 created_by uuid not null references public.partners(id),
 updated_by uuid not null references public.partners(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 version integer not null default 1,
 voided boolean not null default false,
 create_fingerprint text not null,
 check ((type='expense' and sheep_count is null) or (type<>'expense' and sheep_count is not null and sheep_count between 1 and 1000000)),
 check ((type='loss' and (amount is null or amount>0)) or (type<>'loss' and amount>0 and amount is not null)),
 check ((type='expense' and expense_category in ('أعلاف','نقل','بيطري','أخرى') and expense_category is not null) or (type<>'expense' and expense_category is null))
);
create index transactions_date_idx on public.transactions(transaction_date desc,created_at desc,id) where not voided;
create index transactions_type_date_idx on public.transactions(type,transaction_date desc) where not voided;
create index transactions_creator_idx on public.transactions(created_by);
create index transactions_updater_idx on public.transactions(updated_by);
create table public.capital_movements (
 id uuid primary key,
 movement_type text not null check(movement_type in ('deposit','withdrawal')),
 amount numeric(14,2) not null check(amount>0),
 movement_date date not null check(movement_date >= date '2000-01-01'),
 partner_id uuid not null references public.partners(id),
 notes text check(length(notes)<=2000),
 created_by uuid not null references public.partners(id),
 updated_by uuid not null references public.partners(id),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 version integer not null default 1,
 voided boolean not null default false,
 create_fingerprint text not null
);
create index capital_date_idx on public.capital_movements(movement_date desc,created_at desc,id) where not voided;
create index capital_partner_idx on public.capital_movements(partner_id);
create index capital_creator_idx on public.capital_movements(created_by);
create index capital_updater_idx on public.capital_movements(updated_by);
create table public.transaction_attachments (
 id uuid primary key default gen_random_uuid(),
 transaction_id uuid not null references public.transactions(id),
 storage_path text not null unique,
 file_type text not null check(file_type in ('image/jpeg','image/png','image/webp')),
 created_by uuid not null references public.partners(id),
 created_at timestamptz not null default now(),
 removed_at timestamptz,
 removed_by uuid references public.partners(id)
);
create index attachments_tx_idx on public.transaction_attachments(transaction_id);
create index attachments_creator_idx on public.transaction_attachments(created_by);
create index attachments_remover_idx on public.transaction_attachments(removed_by);
create table private.audit_log (
 id bigint generated always as identity primary key,
 table_name text not null,
 record_id uuid not null,
 action text not null,
 actor uuid,
 before_data jsonb,
 after_data jsonb,
 occurred_at timestamptz not null default now()
);

create function private.is_partner() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.partners p join auth.users u on u.id=p.id
 where p.id=(select auth.uid()) and p.email=lower(u.email) and u.email_confirmed_at is not null);
$$;
create function private.require_partner() returns uuid language plpgsql stable security definer set search_path='' as $$
 begin if not private.is_partner() then raise exception 'NOT_AUTHORIZED' using errcode='42501'; end if; return auth.uid(); end;
$$;
create function private.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
 begin
 insert into private.audit_log(table_name,record_id,action,actor,before_data,after_data)
 values(TG_TABLE_NAME,coalesce(new.id,old.id),TG_OP,auth.uid(),case when TG_OP<>'INSERT' then to_jsonb(old) end,case when TG_OP<>'DELETE' then to_jsonb(new) end);
 return coalesce(new,old);
 end;
$$;
create trigger audit_transactions after insert or update or delete on public.transactions for each row execute function private.audit_change();
create trigger audit_capital after insert or update or delete on public.capital_movements for each row execute function private.audit_change();
create trigger audit_attachments after insert or update or delete on public.transaction_attachments for each row execute function private.audit_change();

-- Row-level atomic UPDATE serializes inventory changes, including edits and deletes.
-- It does not rely on SUM() snapshots and cannot oversell under concurrent requests.
create function private.inventory_change() returns trigger language plpgsql security definer set search_path='' as $$
 declare before_delta bigint:=0; after_delta bigint:=0;
 begin
 if TG_OP<>'INSERT' and not old.voided then before_delta:=case old.type when 'purchase' then old.sheep_count when 'sale' then -old.sheep_count when 'loss' then -old.sheep_count else 0 end; end if;
 if TG_OP<>'DELETE' and not new.voided then after_delta:=case new.type when 'purchase' then new.sheep_count when 'sale' then -new.sheep_count when 'loss' then -new.sheep_count else 0 end; end if;
 update public.business_settings set inventory=inventory-before_delta+after_delta
 where id=true and inventory-before_delta+after_delta >=0;
 if not found then raise exception 'INSUFFICIENT_INVENTORY' using errcode='23514'; end if;
 return coalesce(new,old);
 end;
$$;
create trigger inventory_guard before insert or update or delete on public.transactions for each row execute function private.inventory_change();

create function private.save_transaction(p_id uuid,p_data jsonb,p_version integer) returns uuid language plpgsql security definer set search_path='' as $$
 declare actor uuid; previous public.transactions; kind text; d date; qty integer; val numeric; cat text;
 begin
 actor:=private.require_partner();
 perform 1 from public.business_settings where id=true for update;
 select * into previous from public.transactions where id=p_id;
 if found and p_version is null then
   if previous.create_fingerprint=md5(p_data::text) and not previous.voided then return p_id; end if;
   raise exception 'VERSION_CONFLICT';
 end if;
 if p_version is not null and (previous.id is null or previous.voided or previous.version<>p_version) then raise exception 'VERSION_CONFLICT'; end if;
 kind:=p_data->>'type'; d:=(p_data->>'transaction_date')::date;
 if kind is null or kind not in ('purchase','sale','expense','loss') or d is null or d>(now() at time zone 'Asia/Riyadh')::date then raise exception 'INVALID_DATA'; end if;
 if kind='expense' then
   if p_data->>'sheep_count' is not null then raise exception 'INVALID_DATA'; end if;
 else
   if coalesce(p_data->>'sheep_count','') !~ '^[0-9]+$' then raise exception 'INVALID_DATA'; end if;
   qty:=(p_data->>'sheep_count')::integer;
 end if;
 if p_data->>'amount' is not null then
   if (p_data->>'amount') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then raise exception 'INVALID_DATA'; end if;
   val:=(p_data->>'amount')::numeric;
 end if;
 cat:=p_data->>'expense_category';
 if p_version is null then
 insert into public.transactions(id,type,transaction_date,sheep_count,amount,expense_category,breed_description,notes,created_by,updated_by,create_fingerprint)
 values(p_id,kind,d,qty,val,cat,nullif(p_data->>'breed_description',''),nullif(p_data->>'notes',''),actor,actor,md5(p_data::text));
 else
 update public.transactions set type=kind,transaction_date=d,sheep_count=qty,amount=val,expense_category=cat,breed_description=nullif(p_data->>'breed_description',''),notes=nullif(p_data->>'notes',''),updated_by=actor,updated_at=now(),version=version+1 where id=p_id;
 end if;
 return p_id;
 end;
$$;
create function private.delete_transaction(p_id uuid,p_version integer) returns void language plpgsql security definer set search_path='' as $$
 declare actor uuid; previous public.transactions;
 begin
 actor:=private.require_partner(); perform 1 from public.business_settings where id=true for update;
 select * into previous from public.transactions where id=p_id;
 if previous.id is null then raise exception 'VERSION_CONFLICT'; end if;
 if previous.voided then return; end if;
 if p_version is null or previous.version<>p_version then raise exception 'VERSION_CONFLICT'; end if;
 update public.transactions set voided=true,version=version+1,updated_by=actor,updated_at=now() where id=p_id;
 end;
$$;
create function private.save_capital(p_id uuid,p_data jsonb,p_version integer) returns uuid language plpgsql security definer set search_path='' as $$
 declare actor uuid; previous public.capital_movements; kind text; d date; val numeric; partner uuid;
 begin
 actor:=private.require_partner(); perform 1 from public.business_settings where id=true for update;
 select * into previous from public.capital_movements where id=p_id;
 if found and p_version is null then
   if previous.create_fingerprint=md5(p_data::text) and not previous.voided then return p_id; end if;
   raise exception 'VERSION_CONFLICT';
 end if;
 if p_version is not null and (previous.id is null or previous.voided or previous.version<>p_version) then raise exception 'VERSION_CONFLICT'; end if;
 kind:=p_data->>'movement_type'; d:=(p_data->>'movement_date')::date; partner:=(p_data->>'partner_id')::uuid;
 if kind is null or kind not in ('deposit','withdrawal') or d is null or d>(now() at time zone 'Asia/Riyadh')::date or coalesce(p_data->>'amount','') !~ '^[0-9]{1,10}(\.[0-9]{1,2})?$' then raise exception 'INVALID_DATA'; end if;
 val:=(p_data->>'amount')::numeric;
 if p_version is null then
 insert into public.capital_movements(id,movement_type,amount,movement_date,partner_id,notes,created_by,updated_by,create_fingerprint)
 values(p_id,kind,val,d,partner,nullif(p_data->>'notes',''),actor,actor,md5(p_data::text));
 else
 update public.capital_movements set movement_type=kind,amount=val,movement_date=d,partner_id=partner,notes=nullif(p_data->>'notes',''),updated_by=actor,updated_at=now(),version=version+1 where id=p_id;
 end if;return p_id;
 end;
$$;
create function private.delete_capital(p_id uuid,p_version integer) returns void language plpgsql security definer set search_path='' as $$
 declare actor uuid; previous public.capital_movements;
 begin
 actor:=private.require_partner(); perform 1 from public.business_settings where id=true for update;
 select * into previous from public.capital_movements where id=p_id;
 if previous.id is null then raise exception 'VERSION_CONFLICT'; end if;
 if previous.voided then return; end if;
 if p_version is null or previous.version<>p_version then raise exception 'VERSION_CONFLICT'; end if;
 update public.capital_movements set voided=true,version=version+1,updated_by=actor,updated_at=now() where id=p_id;
 end;
$$;

create function public.save_transaction(p_id uuid,p_data jsonb,p_version integer default null) returns uuid language sql security invoker set search_path='' as $$ select private.save_transaction(p_id,p_data,p_version); $$;
create function public.delete_transaction(p_id uuid,p_version integer) returns void language sql security invoker set search_path='' as $$ select private.delete_transaction(p_id,p_version); $$;
create function public.save_capital(p_id uuid,p_data jsonb,p_version integer default null) returns uuid language sql security invoker set search_path='' as $$ select private.save_capital(p_id,p_data,p_version); $$;
create function public.delete_capital(p_id uuid,p_version integer) returns void language sql security invoker set search_path='' as $$ select private.delete_capital(p_id,p_version); $$;

-- These read RPCs honor RLS and compute totals in a single database snapshot.
create function public.get_dashboard() returns jsonb language plpgsql stable security invoker set search_path='' as $$
 declare result jsonb;
 begin
 perform private.require_partner();
 with t as(select coalesce(sum(amount) filter(where type='sale'),0) sales,coalesce(sum(amount) filter(where type='purchase'),0) purchases,coalesce(sum(amount) filter(where type='expense'),0) expenses from public.transactions where not voided),
 c as(select coalesce(sum(amount) filter(where movement_type='deposit'),0) deposits,coalesce(sum(amount) filter(where movement_type='withdrawal'),0) withdrawals from public.capital_movements where not voided)
 select jsonb_build_object('inventory',s.inventory,'sales',t.sales::text,'purchases',t.purchases::text,'expenses',t.expenses::text,'trading',(t.sales-t.purchases-t.expenses)::text,'deposits',c.deposits::text,'withdrawals',c.withdrawals::text,'capital',(c.deposits-c.withdrawals)::text,'cash',(s.opening_cash_balance+t.sales-t.purchases-t.expenses+c.deposits-c.withdrawals)::text) into result from t cross join c cross join public.business_settings s;
 return result;
 end;
$$;
create function public.list_transactions(p_offset integer default 0,p_type text default null,p_query text default '') returns jsonb language plpgsql stable security invoker set search_path='' as $$
 begin
 perform private.require_partner();
 return (select coalesce(jsonb_agg(to_jsonb(t)-'create_fingerprint'-'voided'||jsonb_build_object('amount',t.amount::text) order by t.transaction_date desc,t.created_at desc,t.id),'[]'::jsonb) from (select t.* from public.transactions t join public.partners p on p.id=t.created_by where not t.voided and (p_type is null or t.type=p_type) and (coalesce(p_query,'')='' or strpos(lower(concat_ws(' ',t.notes,t.breed_description,t.expense_category,p.display_name,t.transaction_date::text)),lower(left(p_query,200)))>0) order by t.transaction_date desc,t.created_at desc,t.id limit 50 offset greatest(p_offset,0)) t);
 end;
$$;
create function public.list_capital(p_offset integer default 0) returns jsonb language plpgsql stable security invoker set search_path='' as $$
 begin perform private.require_partner();
 return (select coalesce(jsonb_agg(to_jsonb(c)-'create_fingerprint'-'voided'||jsonb_build_object('amount',c.amount::text) order by c.movement_date desc,c.created_at desc,c.id),'[]'::jsonb) from(select * from public.capital_movements where not voided order by movement_date desc,created_at desc,id limit 50 offset greatest(p_offset,0))c);
 end;
$$;

alter table public.partners enable row level security;
alter table public.business_settings enable row level security;
alter table public.transactions enable row level security;
alter table public.capital_movements enable row level security;
alter table public.transaction_attachments enable row level security;
alter table private.audit_log enable row level security;
create policy partners_read on public.partners for select to authenticated using((select private.is_partner()));
create policy settings_read on public.business_settings for select to authenticated using((select private.is_partner()));
create policy transactions_read on public.transactions for select to authenticated using((select private.is_partner()) and not voided);
create policy capital_read on public.capital_movements for select to authenticated using((select private.is_partner()) and not voided);
create policy attachments_read on public.transaction_attachments for select to authenticated using((select private.is_partner()) and removed_at is null and exists(select 1 from public.transactions t where t.id=transaction_id and not t.voided));
-- No direct writes granted. Commands validate auth, amounts, versions and inventory.
revoke all on public.partners,public.business_settings,public.transactions,public.capital_movements,public.transaction_attachments from anon,authenticated;
grant select on public.partners,public.business_settings,public.transactions,public.capital_movements,public.transaction_attachments to authenticated;
revoke all on private.audit_log from public,anon,authenticated;

-- Private immutable receipts. Only the upload Edge Function (service role) writes.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values('receipts','receipts',false,5242880,array['image/jpeg','image/png','image/webp']);
create policy receipts_read on storage.objects for select to authenticated using(bucket_id='receipts' and (select private.is_partner()) and exists(select 1 from public.transaction_attachments a join public.transactions t on t.id=a.transaction_id where a.storage_path=name and a.removed_at is null and not t.voided));

-- Metadata must reference an existing object; upload authorization happens before
-- service-role storage write. Session uid is explicitly passed by the trusted function.
create function private.register_attachment(p_actor uuid,p_transaction uuid,p_path text,p_mime text) returns uuid language plpgsql security definer set search_path='' as $$
 declare attachment_id uuid;
 begin
 if not exists(select 1 from public.partners p join auth.users u on u.id=p.id where p.id=p_actor and p.email=lower(u.email) and u.email_confirmed_at is not null) then raise exception 'NOT_AUTHORIZED'; end if;
 perform 1 from public.transactions where id=p_transaction and not voided for update;
 if not found or split_part(p_path,'/',1)<>p_transaction::text or not exists(select 1 from storage.objects where bucket_id='receipts' and name=p_path) then raise exception 'INVALID_DATA'; end if;
 if (select count(*) from public.transaction_attachments where transaction_id=p_transaction and removed_at is null)>=12 then raise exception 'INVALID_DATA'; end if;
 insert into public.transaction_attachments(transaction_id,storage_path,file_type,created_by) values(p_transaction,p_path,p_mime,p_actor) returning id into attachment_id;
 return attachment_id;
 end;
$$;
create function public.register_attachment(p_actor uuid,p_transaction uuid,p_path text,p_mime text) returns uuid language sql security invoker set search_path='' as $$ select private.register_attachment(p_actor,p_transaction,p_path,p_mime); $$;
create function private.delete_attachment(p_id uuid) returns void language plpgsql security definer set search_path='' as $$
 declare actor uuid;
 begin actor:=private.require_partner();update public.transaction_attachments set removed_at=now(),removed_by=actor where id=p_id and removed_at is null; end;
$$;
create function public.delete_attachment(p_id uuid) returns void language sql security invoker set search_path='' as $$ select private.delete_attachment(p_id); $$;

-- Explicit function grants: PostgreSQL otherwise grants EXECUTE to PUBLIC.
revoke all on all functions in schema private from public,anon,authenticated;
grant execute on function private.is_partner(),private.require_partner(),private.save_transaction(uuid,jsonb,integer),private.delete_transaction(uuid,integer),private.save_capital(uuid,jsonb,integer),private.delete_capital(uuid,integer),private.delete_attachment(uuid) to authenticated;
revoke all on function public.save_transaction(uuid,jsonb,integer),public.delete_transaction(uuid,integer),public.save_capital(uuid,jsonb,integer),public.delete_capital(uuid,integer),public.get_dashboard(),public.list_transactions(integer,text,text),public.list_capital(integer),public.delete_attachment(uuid),public.register_attachment(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.save_transaction(uuid,jsonb,integer),public.delete_transaction(uuid,integer),public.save_capital(uuid,jsonb,integer),public.delete_capital(uuid,integer),public.get_dashboard(),public.list_transactions(integer,text,text),public.list_capital(integer),public.delete_attachment(uuid) to authenticated;
grant usage on schema private to service_role;
grant execute on function private.register_attachment(uuid,uuid,text,text),public.register_attachment(uuid,uuid,text,text) to service_role;
