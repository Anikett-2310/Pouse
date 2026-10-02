import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Logger } from './core/logger.js';
import { createTempDir, cleanupTempDir } from './core/security.js';
import { ReleaseService } from './core/release-service.js';
import { getPlatformAdapter } from './platforms/index.js';
import { PouseError } from './core/errors.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const pkg = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'package.json'), 'utf8'));

/**
 * Parses raw command-line arguments into structured command and options.
 * @param {string[]} argv
 * @returns {{ command: string, options: { silent: boolean, verbose: boolean, release: string|null, force: boolean, unsafeNoChecksum: boolean, help: boolean, version: boolean } }}
 */
export function parseArgs(argv) {
  const args = argv.slice(2);
  let command = '';
  const options = {
    silent: false,
    verbose: false,
    release: null,
    force: false,
    unsafeNoChecksum: false,
    help: false,
    version: false,
  };

  for (let i = 0; i < args.length; i++) {
    const arg = args[i];

    if (arg === '--help' || arg === '-h' || arg === 'help') {
      options.help = true;
    } else if (arg === '--version' || arg === '-v' || arg === 'version') {
      options.version = true;
    } else if (arg === '--silent' || arg === '-s') {
      options.silent = true;
    } else if (arg === '--verbose') {
      options.verbose = true;
    } else if (arg === '--force' || arg === '-f') {
      options.force = true;
    } else if (arg === '--unsafe-no-checksum') {
      options.unsafeNoChecksum = true;
    } else if (arg === '--release' || arg === '-r') {
      if (i + 1 < args.length && !args[i + 1].startsWith('-')) {
        options.release = args[++i];
      } else {
        throw new PouseError(`Option '${arg}' requires a version argument (e.g. --release v1.0.0)`);
      }
    } else if (arg.startsWith('--release=')) {
      options.release = arg.split('=')[1];
    } else if (!arg.startsWith('-') && !command) {
      command = arg.toLowerCase();
    } else {
      throw new PouseError(`Unknown option or argument: '${arg}'`);
    }
  }

  return { command, options };
}

/**
 * Returns formatted help text.
 * @returns {string}
 */
export function getHelpText() {
  return `
Pouse CLI - Official installer & management tool for Pouse desktop client (v${pkg.version})

USAGE:
  pouse <command> [options]

COMMANDS:
  install        Download, verify, and install the Pouse desktop client.
  update         Check for and install updates for Pouse desktop client.
  uninstall      Remove Pouse desktop client from this system.
  --version, -v  Display Pouse CLI and installed desktop client versions.
  --help, -h     Display this help documentation.

OPTIONS:
  -s, --silent              Run silently without interactive prompts or GUI installer dialogs.
  --verbose                 Display detailed diagnostic and network logs.
  -f, --force               Force action (reinstall if already installed, or terminate running app).
  -r, --release <version>   Target specific GitHub release version (e.g. 1.0.0 or v1.0.0). Defaults to latest.
  --unsafe-no-checksum      [UNSAFE] Bypass mandatory companion SHA-256 checksum verification.
                            WARNING: This is an unsafe development/testing override.

TARGET PLATFORMS:
  Windows: Fully supported (Windows 10/11 x64).
  macOS / Linux: Planned for future desktop releases.
  Android: Available via the official Pouse download page.
  iOS: Future Apple distribution; not a CLI installation target.

EXAMPLES:
  pouse install
  pouse install --release v1.0.0
  pouse update
  pouse uninstall --silent
`;
}

/**
 * Executes the 'install' command.
 */
export async function handleInstall(options, { adapter, releaseService, logger }) {
  logger.info('Checking current Pouse desktop installation...');
  const current = await adapter.detectInstalled();

  if (current.installed && !options.force) {
    logger.warn(
      `Pouse desktop client is already installed (version: ${current.version || 'unknown'}).\n` +
      `       To update to the latest release, run: pouse update\n` +
      `       To reinstall anyway, run: pouse install --force`
    );
    return;
  }

  // Ensure any running instance is closed cleanly
  await adapter.ensureProcessClosed({
    silent: options.silent,
    force: options.force,
    logger,
  });

  const targetTag = options.release || 'latest';
  logger.info(`Fetching release metadata for '${targetTag}' from GitHub...`);
  const release = await releaseService.getRelease(targetTag);

  const tempDir = createTempDir();
  logger.debug(`Created temporary workspace: ${tempDir}`);

  try {
    const { installerPath, version } = await releaseService.downloadAndVerifyInstaller(
      release,
      tempDir,
      {
        unsafeNoChecksum: options.unsafeNoChecksum,
        logger,
      }
    );

    logger.info(`Starting installation of Pouse ${version}...`);
    await adapter.install(installerPath, {
      silent: options.silent,
      verbose: options.verbose,
      logger,
    });

    logger.success(`Pouse ${version} has been successfully installed on this system!`);
  } finally {
    logger.debug(`Cleaning up temporary workspace: ${tempDir}`);
    cleanupTempDir(tempDir);
  }
}

