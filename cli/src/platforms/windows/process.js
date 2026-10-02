import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import readline from 'node:readline';
import { ProcessRunningError } from '../../core/errors.js';

const execFileAsync = promisify(execFile);

export const PROCESS_NAME = 'pc-client.exe';

/**
 * Checks whether pc-client.exe is currently running.
 * @param {Object} [options]
 * @param {Function} [options.exec]
 * @returns {Promise<boolean>}
 */
export async function isPouseRunning({ exec = execFileAsync } = {}) {
  try {
    const { stdout } = await exec('tasklist.exe', [
      '/FI', `IMAGENAME eq ${PROCESS_NAME}`,
      '/FO', 'CSV',
      '/NH',
    ]);
    return stdout.toLowerCase().includes(PROCESS_NAME.toLowerCase());
  } catch {
    return false;
  }
}

/**
 * Forcibly terminates the Pouse process using taskkill.
 * Only invoked when --force is explicitly provided.
 * @param {Object} [options]
 * @param {Function} [options.exec]
 * @returns {Promise<void>}
 */
export async function forceKillPouse({ exec = execFileAsync } = {}) {
  try {
    await exec('taskkill.exe', ['/F', '/IM', PROCESS_NAME]);
  } catch {
    // Process might have exited already
  }
}

/**
 * Handles running process before update or uninstall.
 * Adheres to the clean tray shutdown policy.
 * @param {Object} options
 * @param {boolean} [options.silent=false]
 * @param {boolean} [options.force=false]
 * @param {Object} [options.logger]
 * @param {Function} [options.exec]
 * @param {Function} [options.promptFn] Optional prompt function for testing.
 * @returns {Promise<void>}
 */
export async function ensurePouseClosed({
  silent = false,
  force = false,
  logger,
  exec = execFileAsync,
  promptFn,
} = {}) {
  const running = await isPouseRunning({ exec });
  if (!running) {
    return;
  }

  if (force) {
    logger?.warn(`Terminating running '${PROCESS_NAME}' process due to --force flag.`);
    await forceKillPouse({ exec });
    return;
  }

  // If in silent / non-interactive mode without force, we cannot prompt the user
  if (silent) {
    throw new ProcessRunningError(
      `Pouse desktop client (${PROCESS_NAME}) is currently running.\n` +
      `Please close Pouse cleanly via the system tray before running update or uninstall (or use --force to terminate).`
    );
  }

  // Interactive mode: Prompt the user to close Pouse cleanly via the tray
  logger?.warn(
    `Pouse desktop client is currently running!\n` +
    `To ensure Bluetooth discoverability is cleanly restored and state is saved,\n` +
    `please right-click the Pouse icon in the Windows system tray and select 'Quit Pouse'.`
  );

  if (promptFn) {
    await promptFn();
  } else {
    await new Promise((resolve) => {
      const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout,
      });
      rl.question('Press Enter after closing Pouse to continue (or Ctrl+C to cancel)...', () => {
        rl.close();
        resolve();
      });
    });
  }

  // Check again after user confirmation
  const stillRunning = await isPouseRunning({ exec });
  if (stillRunning) {
    throw new ProcessRunningError(
      `Pouse is still running. Please exit Pouse via the system tray and try again, or pass --force.`
    );
  }
}
