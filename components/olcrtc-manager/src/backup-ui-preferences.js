export const OLC_BACKUP_UI_PREFERENCES_SCHEMA = 1;

const PREFIX = "olc-";
const MAX_VALUE = 64 * 1024;
const MAX_TOTAL = 512 * 1024;
const TRANSIENT = new Set([
  "olc-active-modal-v1",
  "olc-active-feature-modal-v1",
  "olc-modal-client-access-v1",
]);

function eligibleKey(key) {
  return typeof key === "string" && key.startsWith(PREFIX) && !TRANSIENT.has(key);
}

export function collectBackupUIPreferences(storage) {
  const values = {};
  let total = 0;
  try {
    for (let i = 0; i < storage.length; i += 1) {
      const key = storage.key(i);
      if (!eligibleKey(key)) continue;
      const value = storage.getItem(key);
      if (value === null || value.length > MAX_VALUE) continue;
      const nextTotal = total + key.length + value.length;
      if (nextTotal > MAX_TOTAL) break;
      values[key] = value;
      total = nextTotal;
    }
  } catch {
    // Browser storage may be unavailable; server-side backup remains complete.
  }
  return { schema_version: OLC_BACKUP_UI_PREFERENCES_SCHEMA, local_storage: values };
}

export function restoreBackupUIPreferences(rawBackup, storage) {
  try {
    const payload = JSON.parse(rawBackup);
    const values = payload?.ui_preferences?.local_storage;
    if (!values || typeof values !== "object" || Array.isArray(values)) return false;

    const currentKeys = [];
    for (let i = 0; i < storage.length; i += 1) {
      const key = storage.key(i);
      if (eligibleKey(key)) currentKeys.push(key);
    }
    for (const key of currentKeys) storage.removeItem(key);

    let total = 0;
    for (const [key, value] of Object.entries(values)) {
      if (!eligibleKey(key) || typeof value !== "string" || value.length > MAX_VALUE) continue;
      total += key.length + value.length;
      if (total > MAX_TOTAL) break;
      storage.setItem(key, value);
    }
    return true;
  } catch {
    return false;
  }
}
