import { networkInterfaces } from 'node:os';

const octets = value => {
  const parts = String(value).split('.').map(Number);
  return parts.length === 4 && parts.every(n => Number.isInteger(n) && n >= 0 && n <= 255) ? parts : null;
};
const privateAddress = value => {
  const p = octets(value);
  return !!p && (p[0] === 10 || (p[0] === 172 && p[1] >= 16 && p[1] <= 31) || (p[0] === 192 && p[1] === 168));
};
const vpnAddress = value => octets(value)?.[0] === 26;

export function interfaces(source = networkInterfaces()) {
  return Object.values(source).flatMap(entries => entries || [])
    .filter(entry => entry.family === 'IPv4' && !entry.internal && octets(entry.address) && octets(entry.netmask));
}

export function allowedPeer(address, localOnly = false, source = networkInterfaces()) {
  const peer = String(address || '').replace(/^::ffff:/, '');
  if (peer === '127.0.0.1' || peer === '::1') return true;
  if (localOnly) return false;
  const bytes = octets(peer);
  if (!bytes) return false;
  return interfaces(source).some(entry => {
    const host = octets(entry.address), mask = octets(entry.netmask);
    if (vpnAddress(entry.address) && vpnAddress(peer)) return true;
    return privateAddress(entry.address) && privateAddress(peer) &&
      bytes.every((part, i) => (part & mask[i]) === (host[i] & mask[i]));
  });
}

export function addresses(source = networkInterfaces()) {
  const entries = interfaces(source);
  const lan = entries.filter(entry => privateAddress(entry.address)).map(entry => entry.address);
  const vpn = entries.filter(entry => vpnAddress(entry.address)).map(entry => entry.address);
  return [...new Set([...lan, ...vpn])];
}

export function invite(endpoints, port, room, token) {
  return `${(endpoints.length ? endpoints : ['127.0.0.1']).map(address => `${address}:${port}`).join(',')}/${room}/${token}`;
}

export function replyAddress(peer, localOnly = false, source = networkInterfaces()) {
  if (peer === '127.0.0.1' || peer === '::1' || localOnly) return '127.0.0.1';
  const entries = interfaces(source);
  const match = entries.find(entry => allowedPeer(peer, false, { one: [entry] }));
  return match?.address || null;
}
