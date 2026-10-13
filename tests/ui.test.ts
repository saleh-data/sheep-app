import test from 'node:test';
import assert from 'node:assert/strict';
// DOM interaction test only. This is not a real Safari/browser layout test.
test('Preview has three navigation pages and contextual operation fields',async(t)=>{
 process.env.NEXT_PUBLIC_SUPABASE_URL='https://YOUR_PROJECT.supabase.co';
 const {JSDOM}=await import('jsdom');const dom=new JSDOM('<!doctype html><html><body></body></html>',{url:'http://localhost',pretendToBeVisual:true});
 for(const k of ['window','document','navigator','HTMLElement','HTMLInputElement','Element','Node','NodeFilter','CustomEvent','Event','MutationObserver'])Object.defineProperty(globalThis,k,{value:(dom.window as any)[k],configurable:true});
 Object.defineProperty(globalThis,'getComputedStyle',{value:dom.window.getComputedStyle.bind(dom.window),configurable:true});
 Object.defineProperty(globalThis,'requestAnimationFrame',{value:(fn:()=>void)=>setTimeout(fn,0),configurable:true});
 Object.defineProperty(globalThis,'cancelAnimationFrame',{value:clearTimeout,configurable:true});
 t.after(async()=>{const {supabase}=await import('../lib/supabase');await supabase?.auth.stopAutoRefresh();dom.window.close();});
 const React=await import('react');const {render,screen,fireEvent,within,cleanup}=await import('@testing-library/react');const {default:App}=await import('../components/sheep-app');
 try {render(React.createElement(App,{previewOnly:true}));
 assert.ok(screen.getByText('متوسط تكلفة الرأس'));assert.ok(screen.getByText('قيمة المخزون المتبقي'));assert.ok(screen.getByText('صافي الربح'));
 const nav=screen.getByRole('navigation');assert.equal(within(nav).getAllByRole('button').length,3);
 fireEvent.click(screen.getByRole('button',{name:/إضافة عملية/}));
 fireEvent.click(screen.getByRole('button',{name:/مصاريف.*أعلاف/}));
 assert.equal(document.querySelector('input[name=count]'),null);assert.ok(document.querySelector('select[name=category]'));
 fireEvent.click(screen.getByRole('button',{name:'تغيير نوع العملية'}));
 fireEvent.click(screen.getByRole('button',{name:/هالك.*تسجيل فقد/}));
 assert.ok(document.querySelector('input[name=count]'));assert.equal((document.querySelector('input[name=amount]')as HTMLInputElement).required,false);assert.ok(screen.getByText(/القيمة مرجع للتحليل فقط/));
 fireEvent.click(screen.getByRole('button',{name:'إغلاق'}));
 fireEvent.click(within(nav).getByRole('button',{name:'رأس المال'}));assert.ok(screen.getByRole('button',{name:'إضافة حركة رأس مال'}));
 fireEvent.click(within(nav).getByRole('button',{name:'العمليات'}));assert.ok(screen.getByRole('searchbox'));
 cleanup();}catch(e){console.error(e);cleanup();throw e;}
});
