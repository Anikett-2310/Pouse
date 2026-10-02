import { WindowsAdapter } from './windows/index.js';
import { LinuxAdapter } from './linux/index.js';
import { MacOSAdapter } from './macos/index.js';
import { PlatformNotSupportedError } from '../core/errors.js';

/**
 * Returns the appropriate platform adapter for the current or specified OS.
 * @param {string} [platform=process.platform]
 * @param {Object} [adapterOptions]
 * @returns {import('./platform-adapter.js').PlatformAdapter}
 */
export function getPlatformAdapter(platform = process.platform, adapterOptions = {}) {
  switch (platform) {
    case 'win32':
      return new WindowsAdapter(adapterOptions);
    case 'linux':
      return new LinuxAdapter();
    case 'darwin':
      return new MacOSAdapter();
    default:
      throw new PlatformNotSupportedError(platform);
  }
}
