import { execFile } from 'node:child_process';
import { join, dirname } from 'node:path';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

export default function apply(ctx) {
  // Only launch on macOS
  if (process.platform !== 'darwin') return;

  const bin = join(__dirname, '..', 'bin', 'dsh-desktop');
  if (!existsSync(bin)) {
    ctx.logger?.warn?.('[deepseek-harness-mac] binary not found at %s', bin);
    return;
  }

  // Check if the shell is already running (port 3080)
  const port = process.env.DSH_PORT || 3080;
  ctx.logger?.info?.('[deepseek-harness-mac] launching native macOS shell on :%d', port);

  const child = execFile(bin, [], {
    env: { ...process.env, DSH_PORT: String(port) },
    stdio: 'ignore',
  });

  child.unref();

  child.on('error', (err) => {
    ctx.logger?.error?.('[deepseek-harness-mac] failed to launch: %s', err.message);
  });

  // Dispose: kill the shell when DSH shuts down
  ctx.on('dispose', () => {
    if (child.exitCode === null) {
      child.kill();
    }
  });
}
