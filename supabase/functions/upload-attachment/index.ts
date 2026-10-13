import {createClient} from 'npm:@supabase/supabase-js@2.117.3';
const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type','Access-Control-Allow-Methods':'POST, OPTIONS'};
const reply=(data:unknown,status=200)=>Response.json(data,{status,headers:{...cors,'Cache-Control':'no-store'}});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response('ok',{headers:cors});
 if(req.method!=='POST')return reply({error:'METHOD_NOT_ALLOWED'},405);
 try{
  const token=req.headers.get('Authorization')?.replace(/^Bearer\s+/i,'');
  if(!token)return reply({error:'NOT_AUTHORIZED'},401);
  const url=Deno.env.get('SUPABASE_URL')!;
  const pub=JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS')||'{}').default||Deno.env.get('SUPABASE_ANON_KEY')!;
  const user=createClient(url,pub,{global:{headers:{Authorization:`Bearer ${token}`}},auth:{persistSession:false}});
  const {data:auth,error:authError}=await user.auth.getUser(token);
  if(authError||!auth.user)return reply({error:'NOT_AUTHORIZED'},401);
  const {data:partner,error:partnerError}=await user.from('partners').select('id').eq('id',auth.user.id).maybeSingle();
  if(partnerError||!partner)return reply({error:'NOT_AUTHORIZED'},403);
  const length=Number(req.headers.get('content-length')||0);
  if(length>6*1024*1024)return reply({error:'FILE_TOO_LARGE'},413);
  // Bound actual body bytes even when Content-Length is absent or inaccurate.
  const reader=req.body?.getReader();if(!reader)return reply({error:'INVALID_FILE'},400);
  const chunks:Uint8Array[]=[];let total=0;
  while(true){const {done,value}=await reader.read();if(done)break;total+=value.length;if(total>6*1024*1024){await reader.cancel();return reply({error:'FILE_TOO_LARGE'},413);}chunks.push(value);}
  const bytes=new Uint8Array(total);let offset=0;for(const chunk of chunks){bytes.set(chunk,offset);offset+=chunk.length;}
  const form=await new Response(bytes,{headers:{'Content-Type':req.headers.get('content-type')||''}}).formData();
  const tx=String(form.get('transaction_id')||''),file=form.get('file');
  if(!/^[0-9a-f-]{36}$/i.test(tx)||!(file instanceof File)||file.size===0||file.size>5242880)return reply({error:'INVALID_FILE'},400);
  const b=new Uint8Array(await file.arrayBuffer());
  const mime=b[0]===255&&b[1]===216&&b[2]===255?'image/jpeg':b.slice(0,8).every((v,i)=>v===[137,80,78,71,13,10,26,10][i])&&b.length>8?'image/png':b.length>12&&new TextDecoder().decode(b.slice(0,4))==='RIFF'&&new TextDecoder().decode(b.slice(8,12))==='WEBP'?'image/webp':null;
  if(!mime||mime!==file.type)return reply({error:'INVALID_IMAGE'},400);
  const {data:transaction,error}=await user.from('transactions').select('id').eq('id',tx).maybeSingle();
  if(error||!transaction)return reply({error:'NOT_AUTHORIZED'},403);
  const secret=JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS')||'{}').default||Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin=createClient(url,secret,{auth:{persistSession:false}});
  const path=`${tx}/${crypto.randomUUID()}.${mime==='image/jpeg'?'jpg':mime==='image/png'?'png':'webp'}`;
  const {error:uploadError}=await admin.storage.from('receipts').upload(path,b,{contentType:mime,upsert:false,cacheControl:'0'});
  if(uploadError)return reply({error:'UPLOAD_FAILED'},500);
  const {data:id,error:metadataError}=await admin.rpc('register_attachment',{p_actor:auth.user.id,p_transaction:tx,p_path:path,p_mime:mime});
  if(metadataError){await admin.storage.from('receipts').remove([path]);return reply({error:'ATTACHMENT_LIMIT_OR_TRANSACTION_CHANGED'},409);}
  return reply({id});
 }catch{return reply({error:'UPLOAD_FAILED'},400);}
});
