import {supabase} from './supabase';
import type {Transaction,Capital,Metrics,Attachment,Partner,Kind} from './domain';
function db(){if(!supabase)throw Error('يلزم ربط قاعدة البيانات أولًا.');return supabase;}
async function rpc<T>(name:string,args:Record<string,unknown>={}):Promise<T>{const {data,error}=await db().rpc(name,args);if(error)throw error;return data as T;}
export async function partners(){const {data,error}=await db().from('partners').select('id,email,display_name').order('slot');if(error)throw error;return data as Partner[];}
export const dashboard=()=>rpc<Metrics>('get_dashboard');
export const transactions=(offset=0,type:Kind|'all'='all',query='')=>rpc<Transaction[]>('list_transactions',{p_offset:offset,p_type:type==='all'?null:type,p_query:query});
export const capitals=(offset=0)=>rpc<Capital[]>('list_capital',{p_offset:offset});
export const saveTransaction=(id:string,data:Record<string,unknown>,version:number|null)=>rpc<string>('save_transaction',{p_id:id,p_data:data,p_version:version});
export const deleteTransaction=(id:string,version:number)=>rpc<void>('delete_transaction',{p_id:id,p_version:version});
export const saveCapital=(id:string,data:Record<string,unknown>,version:number|null)=>rpc<string>('save_capital',{p_id:id,p_data:data,p_version:version});
export const deleteCapital=(id:string,version:number)=>rpc<void>('delete_capital',{p_id:id,p_version:version});
export async function attachments(id:string){const {data,error}=await db().from('transaction_attachments').select('*').eq('transaction_id',id);if(error)throw error;return data as Attachment[];}
export async function attachmentURL(path:string){const {data,error}=await db().storage.from('receipts').createSignedUrl(path,120);if(error)throw error;return data.signedUrl;}
export async function removeAttachment(id:string){await rpc('delete_attachment',{p_id:id});}
export async function uploadAttachments(id:string,files:File[]){for(const file of files){if(file.size>5*1024*1024||!['image/jpeg','image/png','image/webp'].includes(file.type))throw Error('تقبل الصور بصيغ JPG أو PNG أو WebP فقط، حتى 5 ميجابايت للصورة.');const body=new FormData();body.append('transaction_id',id);body.append('file',file);const {data,error}=await db().functions.invoke('upload-attachment',{body});if(error||data?.error)throw Error('تم حفظ العملية، لكن لم تكتمل المرفقات. افتح تفاصيل العملية لإضافة الصور مجددًا.');}}
