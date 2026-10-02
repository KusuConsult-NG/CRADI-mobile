/** Phase 3: does Appwrite Storage cover ImageKit, thumbnails, and evidence immutability? */
import { readFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const H = { 'x-appwrite-project': project, 'x-appwrite-key': key };

async function j(path, o = {}) {
  const r = await fetch(`${EP}${path}`, { ...o, headers: { 'content-type': 'application/json', ...H, ...(o.headers ?? {}) } });
  return { status: r.status, body: await r.json().catch(() => null) };
}

// A real JPEG, so transformations have something to chew on.
execSync(`python3 -c "from PIL import Image; Image.new('RGB',(1600,1200),(20,40,90)).save('/tmp/shot.jpg','JPEG',quality=90)"`);
const isJpeg = execSync('file -b /tmp/shot.jpg').toString().includes('JPEG');
console.log('test image is a real JPEG:', isJpeg);

await j('/storage/buckets', { method: 'POST', body: JSON.stringify({
  bucketId: 'report-images', name: 'report-images', fileSecurity: true,
  permissions: ['create("users")'],
  allowedFileExtensions: ['jpg', 'jpeg', 'png', 'webp'],
}) }).then(r => console.log('create bucket:', r.status, r.body?.message?.slice(0, 60) ?? 'ok'));

// Upload as the server, stamping a ward team the way a report document is stamped.
const form = new FormData();
form.append('fileId', 'ev-001');
form.append('file', new Blob([readFileSync('/tmp/shot.jpg')], { type: 'image/jpeg' }), 'shot.jpg');
form.append('permissions[]', 'read("team:ward-benue-makurdi-centre")');
let r = await fetch(`${EP}/storage/buckets/report-images/files`, { method: 'POST', headers: H, body: form });
console.log('upload evidence:', r.status, (await r.json().catch(() => ({})))?.message?.slice(0, 70) ?? 'ok');

// Evidence must not be overwritable: same id again.
const form2 = new FormData();
form2.append('fileId', 'ev-001');
form2.append('file', new Blob([readFileSync('/tmp/shot.jpg')], { type: 'image/jpeg' }), 'shot.jpg');
r = await fetch(`${EP}/storage/buckets/report-images/files`, { method: 'POST', headers: H, body: form2 });
console.log('re-upload same fileId:', r.status, r.status === 409 ? '409 — cannot be overwritten' : 'OVERWROTE');

// Transformations: the ImageKit job.
for (const q of ['', '?width=300&height=300', '?width=300&quality=60&output=webp']) {
  const res = await fetch(`${EP}/storage/buckets/report-images/files/ev-001/preview${q}`, { headers: H });
  const buf = Buffer.from(await res.arrayBuffer());
  console.log(`  preview${q || ' (full)'} -> ${res.status} ${res.headers.get('content-type')} ${buf.length}B`);
}

// Ward scoping on a FILE, not a document.
async function asUser(email) {
  const s = await fetch(`${EP}/account/sessions/email`, { method: 'POST', headers: { 'content-type': 'application/json', 'x-appwrite-project': project }, body: JSON.stringify({ email, password: 'SpikePassword123' }) });
  return (s.headers.get('set-cookie') ?? '').split(';')[0];
}
for (const [who, email] of [['ewm in that ward', 'ewma@example.test'], ['ewm elsewhere', 'ewmb@example.test']]) {
  const cookie = await asUser(email);
  const res = await fetch(`${EP}/storage/buckets/report-images/files/ev-001/view`, { headers: { 'x-appwrite-project': project, cookie } });
  console.log(`  ${who} reads the file -> ${res.status}`);
}
