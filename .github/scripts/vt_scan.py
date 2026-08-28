#!/usr/bin/env python3
"""Scan release archives with VirusTotal and emit TSV lines of markdown cells.

usage: vt_scan.py FILE [FILE ...]
env:   TOTALVIRUS_API_KEY (required)

stdout: one line per input FILE, in input order:
    <sha256>\\t[<malicious>/<total>](https://www.virustotal.com/gui/file/<sha256>)
    <sha256>\\t                                          (scan failed: empty cell)

Exit status is always 0: a VirusTotal problem must never fail the release
workflow — failures surface as ::warning:: annotations and empty cells.
"""

import hashlib
import os
import sys
import time

import vt

POLL_INTERVAL_SECONDS = 20
POLL_DEADLINE_SECONDS = 600
READ_CHUNK_BYTES = 4 * 1024 * 1024
REPORT_URL = "https://www.virustotal.com/gui/file/{sha}"


def warn(message):
    # GitHub Actions workflow command — must stay a single line. Stderr, so
    # it never lands in the TSV that the caller tees from stdout.
    print(f"::warning::{message.replace(chr(10), ' ')}", file=sys.stderr, flush=True)


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(READ_CHUNK_BYTES), b""):
            digest.update(chunk)
    return digest.hexdigest()


def cell_from_stats(stats, sha):
    """Format [malicious/total](report-url); None when stats carry no engines."""
    total = sum(stats.values())
    if total == 0:
        return None
    return f"[{stats.get('malicious', 0)}/{total}]({REPORT_URL.format(sha=sha)})"


def scan_one(client, path, sha):
    """Scan one file and return its markdown cell, or None for no result.

    Reuses an existing report when one is available (quota-friendly); the
    SHA-256 is always the locally computed one, never read from an API
    response object.
    """
    try:
        stats = client.get_object(f"/files/{sha}").last_analysis_stats
    except vt.APIError as error:
        # NotFoundError means VT has no cached report for this file yet —
        # not a failure; fall through to the upload. Anything else is.
        if error.code != "NotFoundError":
            raise
    except AttributeError:
        # Known to VT but never analyzed — no report to reuse; upload.
        pass
    else:
        return cell_from_stats(stats, sha)

    with open(path, "rb") as fh:
        analysis = client.scan_file(fh)
    deadline = time.monotonic() + POLL_DEADLINE_SECONDS
    while time.monotonic() < deadline:
        # Hand-rolled bounded polling: vt-py's wait_for_analysis_completion
        # sleeps forever on a stuck analysis; this loop cannot.
        time.sleep(POLL_INTERVAL_SECONDS)
        current = client.get_object(f"/analyses/{analysis.id}")
        if current.status == "completed":
            return cell_from_stats(current.stats, sha)
    raise TimeoutError(f"analysis not completed within {POLL_DEADLINE_SECONDS} seconds")


def main(argv):
    files = argv[1:]
    api_key = os.environ.get("TOTALVIRUS_API_KEY", "").strip()

    if not api_key:
        # Checked before any client construction: vt.Client raises ValueError
        # on an empty key.
        warn("TOTALVIRUS_API_KEY is missing or empty — skipping all VirusTotal scans")
        for path in files:
            try:
                sha = sha256_file(path)
            except OSError:
                sha = ""  # unreadable file: an empty sha never matches a table row
            print(f"{sha}\t", flush=True)
        return 0

    client = vt.Client(api_key, agent="slopon-release-ci", timeout=600)
    try:
        for path in files:
            try:
                sha = sha256_file(path)
            except OSError as error:
                warn(f"{path}: cannot read file: {error}")
                print("\t", flush=True)
                continue
            try:
                cell = scan_one(client, path, sha)
            except Exception as error:  # per-file fail-soft: continue scanning
                warn(f"{path}: VirusTotal scan failed: {type(error).__name__}: {error}")
                cell = None
            print(f"{sha}\t{cell or ''}", flush=True)
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
