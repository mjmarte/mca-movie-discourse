import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import SEED, TABLES

OUT = TABLES
N_BOOT = 2000
METRICS = ["accuracy", "sensitivity", "specificity", "Youden's J"]

def metrics(y, cls, idx):
    yy, cc = y[idx], cls[idx]
    acc = float((yy == cc).mean())
    sens = float((cc[yy == 1] == 1).mean()) if (yy == 1).any() else np.nan
    spec = float((cc[yy == 0] == 0).mean()) if (yy == 0).any() else np.nan
    return acc, sens, spec, sens + spec - 1

def bootstrap_cis():
    pred = pd.read_csv(OUT / "lasso_predictions.csv")
    y = pred["true"].to_numpy()

    cls = (pred["pred_prob"].to_numpy() >= 0.5).astype(int)
    iP = np.where(y == 1)[0]
    iH = np.where(y == 0)[0]

    observed = metrics(y, cls, np.arange(len(y)))
    rng = np.random.default_rng(SEED)
    draws = np.array([
        metrics(y, cls, np.concatenate([rng.choice(iP, iP.size, replace=True),
                                        rng.choice(iH, iH.size, replace=True)]))
        for _ in range(N_BOOT)
    ])
    lo, hi = np.percentile(draws, [2.5, 97.5], axis=0)
    return {k: [observed[i], float(lo[i]), float(hi[i])] for i, k in enumerate(METRICS)}

def main():
    res = bootstrap_cis()
    target = OUT / "lasso_metric_cis.json"

    if "--check" in sys.argv:
        ref = json.loads(target.read_text())
        same = all(np.allclose(res[k], ref[k], atol=1e-12) for k in ref)
        print("reproduces the stored file:", same)
        for k in METRICS:
            print(f"  {k:<12} stored [{ref[k][1]:.4f}, {ref[k][2]:.4f}]   "
                  f"recomputed [{res[k][1]:.4f}, {res[k][2]:.4f}]")
        sys.exit(0 if same else 1)

    target.write_text(json.dumps(res, indent=1))
    print("wrote", target)
    for k, v in res.items():
        print(f"  {k:<12} {v[0]:.4f}  95% CI [{v[1]:.4f}, {v[2]:.4f}]")

if __name__ == "__main__":
    main()
