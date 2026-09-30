import { spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export function watchOwner({ pid, start, onExit, onError = () => {}, launch = spawn }) {
  if (!Number.isSafeInteger(pid) || pid < 1 || pid > 2147483647 || !/^[0-9]{18,19}$/.test(start))
    throw Error('Invalid host process identity');
  const flat = fileURLToPath(new URL('./OwnerWatch.ps1', import.meta.url));
  const script = existsSync(flat) ? flat : fileURLToPath(new URL('./extension/OwnerWatch.ps1', import.meta.url));
  const child = launch('powershell.exe', ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', script, '-OwnerPid', String(pid), '-OwnerStart', start], { windowsHide: true, stdio: 'ignore' });
  let cancelled = false, handled = false;
  const finish = (error, code) => {
    if (cancelled || handled) return;
    handled = true;
    if (!error && code === 0) onExit(); else onError();
  };
  child.once('error', error => finish(error));
  child.once('exit', code => finish(null, code));
  return () => { cancelled = true; child.kill(); };
}
