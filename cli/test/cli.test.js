import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { parseArgs, getHelpText, runCli } from '../src/cli.js';
import { PouseError, PlatformNotSupportedError } from '../src/core/errors.js';

describe('CLI Argument Parser & Dispatcher', () => {
  test('parseArgs parses commands and flags accurately', () => {
    const { command, options } = parseArgs([
      'node', 'bin/pouse.js',
      'install',
      '--silent',
      '--force',
      '--release', 'v1.0.0',
      '--unsafe-no-checksum',
      '--verbose',
    ]);

    assert.equal(command, 'install');
    assert.equal(options.silent, true);
    assert.equal(options.force, true);
    assert.equal(options.release, 'v1.0.0');
    assert.equal(options.unsafeNoChecksum, true);
    assert.equal(options.verbose, true);
  });

  test('parseArgs parses short flags', () => {
    const { command, options } = parseArgs([
      'node', 'bin/pouse.js',
      'update',
      '-s',
      '-f',
      '-r', '1.0.0',
    ]);

    assert.equal(command, 'update');
    assert.equal(options.silent, true);
    assert.equal(options.force, true);
    assert.equal(options.release, '1.0.0');
  });

  test('parseArgs parses --release=<version>', () => {
    const { options } = parseArgs([
      'node', 'bin/pouse.js',
      'install',
      '--release=v1.2.3',
    ]);

    assert.equal(options.release, 'v1.2.3');
  });

  test('parseArgs throws on missing release argument', () => {
    assert.throws(
      () => parseArgs(['node', 'bin/pouse.js', 'install', '--release']),
      (err) => err instanceof PouseError && err.message.includes('requires a version argument')
    );
  });

  test('parseArgs throws on unknown option', () => {
    assert.throws(
      () => parseArgs(['node', 'bin/pouse.js', '--invalid-flag']),
      (err) => err instanceof PouseError && err.message.includes('Unknown option')
    );
  });

  test('getHelpText contains essential command guidance', () => {
    const help = getHelpText();
    assert.ok(help.includes('pouse <command> [options]'));
    assert.ok(help.includes('install'));
    assert.ok(help.includes('update'));
    assert.ok(help.includes('uninstall'));
    assert.ok(help.includes('--unsafe-no-checksum'));
  });

  test('runCli --help prints help and exits with 0', async () => {
    const logs = [];
    const mockLogger = {
      info: (msg) => logs.push(msg),
      error: () => {},
      warn: () => {},
      debug: () => {},
      success: () => {},
    };

    const code = await runCli(['node', 'bin/pouse.js', '--help'], { logger: mockLogger });
    assert.equal(code, 0);
    assert.ok(logs.some((l) => l.includes('Pouse CLI')));
  });

  test('runCli --version prints versions and exits with 0', async () => {
    const logs = [];
    const mockLogger = {
      info: (msg) => logs.push(msg),
      error: () => {},
      warn: () => {},
      debug: () => {},
      success: () => {},
    };

    const mockAdapter = {
      name: 'win32',
      detectInstalled: async () => ({
        installed: true,
        version: '1.0.0',
        installPath: 'C:\\Pouse',
      }),
    };

    const code = await runCli(['node', 'bin/pouse.js', '--version'], {
      logger: mockLogger,
      adapter: mockAdapter,
    });
    assert.equal(code, 0);
    assert.ok(logs.some((l) => l.includes('pouse-cli v1.0.1')));
    assert.ok(logs.some((l) => l.includes('Pouse Desktop: v1.0.0')));
  });

  test('runCli install runs full workflow on Windows', async () => {
    const logs = [];
    const mockLogger = {
      info: (msg) => logs.push(msg),
      error: (msg) => logs.push(`ERR: ${msg}`),
      warn: (msg) => logs.push(`WARN: ${msg}`),
      debug: () => {},
      success: (msg) => logs.push(`OK: ${msg}`),
    };

    let installedCalled = false;
    const mockAdapter = {
      name: 'win32',
      detectInstalled: async () => ({ installed: false, version: null }),
      ensureProcessClosed: async () => {},
      install: async (path, opts) => {
        installedCalled = true;
      },
    };

    const mockReleaseService = {
      getRelease: async () => ({
        tag_name: 'v1.0.0',
        assets: [{ name: 'Pouse-Setup-v1.0.0.exe' }],
      }),
      downloadAndVerifyInstaller: async () => ({
        installerPath: 'C:\\fake\\Pouse-Setup-v1.0.0.exe',
        version: 'v1.0.0',
        assetName: 'Pouse-Setup-v1.0.0.exe',
        checksumVerified: true,
      }),
    };

    const code = await runCli(['node', 'bin/pouse.js', 'install'], {
      logger: mockLogger,
      adapter: mockAdapter,
      releaseService: mockReleaseService,
    });

    assert.equal(code, 0);
    assert.equal(installedCalled, true);
    assert.ok(logs.some((l) => l.includes('Pouse v1.0.0 has been successfully installed')));
  });

  test('runCli update skips when already up to date without force', async () => {
    const logs = [];
    const mockLogger = {
      info: (msg) => logs.push(msg),
      error: () => {},
      warn: () => {},
      debug: () => {},
      success: () => {},
    };

    let installedCalled = false;
    const mockAdapter = {
      name: 'win32',
      detectInstalled: async () => ({ installed: true, version: '1.0.0' }),
      ensureProcessClosed: async () => {},
      install: async () => { installedCalled = true; },
    };

    const mockReleaseService = {
      getRelease: async () => ({ tag_name: 'v1.0.0', assets: [] }),
    };

    const code = await runCli(['node', 'bin/pouse.js', 'update'], {
      logger: mockLogger,
      adapter: mockAdapter,
      releaseService: mockReleaseService,
    });

    assert.equal(code, 0);
    assert.equal(installedCalled, false);
    assert.ok(logs.some((l) => l.includes('already up-to-date')));
  });

  test('runCli uninstall invokes adapter uninstall', async () => {
    const logs = [];
    const mockLogger = {
      info: (msg) => logs.push(msg),
      error: () => {},
      warn: () => {},
      debug: () => {},
      success: (msg) => logs.push(`OK: ${msg}`),
    };

    let uninstallCalled = false;
    const mockAdapter = {
      name: 'win32',
      detectInstalled: async () => ({ installed: true, version: '1.0.0' }),
      uninstall: async () => { uninstallCalled = true; },
    };

    const code = await runCli(['node', 'bin/pouse.js', 'uninstall'], {
      logger: mockLogger,
      adapter: mockAdapter,
    });

    assert.equal(code, 0);
    assert.equal(uninstallCalled, true);
    assert.ok(logs.some((l) => l.includes('has been uninstalled')));
  });

  test('runCli returns 1 on unsupported platform', async () => {
    const logs = [];
    const mockLogger = {
      info: () => {},
      error: (msg) => logs.push(msg),
      warn: () => {},
      debug: () => {},
      success: () => {},
    };

    const code = await runCli(['node', 'bin/pouse.js', 'install'], {
      logger: mockLogger,
      platform: 'linux',
    });

    assert.equal(code, 1);
    assert.ok(logs.some((l) => l.includes('Windows only')));
  });
});