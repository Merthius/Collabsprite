import test from 'node:test';
import assert from 'node:assert/strict';
import {EventEmitter} from 'node:events';
import {watchOwner} from '../owner-watch.mjs';

function setup() {
  const child=new EventEmitter(); let exited=0,errors=0,killed=0,call;
  child.kill=()=>{killed++; child.emit('exit',null);};
  const cancel=watchOwner({pid:123,start:'639263745311234567',onExit:()=>exited++,onError:()=>errors++,
    launch:(...args)=>{call=args;return child;}});
  return {child,cancel,read:()=>({exited,errors,killed,call})};
}
test('owner exit stops exactly once, with a hidden verified-process helper',()=>{
  const t=setup();t.child.emit('exit',0);t.child.emit('exit',0);
  const s=t.read();assert.equal(s.exited,1);assert.equal(s.errors,0);
  assert.equal(s.call[2].windowsHide,true);assert.equal(s.call[2].stdio,'ignore');
  assert.ok(s.call[1].includes('639263745311234567'));
});
test('permission/helper failure never shuts down a live host',()=>{
  for (const mode of ['error','exit']) {
    const t=setup();t.child.emit(mode,mode==='exit'?22:Error('denied'));t.child.emit('exit',0);
    assert.equal(t.read().exited,0);assert.equal(t.read().errors,1);
  }
});
test('normal shutdown cancels only the owned helper',()=>{
  const t=setup();t.cancel();t.child.emit('exit',0);
  assert.equal(t.read().exited,0);assert.equal(t.read().errors,0);assert.equal(t.read().killed,1);
});
test('invalid owner identities are rejected before starting a process',()=>{
  for (const pid of [0,-1,1.5,2147483648])
    assert.throws(()=>watchOwner({pid,start:'639263745311234567',launch:()=>assert.fail()}));
  assert.throws(()=>watchOwner({pid:2,start:'invalid',launch:()=>assert.fail()}));
});
