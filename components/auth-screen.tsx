'use client';
import {useState,type FormEvent} from 'react';
import {ShieldCheck,LoaderCircle} from 'lucide-react';
import {supabase} from '@/lib/supabase';
import {Button} from './ui/button';
export default function AuthScreen(){
 const [email,setEmail]=useState(''),[password,setPassword]=useState('');
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 async function submit(e:FormEvent){e.preventDefault();if(busy||!supabase)return;setBusy(true);setError('');
 try{
  const {error}=await supabase.auth.signInWithPassword({email:email.trim().toLowerCase(),password});
  if(error)setError('تعذر الدخول. تحقق من البريد وكلمة المرور، أو تواصل مع مسؤول الحساب.');
 }catch{setError('تعذر الاتصال. تحقق من الإنترنت وحاول مرة أخرى.');}finally{setBusy(false);}}
 return <main className="login-wrap"><div className="login-card"><span className="eyebrow">أغنامك وحساباتك، في مكان واحد</span><h1>إدارة الأغنام</h1><h2>تسجيل الدخول</h2><form onSubmit={submit}>
 <label>البريد الإلكتروني<input type="email" dir="ltr" autoComplete="username" value={email} onChange={e=>setEmail(e.target.value)} required disabled={busy}/></label>
 <label>كلمة المرور<input type="password" dir="ltr" autoComplete="current-password" value={password} onChange={e=>setPassword(e.target.value)} required disabled={busy}/></label>
 {error&&<p role="alert" className="error-box">{error}</p>}
 <Button className="full" disabled={busy||!supabase}>{busy&&<LoaderCircle className="spin" size={18}/>} {busy?'جارٍ الدخول…':'تسجيل الدخول'}</Button></form>
 <p>لإنشاء الحساب أو إعادة تعيين كلمة المرور، تواصل مع مسؤول الحساب.</p>
 <p className="secure-note"><ShieldCheck size={16}/> مساحة خاصة للشريكين المعتمدين فقط</p></div></main>;
}
