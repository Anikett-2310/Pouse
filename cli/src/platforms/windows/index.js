import { spawn } from 'node:child_process';
import { PlatformAdapter } from '../platform-adapter.js';
import { queryPouseRegistry } from './registry.js';
import { isPouseRunning, ensurePouseClosed } from './process.js';
import { InstallationError, PouseError } from '../../core/errors.js';

export class WindowsAdapter extends PlatformAdapter {
  constructor({ exec, spawnFn } = {}) {
    super('win32');
    this._customExec = exec;
    this._customSpawn = spawnFn || spawn;
  }

  /**
   * @returns {Promise<{ installed: boolean, version: string|null, installPath: string|null, uninstallString: string|null, quietUninstallString: string|null, keyPath: string|null }>}
   */
  async detectInstalled() {
    return await queryPouseRegistry({ exec: this._customExec });
  }

  /**
   * @returns {Promise<boolean>}
   */
  async isProcessRunning() {
    return await isPouseRunning({ exec: this._customExec });
  }

  /**
   * @param {Object} options
   */
  async ensureProcessClosed(options) {
    return await ensurePouseClosed({
      ...options,
      exec: this._customExec,
    });
  }

  /**
   * Runs the Inno Setup installer.
   * @param {string} installerPath
   * @param {Object} [options]
   * @param {boolean} [options.silent=false]
   * @param {boolean} [options.verbose=false]
   * @param {Object} [options.logger]
   */
  async install(installerPath, { silent = false, verbose = false, logger } = {}) {
    const args = [];
    if (silent) {
      args.push('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART');
    }

    logger?.info(`Launching installer: ${installerPath} ${args.join(' ')}`);

    return new Promise((resolve, reject) => {
      const child = this._customSpawn(installerPath, args, {
        stdio: silent ? 'ignore' : 'inherit',
        windowsHide: silent,
      });

      child.on('error', (err) => {
        reject(new InstallationError(`Failed to execute installer '${installerPath}': ${err.message}`));
      });

      child.on('close', (code) => {
        if (code === 0) {
          resolve();
        } else {
          reject(new InstallationError(`Installer exited with non-zero exit code: ${code}`, code));
        }
      });
    });
  }

  /**
   * Runs the Inno Setup uninstaller.
   * @param {Object} [options]
   * @param {boolean} [options.silent=false]
   * @param {boolean} [options.verbose=false]
   * @param {boolean} [options.force=false]
   * @param {Object} [options.logger]
   */
  async uninstall({ silent = false, verbose = false, force = false, logger } = {}) {
    const installed = await this.detectInstalled();
    if (!installed.installed) {
      logger?.warn('Pouse does not appear to be installed on this system.');
      return;
    }

    // Ensure Pouse is not running before uninstalling
    await this.ensureProcessClosed({ silent, force, logger });

    // Determine uninstaller executable and args
    const rawString = (silent && installed.quietUninstallString)
      ? installed.quietUninstallString
      : (installed.uninstallString || '');

    if (!rawString) {
      throw new PouseError('Could not find uninstaller string in Windows registry.');
    }

    let command;
    let args = [];

    // Parse quoted or unquoted path
    if (rawString.startsWith('"')) {
      const closingQuote = rawString.indexOf('"', 1);
      if (closingQuote !== -1) {
        command = rawString.slice(1, closingQuote);
        const remaining = rawString.slice(closingQuote + 1).trim();
        if (remaining) {
          args = remaining.split(/\s+/);
        }
      } else {
        command = rawString.replace(/"/g, '');
      }
    } else {
      const parts = rawString.split(/\s+/);
      command = parts[0];
      args = parts.slice(1);
    }

    if (silent) {
      if (!args.includes('/VERYSILENT')) args.push('/VERYSILENT');
      if (!args.includes('/SUPPRESSMSGBOXES')) args.push('/SUPPRESSMSGBOXES');
      if (!args.includes('/NORESTART')) args.push('/NORESTART');
    }

    logger?.info(`Launching uninstaller: ${command} ${args.join(' ')}`);

    return new Promise((resolve, reject) => {
      const child = this._customSpawn(command, args, {
        stdio: silent ? 'ignore' : 'inherit',
        windowsHide: silent,
      });

      child.on('error', (err) => {
        reject(new InstallationError(`Failed to execute uninstaller '${command}': ${err.message}`));
      });

      child.on('close', (code) => {
        if (code === 0) {
          resolve();
        } else {
          reject(new InstallationError(`Uninstaller exited with non-zero exit code: ${code}`, code));
        }
      });
    });
  }
}
