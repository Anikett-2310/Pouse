import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { ReleaseService } from '../src/core/release-service.js';
import { createTempDir, cleanupTempDir } from '../src/core/security.js';
import { ReleaseNotFoundError, AssetNotFoundError, ChecksumError } from '../src/core/errors.js';

describe('ReleaseService', () => {
  const sampleInstallerContent = 'Sample Inno Setup Installer Executable Binary';
  const sampleInstallerHash = crypto.createHash('sha256').update(sampleInstallerContent).digest('hex');

  const mockRelease = {
    tag_name: 'v1.0.0',
    name: 'Pouse 1.0.0',
    assets: [
      {
        name: 'Pouse-Setup-v1.0.0.exe',
        browser_download_url: 'https://github.com/mock/Pouse-Setup-v1.0.0.exe',
        size: sampleInstallerContent.length,
      },
      {
        name: 'Pouse-Setup-v1.0.0.exe.sha256',
        browser_download_url: 'https://github.com/mock/Pouse-Setup-v1.0.0.exe.sha256',
        size: 70,
      },
    ],
  };

  test('getRelease fetches latest release metadata', async () => {
    const mockFetch = async (url) => {
      assert.ok(url.includes('/releases/latest'));
      return {
        ok: true,
        status: 200,
        json: async () => mockRelease,
      };
    };

    const service = new ReleaseService({ fetchFn: mockFetch });
    const release = await service.getRelease('latest');
    assert.equal(release.tag_name, 'v1.0.0');
  });

  test('getRelease fetches tag release metadata', async () => {
    const mockFetch = async (url) => {
      assert.ok(url.includes('/releases/tags/v1.0.0'));
      return {
        ok: true,
        status: 200,
        json: async () => mockRelease,
      };
    };

    const service = new ReleaseService({ fetchFn: mockFetch });
    const release = await service.getRelease('1.0.0');
    assert.equal(release.tag_name, 'v1.0.0');
  });

  test('getRelease throws ReleaseNotFoundError on 404', async () => {
    const mockFetch = async () => ({
      ok: false,
      status: 404,
      statusText: 'Not Found',
    });

    const service = new ReleaseService({ fetchFn: mockFetch });
    await assert.rejects(
      async () => await service.getRelease('v9.9.9'),
      (err) => err instanceof ReleaseNotFoundError
    );
  });

  test('getRelease handles GitHub rate limits gracefully', async () => {
    const mockFetch = async () => ({
      ok: false,
      status: 403,
      statusText: 'Forbidden',
      headers: new Headers({ 'x-ratelimit-remaining': '0' }),
    });

    const service = new ReleaseService({ fetchFn: mockFetch });
    await assert.rejects(
      async () => await service.getRelease('latest'),
      (err) => err instanceof ReleaseNotFoundError && err.message.includes('rate limit')
    );
  });

  test('findWindowsAssets finds installer and companion checksum', () => {
    const service = new ReleaseService();
    const { installerAsset, checksumAsset } = service.findWindowsAssets(mockRelease);
    assert.equal(installerAsset.name, 'Pouse-Setup-v1.0.0.exe');
    assert.equal(checksumAsset.name, 'Pouse-Setup-v1.0.0.exe.sha256');
  });

  test('findWindowsAssets throws AssetNotFoundError if installer is missing', () => {
    const service = new ReleaseService();
    assert.throws(
      () => service.findWindowsAssets({ tag_name: 'v1.0.0', assets: [] }),
      (err) => err instanceof AssetNotFoundError
    );
  });

  test('downloadAndVerifyInstaller verifies checksum successfully', async () => {
    const tempDir = createTempDir();
    const mockFetch = async (url) => {
      if (url.endsWith('.exe')) {
        return {
          ok: true,
          status: 200,
          body: new ReadableStream({
            start(controller) {
              controller.enqueue(new TextEncoder().encode(sampleInstallerContent));
              controller.close();
            },
          }),
        };
      }
      if (url.endsWith('.sha256')) {
        return {
          ok: true,
          status: 200,
          text: async () => `${sampleInstallerHash}  Pouse-Setup-v1.0.0.exe\n`,
        };
      }
      throw new Error(`Unexpected URL: ${url}`);
    };

    const service = new ReleaseService({ fetchFn: mockFetch });
    const result = await service.downloadAndVerifyInstaller(mockRelease, tempDir);

    assert.equal(result.version, 'v1.0.0');
    assert.equal(result.checksumVerified, true);
    assert.ok(fs.existsSync(result.installerPath));

    cleanupTempDir(tempDir);
  });

  test('downloadAndVerifyInstaller rejects mismatched checksum', async () => {
    const tempDir = createTempDir();
    const mockFetch = async (url) => {
      if (url.endsWith('.exe')) {
        return {
          ok: true,
          status: 200,
          body: new ReadableStream({
            start(controller) {
              controller.enqueue(new TextEncoder().encode(sampleInstallerContent));
              controller.close();
            },
          }),
        };
      }
      if (url.endsWith('.sha256')) {
        return {
          ok: true,
          status: 200,
          text: async () => `ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff  Pouse-Setup-v1.0.0.exe\n`,
        };
      }
      throw new Error(`Unexpected URL: ${url}`);
    };

    const service = new ReleaseService({ fetchFn: mockFetch });
    await assert.rejects(
      async () => await service.downloadAndVerifyInstaller(mockRelease, tempDir),
      (err) => err instanceof ChecksumError
    );

    cleanupTempDir(tempDir);
  });

  test('downloadAndVerifyInstaller throws if companion checksum missing and unsafe override not specified', async () => {
    const tempDir = createTempDir();
    const releaseWithoutChecksum = {
      tag_name: 'v1.0.0',
      assets: [
        {
          name: 'Pouse-Setup-v1.0.0.exe',
          browser_download_url: 'https://github.com/mock/Pouse-Setup-v1.0.0.exe',
          size: sampleInstallerContent.length,
        },
      ],
    };

    const mockFetch = async () => ({
      ok: true,
      status: 200,
      body: new ReadableStream({
        start(controller) {
          controller.enqueue(new TextEncoder().encode(sampleInstallerContent));
          controller.close();
        },
      }),
    });

    const service = new ReleaseService({ fetchFn: mockFetch });

    // Without unsafe flag: should throw ChecksumError
    await assert.rejects(
      async () => await service.downloadAndVerifyInstaller(releaseWithoutChecksum, tempDir, { unsafeNoChecksum: false }),
      (err) => err instanceof ChecksumError && err.message.includes('Companion checksum file')
    );

    // With unsafe flag: should proceed with warning
    let warned = false;
    const mockLogger = {
      info: () => {},
      debug: () => {},
      warn: (msg) => { warned = true; },
      success: () => {},
    };

    const result = await service.downloadAndVerifyInstaller(releaseWithoutChecksum, tempDir, {
      unsafeNoChecksum: true,
      logger: mockLogger,
    });

    assert.equal(result.checksumVerified, false);
    assert.equal(warned, true);

    cleanupTempDir(tempDir);
  });
});
