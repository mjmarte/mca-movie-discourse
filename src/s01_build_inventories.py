import glob
import json
import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import (CLIP_KEY, CLIP_TITLES, HC_PRODUCTION_FLOOR, MATCH_THRESHOLD,
                    MIN_RUN_SUPPORT, TABLES, data_root, generation_runs)

DATA = data_root()
EMB = DATA
OUT = TABLES

os.environ.setdefault('HF_HUB_OFFLINE', '1')
os.environ.setdefault('TRANSFORMERS_OFFLINE', '1')
os.environ.setdefault('TOKENIZERS_PARALLELISM', 'false')

NB = generation_runs()

INVENTORY_DIR = DATA / 'inventories'
INVENTORY_DIR.mkdir(exist_ok=True)

CLIP_NAME = CLIP_TITLES

MATCH_MIN = MATCH_THRESHOLD
MIN_SUPPORT = MIN_RUN_SUPPORT
HC_FLOOR = HC_PRODUCTION_FLOOR * 100

CALIB_PCTILE = 95

def encoder():
    from sentence_transformers import SentenceTransformer
    return SentenceTransformer('sentence-transformers/all-mpnet-base-v2')

def load_candidates():
    out = {}
    for stem, code in CLIP_KEY.items():
        runs = []
        for f in sorted(glob.glob(str(NB / stem / '*.json'))):
            d = json.load(open(f))
            items = d if isinstance(d, list) else (d.get('concepts') or [])
            runs.append([c for c in items if c.get('label')])
        assert len(runs) == 5, f'{stem}: {len(runs)} runs'
        out[code] = runs
    return out

def calibrate(cands, model):
    sims = []
    per_run = []
    for code, runs in cands.items():
        for ri, run in enumerate(runs):
            E = model.encode([c['label'] for c in run], normalize_embeddings=True)
            S = E @ E.T
            iu = np.triu_indices(len(run), k=1)
            vals = S[iu]
            sims.extend(vals.tolist())
            per_run.append(dict(clip=code, run=ri + 1, n_concepts=len(run),
                                n_pairs=len(vals), mean_sim=float(vals.mean()),
                                max_sim=float(vals.max())))
    sims = np.array(sims)
    tau = float(np.percentile(sims, CALIB_PCTILE))
    pd.DataFrame(per_run).to_csv(OUT / 'panel_calibration_per_run.csv', index=False)
    return tau, sims

def cluster_clip(run_concepts, E, spans, tau):
    clusters = []
    for ri, span in enumerate(spans):
        for i in span:
            best, best_sim = None, tau
            for ci, cl in enumerate(clusters):
                if ri in {r for r, _ in cl}:
                    continue
                sim = max(float(E[i] @ E[j]) for _, j in cl)
                if sim > best_sim:
                    best, best_sim = ci, sim
            if best is None:
                clusters.append([(ri, i)])
            else:
                clusters[best].append((ri, i))
    return clusters

def reciprocal_best_match(E, spans, run_concepts):
    n = E.shape[0]
    owner = np.empty(n, dtype=int)
    for ri, span in enumerate(spans):
        for i in span:
            owner[i] = ri
    S = E @ E.T
    np.fill_diagonal(S, -np.inf)
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    for ra in range(len(spans)):
        for rb in range(len(spans)):
            if ra >= rb:
                continue
            A, B = spans[ra], spans[rb]
            sub = S[np.ix_(A, B)]
            for ai, i in enumerate(A):
                bj = int(sub[ai].argmax())
                if int(sub[:, bj].argmax()) == ai:
                    union(i, B[bj])
    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(i)
    return [[(owner[i], i) for i in g] for g in groups.values()]

def medoid(idx, E):
    return max(idx, key=lambda i: sum(float(E[i] @ E[j]) for j in idx))

def hc_argmax_production(concept_vecs, utt_by_pid_clip, clip, hc_ids):
    V = np.asarray(concept_vecs)
    V = V / np.linalg.norm(V, axis=1, keepdims=True)
    hits = np.zeros(len(V), dtype=int)
    n = 0
    for pid in hc_ids:
        U = utt_by_pid_clip.get((pid, clip))
        if U is None:
            continue
        n += 1
        sims = U @ V.T
        best = sims.argmax(axis=1)
        val = sims.max(axis=1)
        for k in set(best[val > MATCH_MIN].tolist()):
            hits[k] += 1
    return n, hits

