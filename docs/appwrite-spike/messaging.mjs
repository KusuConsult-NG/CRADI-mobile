import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const H = { 'content-type': 'application/json', 'x-appwrite-project': project, 'x-appwrite-key': key };
const j = async (p, o = {}) => { const r = await fetch(`${EP}${p}`, { ...o, headers: H }); return { status: r.status, body: await r.json().catch(() => null) }; };

console.log('--- topics: the replacement for OneSignal tag filters');
for (const t of ['lga-benue-makurdi', 'state-benue', 'role-ewv', 'all-users']) {
  const r = await j('/messaging/topics', { method: 'POST', body: JSON.stringify({ topicId: t, name: t, subscribe: ['users'] }) });
  console.log(`  create ${t} -> ${r.status}`);
}

console.log('\n--- a user subscribes to a topic (needs a target)');
const tgt = await j('/users/ewm-b/targets', { method: 'POST', body: JSON.stringify({ targetId: 'tgt-ewmb', providerType: 'push', identifier: 'fake-device-token-123' }) });
console.log('  create push target ->', tgt.status, tgt.status >= 400 ? JSON.stringify(tgt.body?.message).slice(0, 90) : tgt.body.$id);
if (tgt.status < 400) {
  const sub = await j('/messaging/topics/lga-benue-makurdi/subscribers', { method: 'POST', body: JSON.stringify({ subscriberId: 'sub-1', targetId: 'tgt-ewmb' }) });
  console.log('  subscribe to topic ->', sub.status);
}

console.log('\n--- idempotency: OneSignal needed idempotency_key; here the messageId IS the key');
const mk = (id) => j('/messaging/messages/push', { method: 'POST', body: JSON.stringify({
  messageId: id, title: 'Flood warning', body: 'Move to higher ground',
  topics: ['lga-benue-makurdi'], draft: true }) });
const a = await mk('outbox-event-92');
console.log('  first  POST messageId=outbox-event-92 ->', a.status, a.status >= 400 ? JSON.stringify(a.body?.message).slice(0, 90) : 'created');
const b = await mk('outbox-event-92');
console.log('  repeat POST messageId=outbox-event-92 ->', b.status, b.status === 409 ? '409 — duplicate refused, no second send' : JSON.stringify(b.body?.message).slice(0, 90));

console.log('\n--- targeting by user id (OneSignal include_aliases.external_id)');
const u = await j('/messaging/messages/push', { method: 'POST', body: JSON.stringify({
  messageId: 'direct-1', title: 'Your report was approved', body: 'Tap to view',
  users: ['ewm-b'], draft: true }) });
console.log('  users:[...] ->', u.status, u.status >= 400 ? JSON.stringify(u.body?.message).slice(0, 90) : 'accepted');
