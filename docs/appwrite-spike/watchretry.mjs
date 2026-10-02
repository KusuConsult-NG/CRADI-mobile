import { readFileSync } from 'node:fs';
const { project, key } = JSON.parse(readFileSync('env.json', 'utf8'));
const EP = 'http://localhost:8080/v1';
const J = { 'content-type': 'application/json', 'x-appwrite-project': project, 'x-appwrite-key': key };
// Watch for ~3 minutes: an 8-attempt exponential backoff would show a second
// attempt well inside that window if retries exist at all.
for (let i = 0; i < 18; i++) {
  const ex = await (await fetch(`${EP}/functions/always-fails/executions`, { headers: J })).json();
  const rows = (ex.executions || []).map((e) => `${e.$createdAt.slice(11, 19)} ${e.trigger}/${e.status}`);
  process.stdout.write(`\r t+${i * 10}s  executions=${ex.total}  ${rows.join('  ')}          `);
  await new Promise((r) => setTimeout(r, 10000));
}
console.log('\ndone');
