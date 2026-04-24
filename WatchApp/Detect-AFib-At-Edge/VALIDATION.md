# AFib Watch App – Validation Checklist

This document captures the validation steps for the watchOS + iOS pipeline
implemented per the Part 2 plan. Run through each section before treating a
build as release-candidate.

## 1. Preprocessing parity (`RobustScaler`)

1. From the repo root, generate test vectors:
   ```bash
   python MLModel/scripts/generate_parity_vectors.py
   ```
   Output lands at `MLModel/Exports/parity_vectors.json`.
2. Hardcoded patient parameters in
   `WatchApp/.../Constants/AFConstants.swift` (`RobustScalerParams.median`,
   `.scale`) must match `model_contract.scaler.median_ms` and `scale_ms`
   in the JSON.
3. Optional: temporarily bundle the JSON into the watch target and call
   `RobustScaler.scale(input)` for each `cases[i].input_rr_ms`, asserting
   element-wise equality with `cases[i].expected_scaled` (tolerance 1e-5).

## 2. RR ingestion parity

`HeartbeatSeriesIngestor.computeRRIntervals(beats:)` is a pure function.
Verify with synthetic beats:

- Two beats 0.8s apart should yield one RR interval of 800ms.
- A beat with `precededByGap == true` produces an interval whose
  `precededByGap` flag is true so `RRQualityFilter` drops it.
- Three beats at relative times `0, 0.7, 1.6`s produce two intervals
  `700ms` and `900ms`, both timestamped at the closing beat.

## 3. Window assembler invariants

For `windowSize = 200`, `stride = 50`:

- Feeding 199 valid RR samples yields 0 windows.
- Feeding the 200th sample yields 1 window (first emission), and
  `samplesSinceLastEmission` resets to 0.
- After the first emission, feeding 50 more samples (total 250)
  yields 1 additional window.
- Feeding 49 more after that (total 299) yields 0 windows.
- A burst ingest of 1,000 fresh samples on first launch yields 1
  window (the most recent 200) – older intermediate windows are
  intentionally skipped to keep first-launch lag bounded.
- Buffer never exceeds `bufferCapacity = 800` samples.

## 4. Warning state machine

With defaults `hysteresisWindow = 5`, `positivesToWarn = 3`,
`negativesToClear = 4`:

- 4 inferences with `isPositive = true, validSampleCount = 200` keep
  the state at `monitoring` (insufficient observations).
- 5 inferences, of which 3+ are positive, transition to `warning` and
  return `.raisedWarning` exactly once.
- After warning, 4-of-5 negatives transition back to `monitoring` and
  return `.clearedWarning` exactly once.
- A single inference with `validSampleCount < 100` while not in
  warning sets state to `lowQuality`. The next high-quality inference
  resumes normal evaluation.

## 5. End-to-end on watch (device required)

1. Pair an Apple Watch (paired with iPhone) and grant HealthKit
   permission when prompted on first launch.
2. Start an outdoor walk workout for ~3 minutes so HealthKit writes
   beat-to-beat series.
3. Open the AFib watch app: status should transition `idle` →
   `collecting` → `monitoring` once enough RR samples accumulate.
4. Verify the iOS companion (`Detect-AFib-At-Edge`) mirrors the same
   status and displays the latest probability.
5. Force a warning by temporarily lowering `afProbabilityThreshold`
   in `AFConstants` to `0.0`; expect a notification, the warning
   screen on the watch, and an entry in the iOS alert history.

## 6. Background behaviour

1. Lock the watch and wait at least one
   `backgroundRefreshInterval` (default 15 minutes).
2. Confirm via the iOS companion's `Recent windows` list that new
   inferences arrived without re-opening the watch app.
3. Inspect Console.app filtered by `Detect-AFib-At-Edge` to confirm
   no `setTaskCompletedWithSnapshot` overruns or HealthKit errors.

## 7. Performance smoke test

- Single Core ML inference latency on watch (Series 9+): expect
  < 50 ms for a 200-element Float32 input.
- Memory footprint while idle: < 30 MB.
- Battery impact over an 8-hour day with light wear: < 5% extra drain.

## 8. Production model bring-up

When the Part 1 classifier ships:

1. Drop `AFClassifier.mlpackage` into the watch app's synchronized
   folder. Xcode auto-includes it.
2. Rebuild; the dev-mode banner in the UI disappears
   (`coordinator.isUsingBundledModel == true`).
3. Re-run sections 1–7 with the production model.
