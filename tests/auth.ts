import {PGlite} from '@electric-sql/pglite';
import {readFile,readdir} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
async function main(){
const db=new PGlite();
try {
 await db.exec(await readFile('tests/bootstrap.sql','utf8'));
 for(const f of (await readdir('supabase/migrations')).filter(f=>f.endsWith('.sql')).sort())await db.exec(await readFile(`supabase/migrations/${f}`,'utf8'));
 await assert.rejects(db.query('insert into auth.users values($1,$2,now())',[randomUUID(),'outsider@example.test']),/SIGNUP_NOT_ALLOWED/);
 const a=randomUUID(),b=randomUUID();
 await db.query('insert into auth.users values($1,$2,null)',[a,'Partner1@example.test']);
 assert.equal((await db.query('select * from public.partners')).rows.length,0);
 await db.query('update auth.users set email_confirmed_at=now() where id=$1',[a]);
 await db.query('insert into auth.users values($1,$2,now())',[b,'partner2@example.test']);
 assert.equal((await db.query('select * from public.partners')).rows.length,2);
 await db.query('update auth.users set email_confirmed_at=now() where id=$1',[a]);
 await db.query("select set_config('request.jwt.claim.sub',$1,false)",[a]);await db.exec('set role authenticated');
 assert.equal((await db.query<{ok:boolean}>('select private.is_partner() ok')).rows[0].ok,true);
 await assert.rejects(db.query('select * from private.signup_allowlist'),/permission denied/);
 await assert.rejects(db.query("update private.signup_allowlist set email='outsider@example.test'"),/permission denied/);
 console.log('Auth checks passed: rejection, confirmation gate, both partners, normalization, idempotence, private allowlist.');
}finally{await db.close();}

}
main().catch(e=>{console.error(e);process.exit(1);});
