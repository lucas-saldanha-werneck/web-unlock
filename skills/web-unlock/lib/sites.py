#!/usr/bin/env python3
"""web-unlock: the site registry as the skill, fetch.sh and web-unlock-guard read it.

The view is an OVERLAY: the bundled sites.json first, then your registry on top (WEB_UNLOCK_SITES, else
sites.json in your folder). A host in both = your entry, whole (fields are not mixed). So a new plugin version's
bundled hosts reach you, and a full copy of an older bundled file still works: it simply overrides every host it
lists.

Usage: sites.py <bundled> <yours or ""> merged          the merged registry as JSON ({"hosts": {...}})
       sites.py <bundled> <yours or ""> lookup <host>   the entries for a host, its parent domains and *.domain
                                                        (alias_of followed), one JSON line each, with "key"
       sites.py <bundled> <yours or ""> route <host>    "route: how" of the first match with a route (fetch.sh)
       sites.py <bundled> <yours or ""> count           "<yours> <merged>" host counts
A file that is missing or unreadable counts as empty. Keys starting with "_" are notes, not hosts.
"""
import json
import sys


def hosts_of(path):
    if not path:
        return {}
    try:
        with open(path, encoding="utf-8") as f:
            d = json.load(f)
    except Exception:
        return {}
    h = d.get("hosts") if isinstance(d, dict) else None
    return {k: v for k, v in h.items() if not k.startswith("_")} if isinstance(h, dict) else {}


def merged(bundled, yours):
    out = hosts_of(bundled)
    out.update(hosts_of(yours))  # same host: your whole entry wins
    return out


def candidates(host):
    parts = host.lower().split(".")
    keys = []
    for i in range(len(parts) - 1):
        k = ".".join(parts[i:])
        keys.append(k)
        if i > 0:
            keys.append("*." + k)
    return keys


def lookup(hosts, host):
    for k in candidates(host):
        e = hosts.get(k)
        if isinstance(e, dict) and e.get("alias_of"):
            e = hosts.get(e["alias_of"]) or e
        if isinstance(e, dict):
            yield k, e


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    bundled, yours, cmd = argv[0], argv[1], argv[2]
    hosts = merged(bundled, yours)
    if cmd == "merged":
        print(json.dumps({"hosts": hosts}, ensure_ascii=False, indent=1))
    elif cmd == "count":
        print(len(hosts_of(yours)), len(hosts))
    elif cmd in ("lookup", "route") and len(argv) > 3:
        for k, e in lookup(hosts, argv[3]):
            if cmd == "lookup":
                print(json.dumps(dict(e, key=k), ensure_ascii=False))
            elif e.get("route"):
                print("%s: %s" % (e["route"], e.get("how", "")))
                break
    else:
        print(__doc__, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
