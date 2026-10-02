import { PlatformAdapter } from '../platform-adapter.js';
import { PlatformNotSupportedError } from '../../core/errors.js';

export class MacOSAdapter extends PlatformAdapter {
  constructor() {
    super('darwin');
  }

  async detectInstalled() {
    throw new PlatformNotSupportedError('darwin');
  }

  async isProcessRunning() {
    throw new PlatformNotSupportedError('darwin');
  }

  async ensureProcessClosed() {
    throw new PlatformNotSupportedError('darwin');
  }

  async install() {
    throw new PlatformNotSupportedError('darwin');
  }

  async uninstall() {
    throw new PlatformNotSupportedError('darwin');
  }
}
