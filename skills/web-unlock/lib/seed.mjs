#!/usr/bin/env node
// web-unlock: create your own settings folder on first run. Never overwrites or changes a file that exists.
//
// Run by the plugin's SessionStart hook (quiet: no output, always exit 0, so a session never waits on it)
// and by `bin/user-config.sh` (`--init` passes --verbose: one line per file, exit 1 if the folder cannot be
// made). The folder is the one lib/config.sh reads: $WEB_UNLOCK_HOME, else ~/.config/web-unlock.
//   sites.json   copy of the bundled registry (skipped when WEB_UNLOCK_SITES, from the environment or the
//                env file, points elsewhere)
//   env          copy of env.default: every setting commented out, so behavior is the same as no file
//   references/  empty folder for your own reference notes
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { home, envFile, setting } from './envfile.mjs';

const SKILL = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const verbose = process.argv.includes('--verbose');
const say = s => { if (verbose) process.stdout.write(s + '\n'); };
// home, envFile: the same folder and env file as lib/config.sh (see envfile.mjs).

// Copy src to dst only if nothing is at dst (O_EXCL: a file, folder or symlink there is left alone).
function seedFile(src, dst, mode) {
  let fd, written = false;
  // A relative path would land in whatever folder the session runs in: never seed one.
  if (!path.isAbsolute(dst)) { if (verbose) process.stderr.write(`seed: ${dst} is not an absolute path, not created\n`); return false; }
  try {
    const data = fs.readFileSync(src);
    fs.mkdirSync(path.dirname(dst), { recursive: true });  // a file in the way throws: a failure, not "kept"
    try { fd = fs.openSync(dst, 'wx', mode); } catch (e) {
      if (e && e.code === 'EEXIST') { say(`kept ${dst}`); return true; }
      throw e;
    }
    for (let off = 0; off < data.length;) off += fs.writeSync(fd, data, off);
    written = true;
    say(`seeded ${dst}`);
  } catch (e) {
    if (verbose) process.stderr.write(`seed: could not create ${dst}: ${e && e.message}\n`);
    return false;
  } finally {
    if (fd !== undefined) {
      try { fs.closeSync(fd); } catch { /* nothing to do */ }
      // A failed write (disk full, ...) must not leave an empty or cut-off file that later runs keep.
      if (!written) try { fs.unlinkSync(dst); } catch { /* nothing to do */ }
    }
  }
  return true;
}

let ok = path.isAbsolute(home);
if (!ok && verbose) process.stderr.write(`seed: WEB_UNLOCK_HOME ${home} is not an absolute path, not created\n`);
if (ok) try {
  fs.mkdirSync(path.join(home, 'references'), { recursive: true });
} catch (e) {
  if (verbose) process.stderr.write(`seed: could not create ${path.join(home, 'references')}: ${e && e.message}\n`);
  ok = false;
}
if (ok) {
  // WEB_UNLOCK_SITES set in the environment or in the env file: your registry lives elsewhere, no copy here
  if (!setting('WEB_UNLOCK_SITES')) ok = seedFile(path.join(SKILL, 'sites.json'), path.join(home, 'sites.json'), 0o644) && ok;
  ok = seedFile(path.join(SKILL, 'env.default'), envFile, 0o600) && ok;
}
process.exitCode = verbose && !ok ? 1 : 0;
