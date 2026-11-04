#!/usr/bin/env python3
"""download.py - robust ranged-chunk downloader for this machine.

Why this exists: PowerShell's Invoke-WebRequest and curl.exe both fail HTTPS here
(schannel SEC_E_NO_CREDENTIALS), and the link stalls on large single streams.
Python's OpenSSL works, and ranged chunks with resume + retries survive the stalls.

Usage:
    python tools/download.py <url> <dest> [--chunk-mb 8] [--retries 6]
"""
import argparse
import os
import sys
import time

import requests

# Accept-Encoding: identity is REQUIRED. dl.google.com serves the SDK zip with
# Content-Encoding: gzip; a byte-range of a gzip stream is not itself a valid
# gzip stream, so urllib3 raised ContentDecodingError on every resume attempt.
UA = {"User-Agent": "Mozilla/5.0", "Accept-Encoding": "identity"}


def human(n):
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return "%.1f %s" % (n, unit)
        n /= 1024.0
    return "%.1f TB" % n


def remote_size(url):
    """Total size, or 0 if the server will not say.

    HEAD alone is not reliable: dl.google.com answers HEAD without a
    Content-Length, which silently turned 'unknown size' into 'stream ended =
    finished' and produced a truncated 11.5 MB zip out of a 133 MB one. The
    ranged-GET fallback reads the real total out of Content-Range.
    """
    try:
        r = requests.head(url, timeout=30, allow_redirects=True, headers=UA)
        n = int(r.headers.get("Content-Length", 0))
        if n:
            return n
    except Exception:
        pass
    try:
        r = requests.get(url, timeout=30, stream=True, headers=dict(UA, **{"Range": "bytes=0-0"}))
        cr = r.headers.get("Content-Range", "")
        r.close()
        # e.g. "bytes 0-0/133278404"
        if "/" in cr:
            tail = cr.rsplit("/", 1)[1].strip()
            if tail.isdigit():
                return int(tail)
    except Exception:
        pass
    return 0


def download(url, dest, chunk_mb=8, retries=6, expect_size=0):
    os.makedirs(os.path.dirname(os.path.abspath(dest)) or ".", exist_ok=True)
    total = expect_size or remote_size(url)
    if not total:
        print("REFUSING: server reported no size and no --expect-size given.")
        print("A truncated stream would be indistinguishable from success.")
        return False
    chunk = chunk_mb * 1024 * 1024
    have = os.path.getsize(dest) if os.path.exists(dest) else 0

    if total and have >= total:
        print("already complete: %s (%s)" % (dest, human(have)))
        return True

    print("url    : %s" % url)
    print("dest   : %s" % dest)
    print("size   : %s" % (human(total) if total else "unknown"))
    print("resume : %s" % (human(have) if have else "0 B"))

    started = time.time()
    fails = 0
    last_report = 0

    while True:
        if total and have >= total:
            break
        end = (have + chunk - 1) if total else None
        if total and end is not None and end > total - 1:
            end = total - 1
        headers = dict(UA)
        headers["Range"] = "bytes=%d-%s" % (have, end if end is not None else "")
        try:
            r = requests.get(url, headers=headers, timeout=(15, 60), stream=True)
            if r.status_code not in (200, 206):
                raise RuntimeError("HTTP %s" % r.status_code)
            mode = "ab" if (have and r.status_code == 206) else "wb"
            if mode == "wb":
                have = 0
            with open(dest, mode) as fh:
                for piece in r.iter_content(65536):
                    if piece:
                        fh.write(piece)
                        have += len(piece)
            fails = 0
        except Exception as e:
            fails += 1
            print("  chunk failed (%s): %s" % (type(e).__name__, str(e)[:90]))
            if fails >= retries:
                print("TOO MANY FAILURES")
                return False
            time.sleep(1.5)
            continue

        now = time.time()
        if now - last_report > 5 or (total and have >= total):
            last_report = now
            rate = have / max(0.001, now - started) / 1024.0
            pct = ("%.0f%%" % (have * 100.0 / total)) if total else "?"
            print("  %s / %s  (%s)  %.0f KB/s" % (
                human(have), human(total) if total else "?", pct, rate))

        if have >= total:
            break

    if have < total:
        print("INCOMPLETE: %s of %s" % (human(have), human(total)))
        return False
    print("done: %s (%s in %.0f s)" % (dest, human(have), time.time() - started))
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("dest")
    ap.add_argument("--chunk-mb", type=int, default=8)
    ap.add_argument("--retries", type=int, default=6)
    ap.add_argument("--expect-size", type=int, default=0,
                    help="known byte count; used when the server hides Content-Length")
    a = ap.parse_args()
    ok = download(a.url, a.dest, a.chunk_mb, a.retries, a.expect_size)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
