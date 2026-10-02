import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { getPlatformAdapter } from '../src/platforms/index.js';
import { WindowsAdapter } from '../src/platforms/windows/index.js';
import { LinuxAdapter } from '../src/platforms/linux/index.js';
import { MacOSAdapter } from '../src/platforms/macos/index.js';
import { PlatformNotSupportedError } from '../src/core/errors.js';

describe('Platform Adapter Factory', () => {
  test('returns WindowsAdapter for win32', () => {
    const adapter = getPlatformAdapter('win32');
    assert.ok(adapter instanceof WindowsAdapter);
    assert.equal(adapter.name, 'win32');
  });

  test('returns LinuxAdapter for linux and throws PlatformNotSupportedError on methods', async () => {
    const adapter = getPlatformAdapter('linux');
    assert.ok(adapter instanceof LinuxAdapter);
    assert.equal(adapter.name, 'linux');

    await assert.rejects(
      async () => await adapter.detectInstalled(),
      (err) => err instanceof PlatformNotSupportedError && err.message.includes('Windows only')
    );
    await assert.rejects(
      async () => await adapter.install(),
      (err) => err instanceof PlatformNotSupportedError
    );
    await assert.rejects(
      async () => await adapter.uninstall(),
      (err) => err instanceof PlatformNotSupportedError
    );
  });

  test('returns MacOSAdapter for darwin and throws PlatformNotSupportedError on methods', async () => {
    const adapter = getPlatformAdapter('darwin');
    assert.ok(adapter instanceof MacOSAdapter);
    assert.equal(adapter.name, 'darwin');

    await assert.rejects(
      async () => await adapter.detectInstalled(),
      (err) => err instanceof PlatformNotSupportedError && err.message.includes('Windows only')
    );
    await assert.rejects(
      async () => await adapter.install(),
      (err) => err instanceof PlatformNotSupportedError
    );
  });

  test('throws PlatformNotSupportedError for unknown platform', () => {
    assert.throws(
      () => getPlatformAdapter('freebsd'),
      (err) => err instanceof PlatformNotSupportedError
    );
  });
});
