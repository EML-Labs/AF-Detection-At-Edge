"""Generate RobustScaler + classifier parity test vectors for the watch app.

The Swift `RobustScaler` and `AFClassifier` wrappers must produce the same
outputs as the Python reference for identical inputs. This script writes a
small JSON payload of inputs and expected outputs so the watch-side code
can be cross-validated either through unit tests or a quick on-device
parity check during bring-up.

Usage:
    python MLModel/scripts/generate_parity_vectors.py [--out path]
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

import numpy as np

try:
    from sklearn.preprocessing import RobustScaler
    HAS_SKLEARN = True
except ImportError:  # pragma: no cover
    HAS_SKLEARN = False

WINDOW_SIZE = 200
PATIENT_MEDIAN_MS = 800.0
PATIENT_SCALE_MS = 120.0


def make_test_windows(rng: np.random.Generator) -> list[list[float]]:
    """A small set of representative windows: regular SR, mild irregularity,
    coarse AF-like irregularity, edge cases (constant, alternating)."""
    windows: list[list[float]] = []
    base = rng.normal(loc=850.0, scale=20.0, size=WINDOW_SIZE)
    windows.append(base.tolist())

    irregular = rng.normal(loc=820.0, scale=80.0, size=WINDOW_SIZE)
    windows.append(irregular.tolist())

    afib_like = rng.normal(loc=780.0, scale=180.0, size=WINDOW_SIZE)
    afib_like = np.clip(afib_like, 350.0, 1800.0)
    windows.append(afib_like.tolist())

    constant = np.full(WINDOW_SIZE, 800.0)
    windows.append(constant.tolist())

    alternating = np.tile([700.0, 900.0], WINDOW_SIZE // 2)
    windows.append(alternating.tolist())

    return [list(map(float, w)) for w in windows]


def robust_scale(window: list[float]) -> list[float]:
    """Mirror Swift's `RobustScaler.scale(_:)`: (rr - median) / scale.

    When sklearn is available we double-check by fitting a fresh scaler on the
    median/IQR derived from our hardcoded params.
    """
    arr = np.asarray(window, dtype=np.float64)
    scaled = (arr - PATIENT_MEDIAN_MS) / PATIENT_SCALE_MS
    if HAS_SKLEARN:
        # sanity check: a RobustScaler with the same (median, scale) yields
        # the same output. We don't fit on `arr`; we set parameters directly.
        scaler = RobustScaler()
        scaler.center_ = np.array([PATIENT_MEDIAN_MS])
        scaler.scale_ = np.array([PATIENT_SCALE_MS])
        sk_out = scaler.transform(arr.reshape(-1, 1)).flatten()
        assert np.allclose(scaled, sk_out, rtol=1e-6, atol=1e-6)
    return scaled.astype(float).tolist()


def main() -> int:
    parser = argparse.ArgumentParser()
    default_out = Path(os.path.dirname(__file__)).parent / "Exports" / "parity_vectors.json"
    parser.add_argument("--out", type=Path, default=default_out)
    parser.add_argument("--seed", type=int, default=20260423)
    args = parser.parse_args()

    rng = np.random.default_rng(args.seed)
    windows = make_test_windows(rng)
    cases = []
    for idx, w in enumerate(windows):
        cases.append({
            "id": f"vec_{idx}",
            "input_rr_ms": w,
            "expected_scaled": robust_scale(w),
        })

    payload = {
        "model_contract": {
            "window_size": WINDOW_SIZE,
            "stride": 50,
            "scaler": {
                "kind": "RobustScaler",
                "median_ms": PATIENT_MEDIAN_MS,
                "scale_ms": PATIENT_SCALE_MS,
            },
            "output": "probability",
        },
        "cases": cases,
    }

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2))
    print(f"wrote {len(cases)} parity vectors to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
