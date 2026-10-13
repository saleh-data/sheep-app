// Run only against a brand-new local PostgreSQL database called sheep_test*.
// This test DOES NOT connect to the production Supabase project.
import {Client} from 'pg';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
async function main(){
 const url=process.env.TEST_DATABASE_URL;if(!url)throw Error('Set TEST_DATABASE_URL to a new, disposable local PostgreSQL database.');
 const parsed=new URL(url);if(!['localhost','127.0.0.1','::1','[::1]'].includes(parsed.hostname)||!parsed.pathname.startsWith('/sheep_test'))throw Error('Refusing non-local or non-test database.');
 const admin=new Client({connectionString:url});await admin.connect();
 const existing=await admin.query("select count(*)::int n from information_schema.tables where table_schema='public'");assert.equal(existing.rows[0].n,0,'Use a fresh test database');
 await admin.query(await readFile('tests/bootstrap.sql','utf8'));
 const actor=randomUUID(),purchase=randomUUID();await admin.query("insert into auth.users values($1,'test@example.test',now())",[actor]);
 for(const p of(await readdir('supabase/migrations')).filter(p=>p.endsWith('.sql')).sort())await admin.query(await readFile(`supabase/migrations/${p}`,'utf8'));
 await admin.query("insert into public.partners(id,slot,email,display_name) values($1,1,'test@example.test','اختبار')",[actor]);
 const a=new Client({connectionString:url}),b=new Client({connectionString:url});await a.connect();await b.connect();
 for(const c of[a,b]){await c.query("select set_config('request.jwt.claim.sub',$1,false)",[actor]);await c.query('set role authenticated');}
 const payload=(type:string,qty:number)=>JSON.stringify({type,transaction_date:'2026-01-01',sheep_count:qty,amount:'100.00',expense_category:null});
 await a.query('select public.save_transaction($1,$2::jsonb,null)',[purchase,payload('purchase',1)]);
 async function race(c:Client,sql:string,params:unknown[]){await c.query('begin');try{await c.query(sql,params);await new Promise(r=>setTimeout(r,150));await c.query('commit');return 'committed';}catch(e){await c.query('rollback');if(String(e).includes('INSUFFICIENT_INVENTORY'))return 'rejected';throw e;}}
 const results=await Promise.all([race(a,'select public.save_transaction($1,$2::jsonb,null)',[randomUUID(),payload('sale',1)]),race(b,'select public.save_transaction($1,$2::jsonb,null)',[randomUUID(),payload('sale',1)])]);
 assert.deepEqual(results.sort(),['committed','rejected']);assert.equal((await admin.query('select inventory from public.business_settings')).rows[0].inventory,'0');
 // Refill two heads; sale-two competes with deletion of that purchase.
 const refill=randomUUID();await a.query('select public.save_transaction($1,$2::jsonb,null)',[refill,payload('purchase',2)]);
 const edits=await Promise.all([race(a,'select public.delete_transaction($1,1)',[refill]),race(b,'select public.save_transaction($1,$2::jsonb,null)',[randomUUID(),payload('sale',2)])]);assert.deepEqual(edits.sort(),['committed','rejected']);
 assert.equal((await admin.query('select inventory from public.business_settings')).rows[0].inventory,'0');
 await a.end();await b.end();await admin.end();console.log('✓ Concurrent sell/sell and delete/sell: only one operation commits; inventory never negative.');
}
main().catch(e=>{console.error(e);process.exit(1);});
