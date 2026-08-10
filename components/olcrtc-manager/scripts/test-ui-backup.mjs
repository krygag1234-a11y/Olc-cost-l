import assert from "node:assert/strict";
import { collectBackupUIPreferences, restoreBackupUIPreferences } from "../src/backup-ui-preferences.js";

class MemoryStorage {
  constructor(values = {}) { this.values = new Map(Object.entries(values)); }
  get length() { return this.values.size; }
  key(index) { return [...this.values.keys()][index] ?? null; }
  getItem(key) { return this.values.has(key) ? this.values.get(key) : null; }
  setItem(key, value) { this.values.set(key, String(value)); }
  removeItem(key) { this.values.delete(key); }
}

const original = new MemoryStorage({
  "olc-panel-lang-v1": "ru",
  "olc-network-bypass-collapsed": "1",
  "olc-active-modal-v1": "transient-before",
  "foreign-key": "leave-me",
});
const exported = collectBackupUIPreferences(original);
assert.deepEqual(exported, {
  schema_version: 1,
  local_storage: {
    "olc-panel-lang-v1": "ru",
    "olc-network-bypass-collapsed": "1",
  },
});

const target = new MemoryStorage({
  "olc-panel-lang-v1": "en",
  "olc-extra-new-setting": "must-be-removed",
  "olc-active-modal-v1": "transient-now",
  "foreign-key": "leave-me",
});
assert.equal(restoreBackupUIPreferences(JSON.stringify({ ui_preferences: exported }), target), true);
assert.deepEqual(Object.fromEntries(target.values), {
  "olc-active-modal-v1": "transient-now",
  "foreign-key": "leave-me",
  "olc-panel-lang-v1": "ru",
  "olc-network-bypass-collapsed": "1",
});

const beforeLegacy = Object.fromEntries(target.values);
assert.equal(restoreBackupUIPreferences(JSON.stringify({ schema_version: 2 }), target), false);
assert.deepEqual(Object.fromEntries(target.values), beforeLegacy);

console.log("ui backup localStorage round-trip: PASS");
