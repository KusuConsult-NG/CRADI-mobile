import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const H = { 'x-appwrite-project': project, 'x-appwrite-key': key };

// Stamp the ward that actually has members (ewm-a, ewm-b are both in 'north').
const form = new FormData();
form.append('fileId', 'ev-north-1');
form.append('file', new Blob([readFileSync('/tmp/shot.jpg')], { type: 'image/jpeg' }), 'shot.jpg');
form.append('permissions[]', 'read("team:ward-benue-makurdi-north")');
const up = await fetch(`${EP}/storage/buckets/report-images/files`, { method: 'POST', headers: H, body: form });
console.log('upload stamped for ward-north:', up.status);

async function cookieFor(email) {
  const s = await fetch(`${EP}/account/sessions/email`, { method: 'POST',
    headers: { 'content-type': 'application/json', 'x-appwrite-project': project },
    body: JSON.stringify({ email, password: 'SpikePassword123' }) });
  return (s.headers.get('set-cookie') ?? '').split(';')[0];
}
for (const [who, email, expect] of [
  ['ewm-a (IS in ward-north)', 'ewma@example.test', 200],
  ['citizen (in no ward team)', 'citizen@example.test', 404],
]) {
  const cookie = await cookieFor(email);
  const hdr = { 'x-appwrite-project': project, cookie };
  const view = await fetch(`${EP}/storage/buckets/report-images/files/ev-north-1/view`, { headers: hdr });
  const prev = await fetch(`${EP}/storage/buckets/report-images/files/ev-north-1/preview?width=300`, { headers: hdr });
  console.log(`  ${who}: view ${view.status} (expect ${expect}), preview ${prev.status}`);
}
