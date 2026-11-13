# Changelog

All notable changes to this plugin. Versions follow `.claude-plugin/plugin.json`.

## 0.3.8 (2026-11-13)

- Skill schema and score: version and tags in the frontmatter, third-person description, Purpose, Prerequisites, Limitations and Troubleshooting sections; skill score badge.

## 0.3.7 (2026-11-13)

- Add author metadata, Instructions and Examples sections to SKILL.md.

## 0.3.6 (2026-11-12)

- Fix invalid YAML in the SKILL.md frontmatter.

## 0.3.5 (2026-11-12)

- Audit fixes, round 2.

## 0.3.4 (2026-11-11)

- Maintenance: point to the catalog repo's new name, lucas-tools.

## 0.3.3 (2026-11-11)

- Maintenance: rename the marketplace to lucas-tools.

## 0.3.2 (2026-11-11)

- `chrome-real.sh`: the process lookup no longer matches itself.

## 0.3.1 (2026-11-09)

- Docs: one-line description, catalog install, one Settings section.

## 0.3.0 (2026-11-09)

- The detector catches the Cloudflare verification page through r.jina.ai; `oc` is the first L1 reader.

## 0.2.1 (2026-11-08)

- The detector works under a parent `package.json` with type commonjs.

## 0.2.0 (2026-11-08)

- A user folder for rules, references, registry and settings that survive updates, created on first run.
- Detector: Mercado Livre's Portuguese error wall; review fixes for env precedence, symlinks and relative paths.

## 0.1.0 (2026-11-08)

- First release: a skill for blocked web pages, with fetch, search, detector and real-Chrome scripts.
