import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const execFileAsync = promisify(execFile);

export const INNO_APP_ID = '{5E97D4F2-4821-4F2A-A816-C6E7216A427F}';
export const REG_SUBKEY = `Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\${INNO_APP_ID}_is1`;

export const REG_HIVES = [
  `HKCU\\${REG_SUBKEY}`,
  `HKLM\\${REG_SUBKEY}`,
];

/**
 * Parses the raw stdout of `reg.exe query <key>` into a key-value map.
 * @param {string} stdout
 * @returns {Record<string, string>}
 */
export function parseRegOutput(stdout) {
  const result = {};
  if (!stdout || typeof stdout !== 'string') return result;

  const lines = stdout.split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed) continue;

    // Matches lines formatted as: "<ValueName>    <Type>    <ValueData>"
    const match = trimmed.match(/^([^\s]+(?:\s+[^\s]+)*?)\s+(REG_[A-Z_]+)\s*(.*)$/i);
    if (match) {
      const [, name, , val] = match;
      result[name.trim()] = val ? val.trim() : '';
    }
  }

  return result;
}

/**
 * Queries Windows registry for Pouse installation.
 * @param {Object} [options]
 * @param {Function} [options.exec] Optional custom executor for testing.
 * @returns {Promise<{ installed: boolean, version: string|null, installPath: string|null, uninstallString: string|null, quietUninstallString: string|null, keyPath: string|null }>}
 */
export async function queryPouseRegistry({ exec = execFileAsync } = {}) {
  for (const hivePath of REG_HIVES) {
    try {
      const { stdout } = await exec('reg.exe', ['query', hivePath]);
      const data = parseRegOutput(stdout);

      if (data.DisplayName || data.DisplayVersion || data.UninstallString) {
        return {
          installed: true,
          version: data.DisplayVersion || null,
          installPath: data.InstallLocation || null,
          uninstallString: data.UninstallString || null,
          quietUninstallString: data.QuietUninstallString || null,
          keyPath: hivePath,
        };
      }
    } catch {
      // Key does not exist in this hive, continue checking other hive
    }
  }

  return {
    installed: false,
    version: null,
    installPath: null,
    uninstallString: null,
    quietUninstallString: null,
    keyPath: null,
  };
}
