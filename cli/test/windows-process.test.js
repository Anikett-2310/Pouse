import { test, describe } from 'node:test';
import assert from 'node:assert/strict';
import { isPouseRunning, forceKillPouse, ensurePouseClosed, PROCESS_NAME } from '../src/platforms/windows/process.js';
import { ProcessRunningError } from '../src/core/errors.js';

describe('Windows Process Module', () => {
  test('isPouseRunning detects running pc-client.exe', async () => {
    const mockExec = async () => ({
      stdout: `"pc-client.exe","12345","Console","1","45,210 K"\r\n`,
      stderr: '',
    });

    const running = await isPouseRunning({ exec: mockExec });
    assert.equal(running, true);
  });

  test('isPouseRunning returns false when pc-client.exe is not in tasklist', async () => {
    const mockExec = async () => ({
      stdout: `INFO: No tasks are running which match the specified criteria.\r\n`,
      stderr: '',
    });

    const running = await isPouseRunning({ exec: mockExec });
    assert.equal(running, false);
  });

  test('forceKillPouse invokes taskkill with /F and /IM pc-client.exe', async () => {
    let calledCmd = '';
    let calledArgs = [];

    const mockExec = async (cmd, args) => {
      calledCmd = cmd;
      calledArgs = args;
      return { stdout: 'SUCCESS', stderr: '' };
    };

    await forceKillPouse({ exec: mockExec });
    assert.equal(calledCmd, 'taskkill.exe');
    assert.deepEqual(calledArgs, ['/F', '/IM', PROCESS_NAME]);
  });

  test('ensurePouseClosed succeeds when process is not running', async () => {
    const mockExec = async () => ({ stdout: 'INFO: No tasks', stderr: '' });
    await ensurePouseClosed({ exec: mockExec });
  });

  test('ensurePouseClosed with force terminates running process', async () => {
    let killed = false;
    const mockExec = async (cmd, args) => {
      if (cmd === 'tasklist.exe') {
        return { stdout: killed ? 'INFO: No tasks' : '"pc-client.exe","1234"', stderr: '' };
      }
      if (cmd === 'taskkill.exe') {
        killed = true;
        return { stdout: 'SUCCESS', stderr: '' };
      }
      return { stdout: '', stderr: '' };
    };

    await ensurePouseClosed({ force: true, exec: mockExec });
    assert.equal(killed, true);
  });

  test('ensurePouseClosed in silent mode without force throws ProcessRunningError', async () => {
    const mockExec = async () => ({ stdout: '"pc-client.exe","1234"', stderr: '' });

    await assert.rejects(
      async () => await ensurePouseClosed({ silent: true, force: false, exec: mockExec }),
      (err) => err instanceof ProcessRunningError && err.message.includes('system tray')
    );
  });

  test('ensurePouseClosed in interactive mode prompts user and succeeds after close', async () => {
    let checkCount = 0;
    const mockExec = async () => {
      checkCount++;
      // First check: running. Second check (after prompt): closed.
      if (checkCount === 1) {
        return { stdout: '"pc-client.exe","1234"', stderr: '' };
      }
      return { stdout: 'INFO: No tasks', stderr: '' };
    };

    let promptCalled = false;
    const mockPrompt = async () => {
      promptCalled = true;
    };

    await ensurePouseClosed({ silent: false, force: false, exec: mockExec, promptFn: mockPrompt });
    assert.equal(promptCalled, true);
  });
});
