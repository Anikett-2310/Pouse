/**
 * Base abstract platform adapter for Pouse CLI.
 */
export class PlatformAdapter {
  constructor(name) {
    this.name = name;
  }

  /**
   * Detects whether Pouse desktop is installed and retrieves installation details.
   * @returns {Promise<{ installed: boolean, version: string|null, installPath: string|null, uninstallString: string|null, quietUninstallString: string|null }>}
   */
  async detectInstalled() {
    throw new Error('detectInstalled() must be implemented by platform adapter.');
  }

  /**
   * Checks whether the Pouse desktop process is currently running.
   * @returns {Promise<boolean>}
   */
  async isProcessRunning() {
    throw new Error('isProcessRunning() must be implemented by platform adapter.');
  }

  /**
   * Ensures the running Pouse process is terminated before update/uninstall.
   * Adheres to clean tray shutdown policy unless force is true.
   * @param {Object} options
   * @param {boolean} [options.silent=false]
   * @param {boolean} [options.force=false]
   * @param {Object} [options.logger]
   * @returns {Promise<void>}
   */
  async ensureProcessClosed(options) {
    throw new Error('ensureProcessClosed() must be implemented by platform adapter.');
  }

  /**
   * Runs the installer.
   * @param {string} installerPath
   * @param {Object} options
   * @param {boolean} [options.silent=false]
   * @param {boolean} [options.verbose=false]
   * @param {Object} [options.logger]
   * @returns {Promise<void>}
   */
  async install(installerPath, options) {
    throw new Error('install() must be implemented by platform adapter.');
  }

  /**
   * Runs the uninstaller.
   * @param {Object} options
   * @param {boolean} [options.silent=false]
   * @param {boolean} [options.verbose=false]
   * @param {boolean} [options.force=false]
   * @param {Object} [options.logger]
   * @returns {Promise<void>}
   */
  async uninstall(options) {
    throw new Error('uninstall() must be implemented by platform adapter.');
  }
}
