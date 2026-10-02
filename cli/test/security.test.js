import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import {
  createTempDir,
  cleanupTempDir,
  computeFileSha256,
  parseChecksum,
  verifySha256,
} from '../src/core/security.js';
import { ChecksumError } from '../src/core/errors.js';

describe('Security & Checksum Module', () => {
  test('createTempDir creates a unique temporary directory', () => {
    const dir = createTempDir();
    assert.ok(fs.existsSync(dir), 'Temp dir should exist');
    assert.ok(path.basename(dir).startsWith('pouse-cli-'), 'Dir name should start with pouse-cli-');
    cleanupTempDir(dir);
    assert.ok(!fs.existsSync(dir), 'Temp dir should be deleted by cleanup');
  });

  test('computeFileSha256 correctly calculates SHA-256 hash', async () => {
    const tempDir = createTempDir();
    const testFile = path.join(tempDir, 'test.bin');
    const content = Buffer.from('Pouse Desktop Client Test Payload 12345');
    fs.writeFileSync(testFile, content);

    const expectedHash = crypto.createHash('sha256').update(content).digest('hex').toLowerCase();
    const actualHash = await computeFileSha256(testFile);

    assert.equal(actualHash, expectedHash);
    cleanupTempDir(tempDir);
  });

  test('parseChecksum parses various format checksum strings', () => {
    const sampleHash = '5baa43f7b90f451a19ba1d1e54edb763a66337d64e7b25dc627340d1dad6b70d';

    // GNU format: hash  filename
    assert.equal(
      parseChecksum(`${sampleHash}  Pouse-Setup-v1.0.0.exe`),
      sampleHash
    );

    // GNU binary format: hash *filename
    assert.equal(
      parseChecksum(`${sampleHash} *Pouse-Setup-v1.0.0.exe`),
      sampleHash
    );

    // BSD format: SHA256 (filename) = hash
    assert.equal(
      parseChecksum(`SHA256 (Pouse-Setup-v1.0.0.exe) = ${sampleHash.toUpperCase()}`),
      sampleHash
    );

    // Raw hex string
    assert.equal(
      parseChecksum(sampleHash),
      sampleHash
    );

    // Multi-line with comments
    const multiLine = `# Checksum file\n\n${sampleHash}  Pouse-Setup-v1.0.0.exe\n`;
    assert.equal(parseChecksum(multiLine), sampleHash);
  });

  test('parseChecksum throws ChecksumError on invalid content', () => {
    assert.throws(
      () => parseChecksum('invalid content'),
      (err) => err instanceof ChecksumError
    );
    assert.throws(
      () => parseChecksum(''),
      (err) => err instanceof ChecksumError
    );
  });

  test('verifySha256 passes for matching hash', async () => {
    const tempDir = createTempDir();
    const testFile = path.join(tempDir, 'valid.bin');
    fs.writeFileSync(testFile, 'Clean binary payload');
    const hash = crypto.createHash('sha256').update('Clean binary payload').digest('hex');

    const result = await verifySha256(testFile, hash);
    assert.equal(result, hash.toLowerCase());
    assert.ok(fs.existsSync(testFile), 'File should still exist');
    cleanupTempDir(tempDir);
  });

  test('verifySha256 fails and unlinks file for mismatched hash', async () => {
    const tempDir = createTempDir();
    const testFile = path.join(tempDir, 'tampered.bin');
    fs.writeFileSync(testFile, 'Tampered binary payload');
    const fakeHash = '0000000000000000000000000000000000000000000000000000000000000000';

    await assert.rejects(
      async () => {
        await verifySha256(testFile, fakeHash);
      },
      (err) => err instanceof ChecksumError && err.message.includes('SHA-256 checksum mismatch')
    );

    assert.ok(!fs.existsSync(testFile), 'Tampered file should be deleted on checksum failure');
    cleanupTempDir(tempDir);
  });
});
