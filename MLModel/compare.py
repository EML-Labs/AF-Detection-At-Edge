import os
import platform
import time
from pathlib import Path

import coremltools as ct
import numpy as np
import torch
import torch.nn.functional as F

from Model.Encoder import Encoder
from Utils.Dataset.IRIDIA import ClassificationDataset

MODELS_DIR = Path(os.getcwd()) / "Exports" / "models"
PTH_PATH = MODELS_DIR / "encoder.pth"
MLPACKAGE_PATH = MODELS_DIR / "encoder.mlpackage"


def _human_bytes(n: float) -> str:
    for unit in ("B", "KiB", "MiB", "GiB"):
        if n < 1024:
            return f"{n:.2f} {unit}"
        n /= 1024
    return f"{n:.2f} TiB"


def _path_size_bytes(path: Path) -> int:
    if path.is_file():
        return path.stat().st_size
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())


def _weight_bin_paths(mlpackage: Path) -> list[Path]:
    return sorted(mlpackage.rglob("weight.bin"))


def _coreml_predict_latent(
    converted_encoder: ct.models.MLModel,
    x: torch.Tensor,
) -> np.ndarray:
    spec = converted_encoder.get_spec()
    input_name = spec.description.input[0].name
    output_name = spec.description.output[0].name
    out = converted_encoder.predict({input_name: x.detach().cpu().numpy().astype(np.float32)})
    return np.asarray(out[output_name]).reshape(-1)


def _torchscript_predict_latent(
    traced_encoder: torch.jit.ScriptModule,
    x: torch.Tensor,
) -> torch.Tensor:
    with torch.no_grad():
        return traced_encoder(x).squeeze(0).detach().cpu()


def _print_dataset_latent_diff_report(
    encoder: Encoder,
    converted_encoder: ct.models.MLModel,
    max_samples: int = 256,
) -> None:
    config = {
        "classification": {
            "minimum_af_length": int(60 * 60),
            "minimum_sr_length": int(4 * 60 * 60),
            "minimum_sr_time_to_be_considered_for_scaler": int(1 * 60 * 60),
        },
        "window_size": 200,
        "stride": 50,
    }
    dataset = ClassificationDataset(
        processed_dataset_path=os.path.join(os.getcwd(), "processed_datasets"),
        minimum_af_length=config["classification"]["minimum_af_length"],
        minimum_sr_length=config["classification"]["minimum_sr_length"],
        minimum_sr_time_to_be_considered_for_scaler=config["classification"][
            "minimum_sr_time_to_be_considered_for_scaler"
        ],
        window_size=config["window_size"],
        stride=config["stride"],
        train=False,
        test=True,
    )
    n_eval = min(max_samples, len(dataset))
    if n_eval == 0:
        print("\n=== Dataset latent comparison ===")
        print("  Dataset is empty; skipping.")
        return

    can_run_coreml_predict = platform.system() == "Darwin"
    if can_run_coreml_predict:
        backend_name = "Core ML (mlpackage runtime)"
    else:
        backend_name = "TorchScript trace fallback (Linux-compatible proxy)"
        # Same traced graph that converter.py uses prior to Core ML conversion.
        example_input = torch.rand(1, 200)
        traced_encoder = torch.jit.trace(encoder, example_input)
        traced_encoder.eval()

    l2_errors = []
    mae_errors = []
    max_abs_errors = []
    cosine_sims = []
    labels = []
    patient_ids = []

    with torch.no_grad():
        for idx in range(n_eval):
            rr_window, label, patient_id = dataset[idx]
            rr_window = rr_window.float().unsqueeze(0)

            latent_pt = encoder(rr_window).squeeze(0).detach().cpu()
            if can_run_coreml_predict:
                latent_ml = torch.from_numpy(
                    _coreml_predict_latent(converted_encoder, rr_window)
                )
            else:
                latent_ml = _torchscript_predict_latent(traced_encoder, rr_window)

            diff = latent_pt - latent_ml
            l2_errors.append(torch.norm(diff, p=2).item())
            mae_errors.append(torch.mean(torch.abs(diff)).item())
            max_abs_errors.append(torch.max(torch.abs(diff)).item())
            cosine_sims.append(
                F.cosine_similarity(
                    latent_pt.unsqueeze(0), latent_ml.unsqueeze(0), dim=1
                ).item()
            )
            labels.append(int(label.item()))
            patient_ids.append(int(patient_id.item()))

    l2 = np.asarray(l2_errors, dtype=np.float64)
    mae = np.asarray(mae_errors, dtype=np.float64)
    max_abs = np.asarray(max_abs_errors, dtype=np.float64)
    cos = np.asarray(cosine_sims, dtype=np.float64)
    labels_np = np.asarray(labels, dtype=np.int64)
    patient_np = np.asarray(patient_ids, dtype=np.int64)

    print("\n=== Dataset latent comparison (PyTorch vs Core ML) ===")
    print(f"  Comparison backend: {backend_name}")
    if not can_run_coreml_predict:
        print("  Note: Core ML predict() is unavailable on Linux; using TorchScript proxy.")
    print(f"  Samples evaluated: {n_eval:,} / {len(dataset):,}")
    print(f"  Unique patients in sample: {np.unique(patient_np).size}")
    print(f"  Mean L2(latent diff): {l2.mean():.6f}")
    print(f"  P95 L2(latent diff):  {np.percentile(l2, 95):.6f}")
    print(f"  Mean MAE(latent dim): {mae.mean():.6f}")
    print(f"  Max |diff| observed:  {max_abs.max():.6f}")
    print(f"  Mean cosine similarity: {cos.mean():.8f}")
    print(f"  Min cosine similarity:  {cos.min():.8f}")

    print("\n=== By-label latent drift ===")
    for label_val in np.unique(labels_np):
        mask = labels_np == label_val
        print(
            f"  label={label_val}: n={mask.sum():,}, "
            f"mean_l2={l2[mask].mean():.6f}, "
            f"mean_mae={mae[mask].mean():.6f}, "
            f"mean_cos={cos[mask].mean():.8f}"
        )