def main():
    model = encoder()
    cands = load_candidates()

    tau, sims = calibrate(cands, model)
    print(f'candidate concepts: {sum(len(r) for runs in cands.values() for r in runs)}')
    print(f'within-run distinct-concept similarity: n={len(sims)}  '
          f'mean={sims.mean():.4f}  median={np.median(sims):.4f}  '
          f'p90={np.percentile(sims,90):.4f}  p95={tau:.4f}  p99={np.percentile(sims,99):.4f}  '
          f'max={sims.max():.4f}')

    ue = pd.read_csv(EMB / 'utterance_embeddings.csv')
    ecols = [c for c in ue.columns if c.startswith('emb_')]
    utt = {}
    for (pid, clip), g in ue.groupby(['participant_id', 'clip'], sort=False):
        U = g[ecols].to_numpy(dtype=np.float64)
        utt[(pid, clip)] = U / np.linalg.norm(U, axis=1, keepdims=True)
    ana = pd.read_csv(DATA / 'features.csv')
    hc_ids = sorted(ana[ana.Group == 'HC'].Participant.unique())
    print(f'analysis-sample healthy controls: {len(hc_ids)}')

    rows, panel_rows, dropped_rows = [], [], []
    rbm_sizes = {}

    for code in ['AKB', 'CMIYC', 'GWH', 'MIR', 'MOON', 'NCOM', 'PT', 'PC']:
        runs = cands[code]
        flat = [c for run in runs for c in run]
        labels = [c['label'] for c in flat]
        E = model.encode(labels, normalize_embeddings=True).astype(np.float64)
        spans, s = [], 0
        for run in runs:
            spans.append(list(range(s, s + len(run))))
            s += len(run)

        clusters = cluster_clip(runs, E, spans, tau)
        kept = [cl for cl in clusters if len({r for r, _ in cl}) >= MIN_SUPPORT]
        kept.sort(key=lambda cl: (-len({r for r, _ in cl}), min(i for _, i in cl)))

        rbm = reciprocal_best_match(E, spans, runs)
        rbm_sizes[code] = sum(1 for cl in rbm if len({r for r, _ in cl}) >= MIN_SUPPORT)

        reps = []
        for cl in kept:
            idx = [i for _, i in cl]
            m = medoid(idx, E)
            reps.append(dict(support=len({r for r, _ in cl}), medoid=m, members=idx))
        V = [E[r['medoid']] for r in reps]
        n_hc, hits = hc_argmax_production(V, utt, code, hc_ids)
        pct = 100.0 * hits / n_hc

        keep_mask = pct >= HC_FLOOR
        print(f'{code}: {len(flat)} candidates -> {len(clusters)} clusters -> '
              f'{len(kept)} at >={MIN_SUPPORT}/5 -> {int(keep_mask.sum())} after the {HC_FLOOR:.0f}% floor '
              f'(RBM variant would give {rbm_sizes[code]})')

        out_json, mc_i = [], 0
        for j, r in enumerate(reps):
            src = flat[r['medoid']]
            rec = dict(clip=code, clip_name=CLIP_NAME[code], label=src['label'],
                       role=src.get('role', ''), support_runs=r['support'],
                       pct_hc=round(float(pct[j]), 1), n_hc=n_hc,
                       n_hc_matched=int(hits[j]), retained=bool(keep_mask[j]))
            panel_rows.append(rec)
            if not keep_mask[j]:
                dropped_rows.append(rec)
                continue
            mc_i += 1
            sup = src.get('support', {}) or {}
            quotes = sup.get('transcript_quotes') or []
            frames = sup.get('frame_ids') or []
            grounding = ('Both' if quotes and frames else
                         'Subtitles' if quotes else
                         'Audiovisual' if frames or sup.get('audio_note') else 'Unspecified')
            out_json.append({
                'id': f'MC-{mc_i:02d}',
                'label': src['label'],
                'definition': src.get('definition', ''),
                'role': src.get('role', ''),
                'positives': src.get('positives', []),
                'negatives': src.get('negatives', []),
                'support': {
                    'sources': sup.get('sources', []),
                    'transcript_quotes': quotes,
                    'frame_ids': frames,
                    **({'audio_note': sup['audio_note']} if sup.get('audio_note') else {}),
                },
                'panel': {'support_runs': r['support'], 'n_runs': 5,
                          'equivalence_threshold': round(tau, 4),
                          'medoid_of_n_members': len(r['members'])},
                'grounding': grounding,
            })
            rows.append(dict(Clip=code, ClipName=CLIP_NAME[code], MC_ID=f'MC-{mc_i:02d}',
                             Concept=src['label'], Role=src.get('role', ''),
                             Grounding=grounding, SupportRuns=r['support'],
                             PctHC=round(float(pct[j]), 1), NHC=n_hc,
                             NHCmatched=int(hits[j])))

        stem = [k for k, v in CLIP_KEY.items() if v == code][0]
        with open(INVENTORY_DIR / f'{stem}_mci.json', 'w') as f:
            json.dump(out_json, f, indent=2)

    inv = pd.DataFrame(rows)
    inv.to_csv(OUT / 'inventory.csv', index=False)
    pd.DataFrame(panel_rows).to_csv(OUT / 'panel_clusters_all.csv', index=False)
    pd.DataFrame(dropped_rows).to_csv(OUT / 'panel_dropped_by_hc_floor.csv', index=False)

    print(f'\ninventory: {len(inv)} concepts, {inv.groupby("Clip").size().to_dict()}')
    print(f'panel support (retained): mean {inv.SupportRuns.mean():.2f} of 5, '
          f'min {inv.SupportRuns.min()}, all-five {int((inv.SupportRuns==5).sum())}')
    print(f'HC production: median {inv.PctHC.median():.1f}%, min {inv.PctHC.min():.1f}%, '
          f'max {inv.PctHC.max():.1f}%; >=33% {int((inv.PctHC>=33).sum())}/{len(inv)}; '
          f'>=50% {int((inv.PctHC>=50).sum())}/{len(inv)}; >=70% {int((inv.PctHC>=70).sum())}/{len(inv)}')
    print(f'calibrated equivalence threshold tau = {tau:.4f}')
    with open(OUT / 'panel_construction_summary.json', 'w') as f:
        json.dump(dict(tau=tau, min_support=MIN_SUPPORT, hc_floor=HC_FLOOR,
                       match_min=MATCH_MIN, n_hc=len(hc_ids),
                       n_concepts=len(inv),
                       per_clip=inv.groupby('Clip').size().to_dict(),
                       rbm_variant_per_clip=rbm_sizes,
                       within_run_sim=dict(n=int(len(sims)), mean=float(sims.mean()),
                                           p90=float(np.percentile(sims, 90)),
                                           p95=tau, p99=float(np.percentile(sims, 99)),
                                           max=float(sims.max()))), f, indent=2)

if __name__ == '__main__':
    main()
