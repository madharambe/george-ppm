#!/usr/bin/env python3
"""xcodegen_spec_check.py - validate ios/project.yml against XcodeGen's own docs.

XcodeGen cannot be built on this machine (its dependency checkouts need symlink
support, which requires Developer Mode or elevation), so the spec is validated
against ProjectSpec.md from the XcodeGen source instead - the same document the
tool itself is written from.

Run: python tools/xcodegen_spec_check.py
"""
import os
import re
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))
SPEC = os.path.join(REPO, "ios", "project.yml")
DOC_CANDIDATES = [
    r"D:\Android\xcodegen\XcodeGen-2.46.0\Docs\ProjectSpec.md",
    os.path.join(HERE, "xcodegen-ProjectSpec.md"),
]

BT = chr(96)   # backtick, used by the docs for inline code spans

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("  PASS  " if cond else "  FAIL  ") + name + ("  " + detail if detail else ""))


def find_doc():
    for p in DOC_CANDIDATES:
        if os.path.exists(p):
            return p
    return None


# Keys whose names are chosen by the user, not by XcodeGen.
USER_DEFINED = {"GeorgePPM", "GeorgePPMTests", "com.georgeppm.monitor"}


def collect_keys(node, path=()):
    out = []
    if isinstance(node, dict):
        for k, v in node.items():
            out.append((path + (str(k),), v))
            out.extend(collect_keys(v, path + (str(k),)))
    elif isinstance(node, list):
        for item in node:
            out.extend(collect_keys(item, path))
    return out


def main():
    doc_path = find_doc()
    if not doc_path:
        print("ProjectSpec.md not found - cannot validate")
        for p in DOC_CANDIDATES:
            print("  looked in: " + p)
        return 2

    doc = open(doc_path, encoding="utf-8").read()
    spec = yaml.safe_load(open(SPEC, encoding="utf-8"))
    print("spec : " + SPEC)
    print("docs : " + doc_path)
    print()

    print("=" * 66)
    print("1. every structural key is documented by XcodeGen")
    print("=" * 66)
    checked = set()
    for path, value in collect_keys(spec):
        key = path[-1]
        if key in USER_DEFINED or key in checked:
            continue
        if len(path) >= 2 and path[-2] == "properties":
            continue                      # Info.plist keys belong to Apple
        if "settings" in path and key.isupper():
            continue                      # build settings are free-form
        if isinstance(value, dict):
            continue                      # containers verified via children
        checked.add(key)
        # XcodeGen documents options as "- [ ] **key**: **Type** - description",
        # so bold is the primary form; headings/tables/backticks are also used.
        patterns = [
            r"\*\*" + re.escape(key) + r"\*\*",
            r"(?m)^#{1,4}\s+" + re.escape(key) + r"\b",
            r"\|\s*" + re.escape(key) + r"\s*\|",
            BT + re.escape(key) + BT,
        ]
        documented = any(re.search(p, doc) for p in patterns)
        check("%-24s documented" % key, documented)

    print()
    print("=" * 66)
    print("2. target types are valid")
    print("=" * 66)
    VALID_TYPES = {"application", "bundle.unit-test", "framework", "staticLibrary",
                   "dynamicLibrary", "bundle", "app-extension", "tool", "commandLineTool"}
    for name, tgt in spec.get("targets", {}).items():
        t = tgt.get("type", "")
        check("%-18s type '%s' is valid" % (name, t), t in VALID_TYPES)

    print()
    print("=" * 66)
    print("3. platform and deployment target")
    print("=" * 66)
    for name, tgt in spec.get("targets", {}).items():
        check("%-18s platform is iOS" % name, tgt.get("platform") == "iOS")
    dt = spec.get("options", {}).get("deploymentTarget", {})
    check("deploymentTarget declares iOS", "iOS" in dt, str(dt))

    print()
    print("=" * 66)
    print("4. scheme references resolve")
    print("=" * 66)
    targets = set(spec.get("targets", {}).keys())
    for sname, scheme in spec.get("schemes", {}).items():
        build_targets = (scheme.get("build") or {}).get("targets") or {}
        for t in build_targets:
            check("scheme %s build target %s exists" % (sname, t), t in targets)
        for t in (scheme.get("test") or {}).get("targets") or []:
            check("scheme %s test target %s exists" % (sname, t), t in targets)

    print()
    print("=" * 66)
    print("RESULT: %d passed, %d failed" % (len(PASS), len(FAIL)))
    if FAIL:
        print("failed:", ", ".join(FAIL))
    print("=" * 66)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
