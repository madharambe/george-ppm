#!/usr/bin/env python3
"""app_parity_check.py - iOS and Android must render telemetry identically.

Two clients read the same JSON frame. If they format it differently, the same
reading shows two different numbers depending on which app you open - a silent
inconsistency no single-app test can catch.

This compares the formatting rules statically:
  - decimal values use the same format specifier
  - integers are rendered the same way
  - the "sensor absent" sentinel is the same string
  - unit suffixes match

Run: python tools/app_parity_check.py
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, ".."))

SWIFT_FMT = os.path.join(REPO, "ios", "GeorgePPM", "TelemetryFormatter.swift")
SWIFT_DASH = os.path.join(REPO, "ios", "GeorgePPM", "Dashboard.swift")
KOTLIN = os.path.join(REPO, "android", "app", "src", "main", "java", "com",
                      "georgeppm", "monitor", "MainActivity.kt")
KOTLIN_MODEL = os.path.join(REPO, "android", "app", "src", "main", "java", "com",
                            "georgeppm", "monitor", "Telemetry.kt")
# Labels and units live in the layouts, not the formatters - comparing the
# formatters was the first version of this check and it produced four false
# failures. Read where the strings actually are.
SWIFT_VIEW = os.path.join(REPO, "ios", "GeorgePPM", "ContentView.swift")
ANDROID_STRINGS = os.path.join(REPO, "android", "app", "src", "main", "res", "values", "strings.xml")
ANDROID_LAYOUT = os.path.join(REPO, "android", "app", "src", "main", "res", "layout", "activity_main.xml")

PASS, FAIL = [], []


def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("  PASS  " if cond else "  FAIL  ") + name + ("  " + detail if detail else ""))


def read(p):
    with open(p, encoding="utf-8") as fh:
        return fh.read()


def main():
    for p in (SWIFT_FMT, SWIFT_DASH, KOTLIN, KOTLIN_MODEL):
        if not os.path.exists(p):
            print("missing:", p)
            return 2

    swift = read(SWIFT_FMT) + read(SWIFT_DASH)
    kotlin = read(KOTLIN) + read(KOTLIN_MODEL)

    swift_specs = set(re.findall(r'String\(format:\s*"([^"]+)"', swift))
    kotlin_specs = set(re.findall(r'String\.format\(Locale\.US,\s*"([^"]+)"', kotlin))

    print("=" * 66)
    print("1. decimal formatting")
    print("=" * 66)
    print("  swift  specifiers:", sorted(swift_specs))
    print("  kotlin specifiers:", sorted(kotlin_specs))
    check("both use %.2f for decimals", "%.2f" in swift_specs and "%.2f" in kotlin_specs)
    check("neither uses a different decimal precision",
          not any(s in ("%.1f", "%.3f") for s in swift_specs | kotlin_specs))

    print()
    print("=" * 66)
    print("2. missing-sensor sentinel")
    print("=" * 66)
    swift_dash = re.findall(r'return\s+"([^"]+)"\s*\n?\s*\}', swift)
    check('swift uses "--" for absent values', '"--"' in swift)
    check('kotlin uses "--" for absent values', '"--"' in kotlin)
    # make sure neither side silently falls back to a zero
    check("swift does not render 0 for nil",
          not re.search(r'guard let v = value else \{ return "0', swift))
    check("kotlin does not render 0 for null",
          not re.search(r'if \(t\.(amps|battery) != null\)[^}]*else \{?\s*"0', kotlin))

    print()
    print("=" * 66)
    print("3. integer rendering")
    print("=" * 66)
    check("swift renders Int with String(value)", "String(value)" in swift)
    check("kotlin renders Int with %d or toString",
          ("%d" in kotlin_specs) or ("toString()" in kotlin) or ("String(t.rpm)" in kotlin))

    print()
    print("=" * 66)
    print("4. labels and units shown to the user")
    print("=" * 66)
    swift_view = read(SWIFT_VIEW)
    android_ui = read(ANDROID_STRINGS) + read(ANDROID_LAYOUT)

    # every literal string the iOS view renders, plus every Android string/label
    swift_literals = set(re.findall(r'Text\("([^"]+)"\)', swift_view))
    swift_literals |= set(re.findall(r'label:\s*"([^"]+)"', swift_view))
    swift_literals |= set(re.findall(r'unit:\s*"([^"]+)"', swift_view))
    android_literals = set(re.findall(r'android:text="([^"]+)"', android_ui))
    android_literals |= set(re.findall(r'<string name="[^"]+">([^<]+)</string>', android_ui))

    swift_lc = {s.lower() for s in swift_literals}
    android_lc = {s.lower() for s in android_literals}

    for token in ("Debit", "Total", "RPM", "Arus", "Baterai", "L/min", "rev/min"):
        in_swift = token.lower() in swift_lc
        in_android = token.lower() in android_lc
        check("%-8s shown by both clients" % token, in_swift and in_android,
              "" if (in_swift and in_android) else ("swift=%s android=%s" % (in_swift, in_android)))
    check("uptime suffix is seconds in both", '" s"' in swift and '" s"' in kotlin)
    check("rssi suffix is dBm in both", '" dBm"' in swift and '" dBm"' in kotlin)

    print()
    print("=" * 66)
    print("5. nullability contract")
    print("=" * 66)
    check("swift models amps as optional", "let a: Double?" in read(SWIFT_FMT).replace("\n", " ") or "Double?" in swift)
    check("kotlin models amps as nullable", "amps: Double?" in kotlin)
    check("swift models battery as optional", "Double?" in swift)
    check("kotlin models battery as nullable", "battery: Double?" in kotlin)

    print()
    print("=" * 66)
    print("RESULT: %d passed, %d failed" % (len(PASS), len(FAIL)))
    if FAIL:
        print("failed:", ", ".join(FAIL))
    print("=" * 66)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
