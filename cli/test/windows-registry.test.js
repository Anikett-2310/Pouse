import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { parseRegOutput, queryPouseRegistry, INNO_APP_ID } from '../src/platforms/windows/registry.js';

describe('Windows Registry Module', () => {
  const sampleRegStdout = `
HKEY_CURRENT_USER\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\{5E97D4F2-4821-4F2A-A816-C6E7216A427F}_is1
    DisplayName    REG_SZ    Pouse
    DisplayVersion    REG_SZ    1.0.0
    InstallLocation    REG_SZ    C:\\Users\\Test\\AppData\\Local\\Programs\\Pouse
    UninstallString    REG_SZ    "C:\\Users\\Test\\AppData\\Local\\Programs\\Pouse\\unins000.exe"
    QuietUninstallString    REG_SZ    "C:\\Users\\Test\\AppData\\Local\\Programs\\Pouse\\unins000.exe" /SILENT
`;

  test('parseRegOutput extracts values accurately', () => {
    const parsed = parseRegOutput(sampleRegStdout);
    assert.equal(parsed.DisplayName, 'Pouse');
    assert.equal(parsed.DisplayVersion, '1.0.0');
    assert.equal(parsed.InstallLocation, 'C:\\Users\\Test\\AppData\\Local\\Programs\\Pouse');
    assert.equal(parsed.UninstallString, '"C:\\Users\\Test\\AppData\\Local\\Programs\\Pouse\\unins000.exe"');
    assert.equal(parsed.QuietUninstallString, '"C:\\Users\\Test\\AppData\\Local\\Programs\\Pouse\\unins000.exe" /SILENT');
  });

  test('queryPouseRegistry detects installed Pouse in HKCU', async () => {
    const mockExec = async (cmd, args) => {
      if (cmd === 'reg.exe' && args[1].startsWith('HKCU')) {
        return { stdout: sampleRegStdout, stderr: '' };
      }
      throw new Error('Key not found');
    };

    const result = await queryPouseRegistry({ exec: mockExec });
    assert.equal(result.installed, true);
    assert.equal(result.version, '1.0.0');
    assert.equal(result.installPath, 'C:\\Users\\Test\\AppData\\Local\\Programs\\Pouse');
    assert.ok(result.keyPath.startsWith('HKCU'));
  });

  test('queryPouseRegistry detects installed Pouse in HKLM if HKCU absent', async () => {
    const mockExec = async (cmd, args) => {
      if (cmd === 'reg.exe' && args[1].startsWith('HKCU')) {
        throw new Error('Key not found');
      }
      if (cmd === 'reg.exe' && args[1].startsWith('HKLM')) {
        return { stdout: sampleRegStdout, stderr: '' };
      }
      throw new Error('Key not found');
    };

    const result = await queryPouseRegistry({ exec: mockExec });
    assert.equal(result.installed, true);
    assert.equal(result.version, '1.0.0');
    assert.ok(result.keyPath.startsWith('HKLM'));
  });

  test('queryPouseRegistry returns not installed when absent in both hives', async () => {
    const mockExec = async () => {
      throw new Error('Key not found');
    };

    const result = await queryPouseRegistry({ exec: mockExec });
    assert.equal(result.installed, false);
    assert.equal(result.version, null);
    assert.equal(result.installPath, null);
  });
});
