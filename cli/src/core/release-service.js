import fs from 'node:fs';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { Readable } from 'node:stream';
import { ReleaseNotFoundError, AssetNotFoundError, ChecksumError } from './errors.js';
import { parseChecksum, verifySha256 } from './security.js';

export const DEFAULT_REPO = 'Anikett-2310/Pouse';

/**
 * Service for interacting with GitHub Releases.
 */
export class ReleaseService {
  /**
   * @param {Object} [options]
   * @param {string} [options.repo]
   * @param {string} [options.apiBase]
   * @param {string} [options.token]
   * @param {typeof fetch} [options.fetchFn]
   */
  constructor({
    repo = process.env.POUSE_GITHUB_REPO || DEFAULT_REPO,
    apiBase = process.env.POUSE_GITHUB_API_BASE || 'https://api.github.com',
    token = process.env.GITHUB_TOKEN || process.env.GH_TOKEN,
    fetchFn = globalThis.fetch,
  } = {}) {
    this.repo = repo;
    this.apiBase = apiBase.replace(/\/$/, '');
    this.token = token;
    this.fetchFn = fetchFn;
  }

  /**
   * Builds request headers for GitHub API requests.
   * @private
   */
  _getHeaders() {
    const headers = {
      'User-Agent': 'pouse-cli/1.0.0',
      'Accept': 'application/vnd.github.v3+json',
    };
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`;
    }
    return headers;
  }

  /**
   * Retrieves release metadata from GitHub.
   * @param {string} [versionTag='latest']
   * @returns {Promise<Object>}
   */
  async getRelease(versionTag = 'latest') {
    let url;
    if (!versionTag || versionTag.toLowerCase() === 'latest') {
      url = `${this.apiBase}/repos/${this.repo}/releases/latest`;
    } else {
      const tag = versionTag.startsWith('v') ? versionTag : `v${versionTag}`;
      url = `${this.apiBase}/repos/${this.repo}/releases/tags/${tag}`;
    }

    const res = await this.fetchFn(url, { headers: this._getHeaders() });

    if (res.status === 404) {
      // If tag had 'v' prefixed, try without 'v' just in case
      if (versionTag && versionTag !== 'latest' && versionTag.startsWith('v')) {
        const fallbackTag = versionTag.slice(1);
        const fallbackUrl = `${this.apiBase}/repos/${this.repo}/releases/tags/${fallbackTag}`;
        const fallbackRes = await this.fetchFn(fallbackUrl, { headers: this._getHeaders() });
        if (fallbackRes.ok) {
          return await fallbackRes.json();
        }
      }
      throw new ReleaseNotFoundError(versionTag);
    }

    if (res.status === 403) {
      const rateLimitRemaining = res.headers.get('x-ratelimit-remaining');
      if (rateLimitRemaining === '0') {
        throw new ReleaseNotFoundError(
          versionTag,
          'GitHub API rate limit exceeded. Set GITHUB_TOKEN environment variable to increase limit.'
        );
      }
    }

    if (!res.ok) {
      throw new ReleaseNotFoundError(
        versionTag,
        `GitHub API returned status ${res.status} ${res.statusText}`
      );
    }

    return await res.json();
  }

  /**
   * Identifies the Windows installer asset and companion .sha256 checksum asset in a release.
   * @param {Object} release
   * @returns {{ installerAsset: Object, checksumAsset: Object|null }}
   */
  findWindowsAssets(release) {
    if (!release || !Array.isArray(release.assets)) {
      throw new AssetNotFoundError('Pouse-Setup-*.exe', release?.tag_name || 'unknown');
    }

    const installerAsset = release.assets.find(
      (a) => /^Pouse-Setup-.*\.exe$/i.test(a.name) || (a.name.startsWith('Pouse-Setup') && a.name.endsWith('.exe'))
    );

    if (!installerAsset) {
      throw new AssetNotFoundError('Pouse-Setup-*.exe', release.tag_name);
    }

    const expectedChecksumName = `${installerAsset.name}.sha256`;
    const checksumAsset = release.assets.find(
      (a) => a.name.toLowerCase() === expectedChecksumName.toLowerCase() ||
             a.name.toLowerCase() === `${installerAsset.name}.sha256`.toLowerCase() ||
             /^Pouse-Setup-.*\.exe\.sha256$/i.test(a.name)
    ) || null;

    return { installerAsset, checksumAsset };
  }

  /**
   * Downloads a remote file to a local destination.
   * @param {string} downloadUrl
   * @param {string} destinationPath
   * @param {Object} [logger]
   */
  async downloadFile(downloadUrl, destinationPath, logger) {
    logger?.debug(`Downloading ${downloadUrl} to ${destinationPath}`);
    const res = await this.fetchFn(downloadUrl, {
      headers: {
        'User-Agent': 'pouse-cli/1.0.0',
        'Accept': 'application/octet-stream',
      },
    });

    if (!res.ok) {
      throw new Error(`Failed to download file: HTTP ${res.status} ${res.statusText}`);
    }

    if (!res.body) {
      throw new Error('Response body is empty.');
    }

    const fileStream = fs.createWriteStream(destinationPath);
    // Convert Web ReadableStream to Node.js Readable
    const nodeStream = Readable.fromWeb(res.body);
    await pipeline(nodeStream, fileStream);
  }

  /**
   * Fetches text content of a checksum file.
   * @param {string} downloadUrl
   * @returns {Promise<string>}
   */
  async fetchChecksumContent(downloadUrl) {
    const res = await this.fetchFn(downloadUrl, {
      headers: {
        'User-Agent': 'pouse-cli/1.0.0',
        'Accept': 'text/plain, application/octet-stream',
      },
    });

    if (!res.ok) {
      throw new ChecksumError(`Failed to fetch checksum file from ${downloadUrl}: HTTP ${res.status}`);
    }

    return await res.text();
  }

  /**
   * Downloads the installer and verifies its companion SHA-256 checksum.
   * @param {Object} release
   * @param {string} tempDir
   * @param {Object} [options]
   * @param {boolean} [options.unsafeNoChecksum=false]
   * @param {Object} [options.logger]
   * @returns {Promise<{ installerPath: string, version: string, assetName: string, checksumVerified: boolean }>}
   */
  async downloadAndVerifyInstaller(release, tempDir, { unsafeNoChecksum = false, logger } = {}) {
    const { installerAsset, checksumAsset } = this.findWindowsAssets(release);
    const installerPath = path.join(tempDir, installerAsset.name);

    logger?.info(`Found release ${release.tag_name}: ${installerAsset.name} (${(installerAsset.size / (1024 * 1024)).toFixed(2)} MB)`);

    // Download installer binary
    logger?.info(`Downloading ${installerAsset.name}...`);
    await this.downloadFile(installerAsset.browser_download_url, installerPath, logger);

    let checksumVerified = false;

    if (checksumAsset) {
      logger?.info(`Fetching companion checksum (${checksumAsset.name})...`);
      const checksumText = await this.fetchChecksumContent(checksumAsset.browser_download_url);
      const expectedHash = parseChecksum(checksumText);

      logger?.info(`Verifying SHA-256 checksum...`);
      await verifySha256(installerPath, expectedHash, installerAsset.name);
      logger?.success(`Checksum verified: ${expectedHash}`);
      checksumVerified = true;
    } else {
      if (unsafeNoChecksum) {
        logger?.warn(
          `Mandatory checksum verification bypassed via --unsafe-no-checksum.\n` +
          `       This is an unsafe development/testing override. Proceeding without checksum verification.`
        );
      } else {
        // Safe default: delete downloaded file and abort
        try {
          if (fs.existsSync(installerPath)) {
            fs.unlinkSync(installerPath);
          }
        } catch {
          // ignore
        }
        throw new ChecksumError(
          `Mandatory checksum verification failed: Companion checksum file '${installerAsset.name}.sha256' was not found on GitHub release '${release.tag_name}'.\n` +
          `Installation aborted for security.\n` +
          `(To override in development/testing only, pass --unsafe-no-checksum)`
        );
      }
    }

    return {
      installerPath,
      version: release.tag_name,
      assetName: installerAsset.name,
      checksumVerified,
    };
  }
}
