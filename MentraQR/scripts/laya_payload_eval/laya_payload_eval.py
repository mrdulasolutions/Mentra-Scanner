#!/usr/bin/env python3
"""
Evaluate Laya questions on QR payload fixtures before embedding Core ML.

Usage:
  pip install laya   # optional; uses heuristics-only mode if import fails
  python3 laya_payload_eval.py

Outputs suggested noul threshold and per-fixture results to stdout.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

FIXTURES = Path(__file__).resolve().parent / "fixtures.json"

QUESTIONS = {
    "suspicious": {
        "type": "noul",
        "instructions": "Does this text describe a deceptive or high-risk link or payment request?",
    },
    "kind": {
        "type": "choice",
        "instructions": "What kind of content does this text represent?",
        "criteria": {
            "web": "http or https URLs and web pages",
            "payment": "money transfer, invoice, or wallet links",
            "contact": "email, phone, or address book entries",
            "other": "everything else",
        },
    },
}


def shape_for_laya(payload: str) -> str:
    payload = payload.strip()
    if payload.lower().startswith(("http://", "https://")):
        from urllib.parse import urlparse

        u = urlparse(payload)
        parts = []
        if u.hostname:
            parts.append(u.hostname.lower())
        if u.path and u.path != "/":
            parts.append(u.path[:120])
        if u.query:
            keys = [p.split("=")[0] for p in u.query.split("&")[:8]]
            parts.append("?" + "&".join(keys))
        shaped = " ".join(parts)
        return shaped[:400] if shaped else payload[:200]
    return payload[:400]


def heuristic_suspicious(state: str, full: str) -> float:
    blob = (state + " " + full).lower()
    score = 0.0
    frags = [
        "login",
        "signin",
        "verify",
        "secure",
        "account",
        "wallet",
        "crypto",
        "bit.ly",
        "tinyurl",
        "t.co",
        "password",
        "credential",
        "otp",
        "urgent",
        "invoice",
        "refund",
    ]
    for f in frags:
        if f in blob:
            score += 0.18
    if full.lower().startswith("http://") and not full.lower().startswith("http://localhost"):
        score += 0.12
    if "@" in blob and "http" in blob:
        score += 0.25
    return min(1.0, score)


def main() -> int:
    fixtures = json.loads(FIXTURES.read_text())
    agent = None
    try:
        import laya  # type: ignore

        print("Loading Laya (English checkpoint)...", file=sys.stderr)
        agent = laya.load("convaiinnovations/laya")
        agent.predict({"warmup": "ok"}, {"kind": QUESTIONS["kind"]})
        print("Laya ready.", file=sys.stderr)
    except Exception as exc:
        print(f"Laya not available ({exc}); running heuristic suspicious scores only.", file=sys.stderr)

    suspicious_scores: list[tuple[float, bool]] = []
    kind_hits = 0
    kind_total = 0

    for row in fixtures:
        payload = row["payload"]
        state = shape_for_laya(payload)
        expect_susp = row["expect_suspicious"]
        expect_kind = row.get("expect_kind")

        if agent:
            result = agent.predict(state, QUESTIONS)
            answers = result["answers"]
            noul = answers["suspicious"]["noul"]
            choice = answers["kind"]["choice"]
            kind_total += 1
            if choice == expect_kind:
                kind_hits += 1
        else:
            noul = heuristic_suspicious(state, payload)
            choice = "?"

        suspicious_scores.append((noul, expect_susp))
        flag = "SUSP" if noul >= 0.62 else "ok  "
        print(f"{flag}  noul={noul:.2f}  kind={choice!s:8}  expect_susp={expect_susp}  {payload[:72]}")

    # Threshold sweep for suspicious noul
    best_t, best_f1 = 0.62, 0.0
    for t in [x / 100 for x in range(40, 85, 2)]:
        tp = fp = fn = 0
        for noul, expect in suspicious_scores:
            pred = noul >= t
            if pred and expect:
                tp += 1
            elif pred and not expect:
                fp += 1
            elif not pred and expect:
                fn += 1
        prec = tp / (tp + fp) if (tp + fp) else 0
        rec = tp / (tp + fn) if (tp + fn) else 0
        f1 = 2 * prec * rec / (prec + rec) if (prec + rec) else 0
        if f1 >= best_f1:
            best_f1, best_t = f1, t

    print()
    print(f"Suggested LayaClassificationThresholds.suspiciousNoul ≈ {best_t:.2f} (heuristic/Laya F1={best_f1:.2f} on fixtures)")
    if agent and kind_total:
        print(f"Kind accuracy on fixtures: {kind_hits}/{kind_total} ({100 * kind_hits / kind_total:.1f}%)")
    print("Update Swift constant in LayaCoreMLPayloadClassifier.swift after tuning on your own scans.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
