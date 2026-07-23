"""Golden-test runner against a live LangOS instance."""

from __future__ import annotations

import json
from pathlib import Path

from langos_sdk import LangOSClient


def run_golden(path: Path, base_url: str = "http://127.0.0.1:9473") -> int:
    client = LangOSClient(base_url)
    failures = 0

    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        case = json.loads(line)
        resp = client.understand(case["input"])
        unit = resp["ir"]["units"][0]
        expected = case["expected"]

        if unit["predicate"] != expected["predicate"]:
            failures += 1
            print(f"FAIL predicate: {unit['predicate']!r} != {expected['predicate']!r}")
            continue

        for exp, act in zip(expected["arguments"], unit["arguments"], strict=False):
            label = act.get("label") or act.get("value")
            if exp["role"] != act["role"] or exp["label"] != label:
                failures += 1
                print(f"FAIL arguments: expected {exp}, got {act}")

    return failures
