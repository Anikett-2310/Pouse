/**
 * Base custom error class for Pouse CLI.
 */
export class PouseError extends Error {
  /**
   * @param {string} message
   * @param {string} [code]
   */
  constructor(message, code = 'POUSE_ERROR') {
    super(message);
    this.name = 'PouseError';
    this.code = code;
  }
}

/**
 * Thrown when the current operating system or architecture is not supported.
 */
export class PlatformNotSupportedError extends PouseError {
  constructor(platform) {
    super(
      `Pouse desktop client is currently supported on Windows only.\n` +
      `Platform '${platform}' is not yet supported. Linux and macOS desktop clients are planned for future releases.\n` +
      `Android: Available via the official Pouse download page.\n` +
      `iOS: Future Apple distribution; not a CLI installation target.`,
      'PLATFORM_NOT_SUPPORTED'
    );
    this.name = 'PlatformNotSupportedError';
  }
}

/**
 * Thrown when a GitHub release cannot be found or accessed.
 */
export class ReleaseNotFoundError extends PouseError {
  constructor(releaseTag, details = '') {
    const detailMsg = details ? ` (${details})` : '';
    super(
      `Release '${releaseTag}' was not found on GitHub repository 'Anikett-2310/Pouse'${detailMsg}.`,
      'RELEASE_NOT_FOUND'
    );
    this.name = 'ReleaseNotFoundError';
  }
}

/**
 * Thrown when an expected asset is missing from a GitHub release.
 */
export class AssetNotFoundError extends PouseError {
  constructor(assetPattern, releaseTag) {
    super(
      `Could not find expected release asset '${assetPattern}' in GitHub release '${releaseTag}'.`,
      'ASSET_NOT_FOUND'
    );
    this.name = 'AssetNotFoundError';
  }
}

/**
 * Thrown when checksum verification fails or companion checksum is missing.
 */
export class ChecksumError extends PouseError {
  constructor(message) {
    super(message, 'CHECKSUM_ERROR');
    this.name = 'ChecksumError';
  }
}

/**
 * Thrown when Pouse process is running and must be closed cleanly before proceeding.
 */
export class ProcessRunningError extends PouseError {
  constructor(message = 'Pouse desktop client is currently running. Please close Pouse cleanly via the system tray before proceeding.') {
    super(message, 'PROCESS_RUNNING');
    this.name = 'ProcessRunningError';
  }
}

/**
 * Thrown when installer or uninstaller fails execution.
 */
export class InstallationError extends PouseError {
  constructor(message, exitCode) {
    super(message, 'INSTALLATION_ERROR');
    this.name = 'InstallationError';
    this.exitCode = exitCode;
  }
}
