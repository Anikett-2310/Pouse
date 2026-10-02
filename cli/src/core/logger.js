/**
 * Simple zero-dependency logger for Pouse CLI.
 */
export class Logger {
  /**
   * @param {{ silent?: boolean, verbose?: boolean }} options
   */
  constructor({ silent = false, verbose = false } = {}) {
    this.silent = silent;
    this.verbose = verbose;
  }

  /**
   * Print standard info message (unless silent).
   * @param {string} msg
   */
  info(msg) {
    if (!this.silent) {
      console.log(msg);
    }
  }

  /**
   * Print success message (unless silent).
   * @param {string} msg
   */
  success(msg) {
    if (!this.silent) {
      console.log(`[OK] ${msg}`);
    }
  }

  /**
   * Print warning message (always visible unless silent).
   * @param {string} msg
   */
  warn(msg) {
    if (!this.silent) {
      console.warn(`[WARN] ${msg}`);
    }
  }

  /**
   * Print error message (always visible).
   * @param {string} msg
   */
  error(msg) {
    console.error(`[ERROR] ${msg}`);
  }

  /**
   * Print debug message (only when verbose is true).
   * @param {string} msg
   */
  debug(msg) {
    if (this.verbose) {
      console.log(`[DEBUG] ${msg}`);
    }
  }
}

export const defaultLogger = new Logger();
