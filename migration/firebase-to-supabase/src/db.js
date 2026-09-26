// Small supabase-js helpers shared by migrate.js and sideEffects.js.

export const PAGE = 1000;
export const IN_CHUNK = 100; // ids per .in() filter, keeps request URLs short

export function must({ data, error }, what) {
  if (error) throw new Error(`${what}: ${error.message ?? JSON.stringify(error)}`);
  return data;
}

/** All rows of `table`, paged. Ordered by `orderBy` (the primary key) so pages are stable. */
export async function selectAll(sb, table, columns, apply = (q) => q, { orderBy = 'id' } = {}) {
  const out = [];
  for (let from = 0; ; from += PAGE) {
    const q = apply(sb.from(table).select(columns)).order(orderBy, { ascending: true });
    const data = must(await q.range(from, from + PAGE - 1), `select ${table}`);
    out.push(...data);
    if (data.length < PAGE) break;
  }
  return out;
}
