import json
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import CLIPS, CLIP_SHORT, MATCH_THRESHOLD, TABLES, data_root

DATA = data_root()
EMB = DATA
OUT = TABLES

CLOSEST_SHARE = 0.05

def unit(a, axis=1):
    return a / np.linalg.norm(a, axis=axis, keepdims=True)

def main():
    ce = pd.read_csv(OUT / "concept_embeddings.csv")
    ec = [c for c in ce.columns if c.startswith("emb_")]
    ue = pd.read_csv(EMB / "utterance_embeddings.csv")
    eu = [c for c in ue.columns if c.startswith("emb_")]
    ana = pd.read_csv(DATA / "features.csv")
    group = dict(zip(ana.Participant, ana.Group))

    rows = []
    for clip in CLIPS:
        V = unit(ce[ce["clip"] == clip][ec].to_numpy(float))

        centroid = V.mean(0)
        centroid /= np.linalg.norm(centroid)

        sub = ue[(ue["clip"] == clip) & (ue.participant_id.isin(group))]
        U = unit(sub[eu].to_numpy(float))

        with np.errstate(divide="ignore", over="ignore", invalid="ignore"):

            sim_nearest = (U @ V.T).max(1)
            dist_centroid = 1 - U @ centroid
        assert np.isfinite(sim_nearest).all() and np.isfinite(dist_centroid).all(), clip
        rows.append(pd.DataFrame({
            "clip": CLIP_SHORT[clip],
            "group": [group[p] for p in sub.participant_id],
            "sim_nearest": sim_nearest,
            "dist_centroid": dist_centroid,
        }))

    df = pd.concat(rows, ignore_index=True)
    df["matched"] = df.sim_nearest > MATCH_THRESHOLD

    df["closest"] = df.groupby("clip").dist_centroid.transform(
        lambda s: s <= s.quantile(CLOSEST_SHARE))
    df.to_csv(OUT / "utterance_distances.csv", index=False)

    closest = df[df.closest]
    summary = {
        "n_utterances": int(len(df)),
        "n_closest": int(len(closest)),
        "closest_share": CLOSEST_SHARE,
        "hc_share_of_closest": float(100 * (closest.group == "HC").mean()),
        "hc_share_of_all": float(100 * (df.group == "HC").mean()),
        "hc_share_of_closest_by_clip": {
            c: float(100 * (g.group == "HC").mean()) for c, g in closest.groupby("clip")
        },
    }
    (OUT / "closest_utterances_summary.json").write_text(json.dumps(summary, indent=1))

    print(f"{summary['n_utterances']} utterances; closest {CLOSEST_SHARE:.0%} within clip "
          f"= {summary['n_closest']}")
    print(f"  healthy controls: {summary['hc_share_of_closest']:.1f}% of the closest, "
          f"{summary['hc_share_of_all']:.1f}% of all")
    for clip, share in summary["hc_share_of_closest_by_clip"].items():
        print(f"   {clip:<14} {share:5.1f}%")

if __name__ == "__main__":
    main()
