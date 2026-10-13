import {createClient} from '@supabase/supabase-js';
import {projectURL,projectPublicKey} from './project-config';
const url=process.env.NEXT_PUBLIC_SUPABASE_URL||projectURL;
const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY||projectPublicKey;
export const configured=!!url&&!!key&&!url.includes('YOUR_PROJECT');
export const supabase=configured?createClient(url!,key!,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}}):null;
