// web-unlock: the settings folder and env file for the node scripts (seed.mjs, cdp.mjs), the same ones
// lib/config.sh uses: $WEB_UNLOCK_HOME, else $HOME/.config/web-unlock; the env file is $WEB_UNLOCK_ENV, else
// <folder>/env. A variable already set in the environment wins over the file.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const env = n => (process.env[n] || '').trim();
const HOME = env('HOME') || os.homedir();

export const home = env('WEB_UNLOCK_HOME') || path.join(HOME, '.config', 'web-unlock');
export const envFile = env('WEB_UNLOCK_ENV') || path.join(home, 'env');

// The value of KEY: the environment first, then the last `KEY=...` (or `export KEY=...`) line of the env file.
// Covers what the file is meant to hold: plain, "double" or 'single' quoted values, $HOME / ${HOME} and a
// leading ~. Anything fancier needs the shell; set it in the environment instead.
export function setting(key) {
  if (env(key)) return env(key);
  let text;
  try { text = fs.readFileSync(envFile, 'utf8'); } catch { return ''; }
  let value = '';
  const re = new RegExp(`^[ \\t]*(?:export[ \\t]+)?${key}=(.*)$`);
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(re);
    if (!m) continue;
    let v = m[1].trim();
    const q = v[0];
    if ((q === '"' || q === "'") && v.indexOf(q, 1) > 0) v = v.slice(1, v.indexOf(q, 1));
    else v = v.replace(/[ \t]+#.*$/, '');
    if (q !== "'") v = v.replace(/\$\{HOME\}|\$HOME(?![A-Za-z0-9_])/g, HOME);
    if (v === '~' || v.startsWith('~/')) v = HOME + v.slice(1);
    value = v;
  }
  return value;
}
