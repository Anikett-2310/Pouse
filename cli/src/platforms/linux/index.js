import { PlatformAdapter } from '../platform-adapter.js';
import { PlatformNotSupportedError } from '../../core/errors.js';

export class LinuxAdapter extends PlatformAdapter {
  constructor() {
    super('linux');
  }

  async detectInstalled() {
    throw new PlatformNotSupportedError('linux');
  }

  async isProcessRunning() {
    throw new PlatformNotSupportedError('linux');
  }

  async ensureProcessClosed() {
    throw new PlatformNotSupportedError('linux');
  }

  async install() {
    throw new PlatformNotSupportedError('linux');
  }

  async uninstall() {
    throw new PlatformNotSupportedError('linux');
  }
}
