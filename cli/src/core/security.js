import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import crypto from 'node:crypto';
import { ChecksumError } from './errors.js';

/**
 * Creates a dedicated, secure temporary directory for Pouse CLI operations.
 * @returns {string} The absolute path to the created temporary directory.
 */
export function createTempDir() {
  const randomSuffix = crypto.randomBytes(8).toString('hex');
  const tempDir = path.join(os.tmpdir(), `pouse-cli-${process.pid}-${randomSuffix}`);
  fs.mkdirSync(tempDir, { recursive: true, mode: 0o700 });
  return tempDir;
}

/**
 * Safely removes a temporary directory and all its contents.
 * @param {string} tempDir
 */
export function cleanupTempDir(tempDir) {
  if (!tempDir || typeof tempDir !== 'string') return;
  try {
    if (fs.existsSync(tempDir)) {
      fs.rmSync(tempDir, { recursive: true, force: true, maxRetries: 3, retryDelay: 100 });
    }
  } catch {
    // Best-effort cleanup
  }
}

/**
 * Computes the SHA-256 hexadecimal digest of a file.
 * @param {string} filePath
 * @returns {Promise<string>}
 */
export function computeFileSha256(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    stream.on('error', (err) => reject(err));
    stream.on('data', (chunk) => hash.update(chunk));
    stream.on('end', () => resolve(hash.digest('hex').toLowerCase()));
  });
}

/**
 * Parses expected SHA-256 hash from checksum file content.
 * Supports:
 * - GNU format: "<hash>  <filename>" or "<hash> *<filename>"
 * - BSD format: "SHA256 (<filename>) = <hash>"
 * - Raw hex string: "<hash>"
 * @param {string} content
 * @returns {string} Expected 64-character lowercase hex hash.
 */
export function parseChecksum(content) {
  if (!content || typeof content !== 'string') {
    throw new ChecksumError('Checksum content is empty or invalid.');
  }

  const lines = content.trim().split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;

    // Match 64-character hex at start or within BSD format
    const bsdMatch = trimmed.match(/SHA256\s*\([^)]+\)\s*=\s*([a-fA-F0-9]{64})/);
    if (bsdMatch) {
      return bsdMatch[1].toLowerCase();
    }

    const gnuMatch = trimmed.match(/^([a-fA-F0-9]{64})(?:\s+[* ]?.+)?$/);
    if (gnuMatch) {
      return gnuMatch[1].toLowerCase();
    }
  }

  throw new ChecksumError(`Could not find a valid 64-character SHA-256 checksum in companion file content.`);
}

/**
 * Verifies that the downloaded file matches the expected SHA-256 checksum.
 * If verification fails, the file is automatically deleted.
 * @param {string} filePath
 * @param {string} expectedHash
 * @param {string} [assetName]
 */
export async function verifySha256(filePath, expectedHash, assetName = path.basename(filePath)) {
  const normalizedExpected = expectedHash.trim().toLowerCase();
  if (normalizedExpected.length !== 64 || !/^[0-9a-f]{64}$/.test(normalizedExpected)) {
    throw new ChecksumError(`Invalid expected SHA-256 checksum format: '${expectedHash}'`);
  }

  const actualHash = await computeFileSha256(filePath);
  if (actualHash !== normalizedExpected) {
    try {
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
      }
    } catch {
      // Best-effort cleanup
    }
    throw new ChecksumError(
      `SHA-256 checksum mismatch for '${assetName}'!\n` +
      `  Expected: ${normalizedExpected}\n` +
      `  Computed: ${actualHash}\n` +
      `The downloaded binary may be corrupted or tampered with. Installation aborted.`
    );
  }

  return actualHash;
}
