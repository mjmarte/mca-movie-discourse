import glob
import json
import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import CLIP_KEY, CLIP_MAP, MATCH_THRESHOLD, TABLES, data_root

DATA = data_root()
EMB = DATA
OUT = TABLES

os.environ.setdefault('HF_HUB_OFFLINE', '1')
os.environ.setdefault('TOKENIZERS_PARALLELISM', 'false')

MATCH_MIN = MATCH_THRESHOLD

def main():
    from sentence_transformers import SentenceTransformer
    model = SentenceTransformer('sentence-transformers/all-mpnet-base-v2')

    cvecs, ctexts = {}, {}
    for stem, code in CLIP_KEY.items():
        items = json.load(open(DATA / 'inventories' / f'{stem}_mci.json'))
        labels = [c['label'] for c in items]
        cvecs[code] = model.encode(labels, normalize_embeddings=True).astype(np.float64)
        ctexts[code] = [(c['id'], c['label']) for c in items]

    rows = []
    for code, V in cvecs.items():
        for (cid, lab), v in zip(ctexts[code], V):
            rows.append(dict(clip=code, concept_id=cid, concept_text=lab,
                             **{f'emb_{i}': x for i, x in enumerate(v)}))
    pd.DataFrame(rows).to_csv(OUT / 'concept_embeddings.csv', index=False)

    ue = pd.read_csv(EMB / 'utterance_embeddings.csv')
    ecols = [c for c in ue.columns if c.startswith('emb_')]

    out = []
    for (pid, clip), g in ue.groupby(['participant_id', 'clip'], sort=False):
        V = cvecs[clip]
        U = g[ecols].to_numpy(dtype=np.float64)
        U = U / np.linalg.norm(U, axis=1, keepdims=True)
        sims = U @ V.T
        best, val = sims.argmax(axis=1), sims.max(axis=1)
        credited = set(best[val > MATCH_MIN].tolist())
        centroid = V.mean(axis=0)
        centroid = centroid / np.linalg.norm(centroid)
        out.append(dict(Participant=pid, Clip=CLIP_MAP[clip], clip_code=clip,
                        n_utterances=len(U),
                        mc_coverage_percentage=100.0 * len(credited) / V.shape[0],
                        mc_avg_distance_to_centroid=float((1.0 - U @ centroid).mean())))
    scored = pd.DataFrame(out)
    scored.to_csv(OUT / 'mc_features.csv', index=False)
    print(f'scored {len(scored)} participant-clip rows against the inventories')

    ana = pd.read_csv(DATA / 'features.csv')
    before = ana[['Participant', 'Clip', 'mc_coverage_percentage',
                  'mc_avg_distance_to_centroid', 'mc_semantic_coherence']].copy()

    merged = ana.drop(columns=['mc_coverage_percentage', 'mc_avg_distance_to_centroid']).merge(
        scored[['Participant', 'Clip', 'mc_coverage_percentage', 'mc_avg_distance_to_centroid']],
        on=['Participant', 'Clip'], how='left')
    merged = merged[ana.columns]

    assert len(merged) == len(ana), 'row count changed'
    assert merged['mc_semantic_coherence'].equals(before['mc_semantic_coherence']), \
        'coherence changed - it must not, it never references the inventory'
    n_new = merged['mc_coverage_percentage'].notna().sum()
    n_old = before['mc_coverage_percentage'].notna().sum()
    print(f'rows with MC data: was {n_old}, now {n_new}')
    print('mc_semantic_coherence unchanged: True')

    d = pd.DataFrame({
        'completeness_input': before['mc_coverage_percentage'],
        'completeness_rescored': merged['mc_coverage_percentage'],
        'distance_input': before['mc_avg_distance_to_centroid'],
        'distance_rescored': merged['mc_avg_distance_to_centroid']})
    print(d.describe().round(4).to_string())

    dest = DATA / 'features_rescored.csv'
    merged.to_csv(dest, index=False)
    print(f'\nwrote {dest}')

if __name__ == '__main__':
    main()