/**
 * Executes the 'update' command.
 */
export async function handleUpdate(options, { adapter, releaseService, logger }) {
  logger.info('Checking current Pouse desktop installation...');
  const current = await adapter.detectInstalled();

  if (!current.installed && !options.force) {
    logger.warn(`Pouse is not currently installed. Proceeding with installation instead.`);
    return await handleInstall(options, { adapter, releaseService, logger });
  }

  const targetTag = options.release || 'latest';
  logger.info(`Fetching release metadata for '${targetTag}' from GitHub...`);
  const release = await releaseService.getRelease(targetTag);
  const targetVersion = release.tag_name ? release.tag_name.replace(/^v/, '') : '';

  if (current.version && targetVersion && current.version === targetVersion && !options.force) {
    logger.info(`Pouse desktop client is already up-to-date (version ${current.version}).`);
    logger.info(`To force re-installation of this version, pass --force.`);
    return;
  }

  // Ensure running process is closed cleanly
  await adapter.ensureProcessClosed({
    silent: options.silent,
    force: options.force,
    logger,
  });

  const tempDir = createTempDir();
  logger.debug(`Created temporary workspace: ${tempDir}`);

  try {
    const { installerPath, version } = await releaseService.downloadAndVerifyInstaller(
      release,
      tempDir,
      {
        unsafeNoChecksum: options.unsafeNoChecksum,
        logger,
      }
    );

    logger.info(`Applying update to Pouse ${version}...`);
    await adapter.install(installerPath, {
      silent: options.silent,
      verbose: options.verbose,
      logger,
    });

    logger.success(`Pouse desktop client has been successfully updated to ${version}!`);
  } finally {
    logger.debug(`Cleaning up temporary workspace: ${tempDir}`);
    cleanupTempDir(tempDir);
  }
}

/**
 * Executes the 'uninstall' command.
 */
export async function handleUninstall(options, { adapter, logger }) {
  logger.info('Checking current Pouse desktop installation...');
  const current = await adapter.detectInstalled();

  if (!current.installed) {
    logger.info('Pouse desktop client is not currently installed on this system.');
    return;
  }

  logger.info(`Initiating uninstallation of Pouse (version: ${current.version || 'unknown'})...`);
  await adapter.uninstall({
    silent: options.silent,
    verbose: options.verbose,
    force: options.force,
    logger,
  });

  logger.success('Pouse desktop client has been uninstalled from this system.');
}

/**
 * Displays version information.
 */
export async function handleVersion({ adapter, logger }) {
  logger.info(`pouse-cli v${pkg.version} (Node.js ${process.version})`);
  try {
    const installed = await adapter.detectInstalled();
    if (installed.installed) {
      logger.info(`Pouse Desktop: v${installed.version || 'unknown'} (installed at: ${installed.installPath || 'unknown'})`);
    } else {
      logger.info(`Pouse Desktop: Not installed`);
    }
  } catch {
    logger.info(`Pouse Desktop: Status unavailable for this platform`);
  }
}

/**
 * Main CLI execution entrypoint.
 * @param {string[]} [argv=process.argv]
 * @param {Object} [deps] Injected dependencies for testing.
 * @returns {Promise<number>} Exit code (0 for success, 1 for error).
 */
export async function runCli(argv = process.argv, deps = {}) {
  let options;
  let command;

  try {
    const parsed = parseArgs(argv);
    command = parsed.command;
    options = parsed.options;
  } catch (err) {
    console.error(`[ERROR] ${err.message}`);
    console.log(getHelpText());
    return 1;
  }

  const logger = deps.logger || new Logger({ silent: options.silent, verbose: options.verbose });

  if (options.help || command === 'help') {
    logger.info(getHelpText());
    return 0;
  }

  let adapter;
  try {
    adapter = deps.adapter || getPlatformAdapter(deps.platform || process.platform);
  } catch (err) {
    logger.error(err.message);
    return 1;
  }

  if (options.version || command === 'version') {
    await handleVersion({ adapter, logger });
    return 0;
  }

  const releaseService = deps.releaseService || new ReleaseService();

  try {
    switch (command) {
      case 'install':
        await handleInstall(options, { adapter, releaseService, logger });
        break;
      case 'update':
        await handleUpdate(options, { adapter, releaseService, logger });
        break;
      case 'uninstall':
        await handleUninstall(options, { adapter, logger });
        break;
      case '':
        logger.info(getHelpText());
        break;
      default:
        logger.error(`Unknown command: '${command}'. See 'pouse --help' for valid commands.`);
        return 1;
    }
    return 0;
  } catch (err) {
    if (err instanceof PouseError) {
      logger.error(err.message);
    } else {
      logger.error(`An unexpected error occurred: ${err.message}`);
      if (options.verbose) {
        console.error(err.stack);
      }
    }
    return 1;
  }
}
