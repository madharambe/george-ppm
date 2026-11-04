#!/usr/bin/env python3
"""ci_lint.py - catch CI mistakes locally, before paying for a macOS run.

Two things it checks, both of which would otherwise only surface 20 minutes into
a GitHub Actions run:

  1. bash -n on every "run:" block in .github/workflows/ios.yml
  2. the simulator-picking pipeline, fed canned "xcrun simctl list devices"
     output for several runner images

Run: python tools/ci_lint.py
"""
import os
import re
import subprocess
import sys

import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))
WF = os.path.join(REPO, ".github", "workflows", "ios.yml")
SCRATCH = os.environ.get("CI_LINT_DIR", os.path.join(os.environ.get("TEMP", "."), "ci-lint"))

BASH_CANDIDATES = [
    r"C:\Program Files\Git\bin\bash.exe",
    r"C:\Program Files\Git\usr\bin\bash.exe",
    r"C:\msys64\usr\bin\bash.exe",
    "/bin/bash",
    "/usr/bin/bash",
]

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("  PASS  " if cond else "  FAIL  ") + name + ("  " + detail if detail else ""))


def find_bash():
    for b in BASH_CANDIDATES:
        if os.path.exists(b):
            return b
    return None


def main():
    if not os.path.exists(WF):
        print("workflow not found:", WF)
        return 1
    bash = find_bash()
    os.makedirs(SCRATCH, exist_ok=True)

    wf = yaml.safe_load(open(WF, encoding="utf-8"))
    steps = wf["jobs"]["build"]["steps"]

    print("=" * 66)
    print("1. bash -n on every run: block")
    print("=" * 66)
    if not bash:
        check("bash available", False, "no bash found - skipping syntax check")
    else:
        for i, step in enumerate(steps):
            script = step.get("run")
            if not script:
                continue
            name = step.get("name", "step %d" % i)
            path = os.path.join(SCRATCH, "step_%02d.sh" % i)
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(script)
            r = subprocess.run([bash, "-n", path], capture_output=True, text=True)
            check("%-40s" % name[:40], r.returncode == 0,
                  "" if r.returncode == 0 else r.stderr.strip().splitlines()[0][:100])

    print()
    print("=" * 66)
    print("2. simulator-picking pipeline")
    print("=" * 66)
    picker = next((s["run"] for s in steps if "SIM_NAME" in (s.get("run") or "")), None)
    if not picker or not bash:
        check("picker step found and testable", False)
    else:
        flat = picker.replace("\\\n", " ")
        m = re.search(r"NAME=\$\((.*?)\)\s*\n", flat + "\n", re.S)
        cmd_template = " ".join(m.group(1).split()) if m else ""
        check("picker command extracted", bool(cmd_template), cmd_template[:70])

        samples = {
            "iOS 17.5 runner": ("-- iOS 17.5 --\n    iPhone 15 (A) (Shutdown)\n"
                                "    iPhone 15 Pro (B) (Shutdown)\n    iPad Pro (C) (Booted)", "iPhone"),
            "iOS 16.4 runner": ("-- iOS 16.4 --\n    iPhone 14 (D) (Shutdown)\n"
                                "    iPhone 14 Pro Max (E) (Shutdown)", "iPhone"),
            "iOS 26.0 runner": ("-- iOS 26.0 --\n    iPhone 17 (G) (Shutdown)\n"
                                "    iPhone 17 Pro Max (H) (Shutdown)", "iPhone"),
            "no iPhones": ("-- iOS 17.0 --\n    iPad Air (F) (Shutdown)", ""),
        }
        for label, (sample, expect_prefix) in samples.items():
            path = os.path.join(SCRATCH, "sample.txt")
            with open(path, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(sample + "\n")
            cmd = cmd_template.replace("xcrun simctl list devices available",
                                       "cat '%s'" % path.replace("\\", "/"))
            r = subprocess.run([bash, "-c", cmd], capture_output=True, text=True)
            got = r.stdout.strip()
            if expect_prefix:
                check("%-16s picks an iPhone" % label, got.startswith(expect_prefix), got or "(nothing)")
            else:
                check("%-16s returns empty (workflow then fails loudly)" % label, got == "", got or "(empty)")

    print()
    print("=" * 66)
    print("RESULT: %d passed, %d failed" % (len(PASS), len(FAIL)))
    if FAIL:
        print("failed:", ", ".join(FAIL))
    print("=" * 66)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
