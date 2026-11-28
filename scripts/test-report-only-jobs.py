#!/usr/bin/env python3
"""Proves a report-only job in ci.yml cannot end red: no step of a job whose name says "report only" exits nonzero,
because continue-on-error keeps the run green but leaves the job's own check red.

    python3 -I scripts/test-report-only-jobs.py
"""
import os
import re
import sys

here = os.path.dirname(os.path.abspath(__file__))
text = open(os.path.join(here, "..", ".github", "workflows", "ci.yml")).read()
jobs = re.split(r"\n(?=  [A-Za-z0-9_-]+:\n)", text.split("\njobs:\n", 1)[1])
found = []
failures = []
for job in jobs:
    name = re.search(r"^    name: (.*)$", job, re.M)
    if not name or "report only" not in name.group(1):
        continue
    found.append(name.group(1))
    for number, line in enumerate(job.splitlines(), 1):
        if re.search(r"\bexit\s+[1-9]\b|\|\|\s*false\b", line.split("#", 1)[0]):
            failures.append(f"{name.group(1)}: line {number} of the job exits nonzero: {line.strip()}")
if not found:
    failures.append('no job says "report only": the check has nothing to read')
if failures:
    print("\n".join(failures))
    sys.exit(1)
print(f"{len(found)} report-only job(s) never exit nonzero")
