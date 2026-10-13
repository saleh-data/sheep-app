import test from 'node:test';
import assert from 'node:assert/strict';
import {moneyInput,countInput,money,inventoryDelta,normalizeDigits} from '../lib/domain';
test('Arabic and Persian digits are accepted without float arithmetic',()=>{assert.equal(moneyInput('١٢٣٫٤٥'),'123.45');assert.equal(moneyInput('۰.۱۰'),'0.10');assert.equal(moneyInput('9999999999.99'),'9999999999.99');assert.equal(money('9999999999.99'),'9,999,999,999.99');});
test('invalid currency and fractional livestock rejected',()=>{for(const n of ['-1','0','1.005','1e3','NaN','10000000000','1,200'])assert.throws(()=>moneyInput(n));for(const n of ['0','1.5','-2','NaN'])assert.throws(()=>countInput(n));assert.equal(countInput('١٢'),12);assert.equal(moneyInput('',true),null);});
test('inventory impact is independent of financial estimate',()=>{assert.equal(inventoryDelta({type:'purchase',sheep_count:10}),10);assert.equal(inventoryDelta({type:'sale',sheep_count:2}),-2);assert.equal(inventoryDelta({type:'loss',sheep_count:1}),-1);assert.equal(inventoryDelta({type:'expense',sheep_count:null}),0);assert.equal(normalizeDigits('١٢٣'),'123');});
