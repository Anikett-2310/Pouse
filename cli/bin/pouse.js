#!/usr/bin/env node

/**
 * Pouse CLI executable entrypoint.
 * Requires Node.js >= 22.0.0.
 */

const [major] = process.versions.node.split('.').map(Number);
if (major < 22) {
  console.error(`[ERROR] Pouse CLI requires Node.js >=22.0.0. Current version is ${process.version}. Please upgrade your Node.js runtime.`);
  process.exit(1);
}

import { runCli } from '../src/cli.js';

runCli(process.argv)
  .then((exitCode) => {
    process.exitCode = exitCode;
  })
  .catch((err) => {
    console.error(`[FATAL] ${err.message}`);
    process.exitCode = 1;
  });