def _print_comparison_report(
    encoder: Encoder,
    converted_encoder: ct.models.MLModel,
) -> None:
    total_params = sum(p.numel() for p in encoder.parameters())
    trainable_params = sum(p.numel() for p in encoder.parameters() if p.requires_grad)
    pth_bytes = PTH_PATH.stat().st_size
    mlpackage_bytes = _path_size_bytes(MLPACKAGE_PATH)
    fp32_weight_bytes = total_params * 4

    weight_bins = _weight_bin_paths(MLPACKAGE_PATH)
    weight_bin_total = sum(p.stat().st_size for p in weight_bins)

    print("\n=== Parameters ===")
    print(f"  PyTorch total parameters:     {total_params:,}")
    print(f"  PyTorch trainable parameters: {trainable_params:,}")
    print(
        "  Core ML: same graph/weights as traced encoder (Core ML does not expose a "
        "parameter count API); compare serialized weight size below."
    )

    print("\n=== On-disk / bundle size (edge deployment) ===")
    print(f"  encoder.pth (state_dict):     {_human_bytes(pth_bytes)} ({pth_bytes:,} B)")
    print(
        f"  encoder.mlpackage (full):     {_human_bytes(mlpackage_bytes)} ({mlpackage_bytes:,} B)"
    )
    if weight_bins:
        print(f"  weight.bin (serialized):      {_human_bytes(weight_bin_total)} ({weight_bin_total:,} B)")
        if weight_bin_total > 0:
            ratio = fp32_weight_bytes / weight_bin_total
            hint = (
                "~FP16 or mixed packing"
                if 1.6 < ratio < 2.4
                else "compare to 4× param count for FP32"
            )
            print(
                f"  Implied vs FP32 weights ({_human_bytes(fp32_weight_bytes)}): "
                f"{ratio:.2f}× smaller ({hint})"
            )

    print("\n=== Estimated runtime weight memory (theory, FP32 tensors) ===")
    print(f"  PyTorch weights (FP32): ~{_human_bytes(fp32_weight_bytes)}")

    spec = converted_encoder.get_spec()
    desc = spec.description
    print("\n=== Core ML I/O (static shapes help on-device) ===")
    for inp in desc.input:
        print(f"  input:  {inp.name} — {inp.type}")
    for out in desc.output:
        print(f"  output: {out.name} — {out.type}")

    ud = dict(desc.metadata.userDefined) if desc.metadata else {}
    if ud:
        print("\n=== Core ML metadata (userDefined) ===")
        for k in sorted(ud):
            print(f"  {k}: {ud[k]}")

    print("\n=== Latency proxy (PyTorch CPU on this machine) ===")
    example = torch.randn(1, 200)
    with torch.no_grad():
        for _ in range(5):
            encoder(example)
    n = 100
    t0 = time.perf_counter()
    with torch.no_grad():
        for _ in range(n):
            encoder(example)
    ms = (time.perf_counter() - t0) / n * 1000
    print(f"  Mean forward: {ms:.3f} ms over {n} runs (batch=1, seq=200)")
    print(
        "  Core ML: run Instruments / XCTest on device; `predict` is not representative on Linux."
    )


encoder = Encoder(latent_dim=128, dropout=0.1)
encoder.load_state_dict(torch.load(PTH_PATH, map_location="cpu"))
encoder.eval()

converted_encoder = ct.models.MLModel(str(MLPACKAGE_PATH))
print("Converted encoder loaded")
_print_comparison_report(encoder, converted_encoder)
_print_dataset_latent_diff_report(encoder, converted_encoder, max_samples=256)

# config = {
#     "classification": {
#         "minimum_af_length": int(60*60),
#         "minimum_sr_length": int(4*60*60),
#         "minimum_sr_time_to_be_considered_for_scaler": int(1*60*60),
#     },
#     "window_size": 200,
#     "stride": 50,
# }
# dataset = ClassificationDataset(
#     processed_dataset_path=os.path.join(os.getcwd(),"processed_datasets"),
#     minimum_af_length=config["classification"]["minimum_af_length"],
#     minimum_sr_length=config["classification"]["minimum_sr_length"],
#     minimum_sr_time_to_be_considered_for_scaler=config["classification"]["minimum_sr_time_to_be_considered_for_scaler"],
#     window_size=config["window_size"],
#     stride=config["stride"],
#     train=False,
#     test=True,
# )

# print(dataset[0])