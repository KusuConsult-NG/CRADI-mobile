// Local, resumable migration state (migration-state.json, gitignored).
//
//   ids.<table>.<firestoreId> → supabase uuid   (tables without a legacy column,
//                                                 plus reports whose Firestore id
//                                                 is not a UUID)
//   users.<firebaseUid>       → supabase user id (mirrors profiles.legacy_firebase_uid)
//   storage.<objectPath>      → new public URL   (objects already copied)
//   passwordResets.<email>    → ISO time a reset email was sent
//
// Ids are assigned and the file is saved BEFORE the corresponding rows are
// written, so a crash between the two never produces a second id for the same
// source document.

import fs from 'node:fs';
import path from 'node:path';
import { newUuid } from './transform.js';

export class MigrationState {
  constructor(file) {
    this.file = file;
    this.data = { version: 1, ids: {}, users: {}, storage: {}, passwordResets: {}, runs: [] };
    if (fs.existsSync(file)) {
      const loaded = JSON.parse(fs.readFileSync(file, 'utf8'));
      this.data = { ...this.data, ...loaded };
    }
  }

  table(name) {
    this.data.ids[name] ??= {};
    return this.data.ids[name];
  }

  getId(tableName, sourceId) {
    return this.table(tableName)[sourceId] ?? null;
  }

  /** Return the recorded uuid for a source id, assigning `preferred` or a new one. */
  idFor(tableName, sourceId, preferred = null) {
    const t = this.table(tableName);
    t[sourceId] ??= preferred ?? newUuid();
    return t[sourceId];
  }

  setId(tableName, sourceId, uuid) {
    this.table(tableName)[sourceId] = uuid;
  }

  save() {
    const tmp = `${this.file}.tmp`;
    fs.mkdirSync(path.dirname(this.file), { recursive: true });
    fs.writeFileSync(tmp, JSON.stringify(this.data, null, 2));
    fs.renameSync(tmp, this.file);
  }
}
