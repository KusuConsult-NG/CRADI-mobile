// Content the Supabase schema already seeds (supabase/migrations/
// 20260927040000_builtin_content.sql): the 10 safety guides the app used to
// bundle, inserted into knowledge_base with fixed ids and no legacy id.
// Firestore knowledge_base copies of them are skipped so they are not
// duplicated. test/builtinContent.test.js parses the titles from the SQL file,
// so this list cannot drift from the seed.

import { decodeHtmlEntities } from './transform.js';

export const BUILTIN_GUIDE_TITLES = [
  'River Benue Flooding Protocols',
  'Gully Erosion Mitigation (Nasarawa/Plateau Context)',
  'Extreme Heat Survival (Makurdi/Lafia Corridors)',
  'Bush Fire & Urban Fire Response',
  'Communal Conflict & Security Preparedness (Middle Belt Context)',
  'Road Traffic & Industrial Accident Response',
  'Storm & Severe Weather Safety',
  'Earthquake Preparedness & Response',
  'Epidemic & Disease Outbreak Response',
  'General Safety & Emergency Kit Essentials',
];

/**
 * Case-, whitespace- and punctuation-insensitive form of a title ('&' counts
 * as 'and'; legacy HTML escaping is undone first).
 */
export function normalizeTitle(title) {
  if (typeof title !== 'string') return '';
  return decodeHtmlEntities(title)
    .toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^\p{L}\p{N}]+/gu, '');
}

// Built lazily: transform.js imports this module, so decodeHtmlEntities is
// not usable while the modules are still being evaluated.
let byKey = null;

/** The seeded guide title a knowledge_base title duplicates, or null. */
export function builtinGuideFor(title) {
  byKey ??= new Map(BUILTIN_GUIDE_TITLES.map((t) => [normalizeTitle(t), t]));
  const key = normalizeTitle(title);
  return key ? byKey.get(key) ?? null : null;
}
