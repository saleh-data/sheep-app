-- One reporting period: all non-voided operations since the zero opening balance.
-- Periodic weighted average (not FIFO, moving average, or current market value).
-- Keep the average unrounded for inventory valuation; round totals only to halalas.
create or replace function public.get_dashboard() returns jsonb
language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 perform private.require_partner();
 with t as (
  select coalesce(sum(amount) filter(where type='sale'),0) sales,
         coalesce(sum(amount) filter(where type='purchase'),0) purchases,
         coalesce(sum(sheep_count) filter(where type='purchase'),0) purchased_count,
         coalesce(sum(amount) filter(where type='expense'),0) expenses
  from public.transactions where not voided
 ), c as (
  select coalesce(sum(amount) filter(where movement_type='deposit'),0) deposits,
         coalesce(sum(amount) filter(where movement_type='withdrawal'),0) withdrawals
  from public.capital_movements where not voided
 ), v as (
  select s.inventory,s.opening_cash_balance,t.*,c.*,
         coalesce(t.purchases/nullif(t.purchased_count,0),0) average_cost
  from t cross join c cross join public.business_settings s
 ), totals as (
  select v.*,round(inventory*average_cost,2) inventory_value from v
 )
 select jsonb_build_object(
  'inventory',inventory,
  'sales',sales::text,'purchases',purchases::text,'expenses',expenses::text,
  'trading',(sales-purchases-expenses)::text,
  'deposits',deposits::text,'withdrawals',withdrawals::text,
  'capital',(deposits-withdrawals)::text,
  'cash',(opening_cash_balance+sales-purchases-expenses+deposits-withdrawals)::text,
  'average_cost',round(average_cost,2)::text,
  'inventory_value',inventory_value::text,
  'net_profit',round(sales+inventory_value-purchases-expenses,2)::text
 ) into result from totals;
 return result;
end;
$$;
revoke all on function public.get_dashboard() from public,anon;
grant execute on function public.get_dashboard() to authenticated;
comment on function public.get_dashboard() is 'Lifetime periodic weighted-average purchase cost; loss estimates are informational only. Capital affects cash, never profit. Monetary JSON fields are decimal strings.';
