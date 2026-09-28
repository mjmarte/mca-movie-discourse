import json
import os
import sys
from pathlib import Path

import numpy as np
import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import CLIPS, MATCH_THRESHOLD, TABLES, data_root

DATA = data_root()
EMB = DATA
OUT = TABLES

os.environ.setdefault('HF_HUB_OFFLINE', '1')
os.environ.setdefault('TOKENIZERS_PARALLELISM', 'false')
np.seterr(all='ignore')

MATCH_MIN = MATCH_THRESHOLD

CLIPS = sorted(CLIPS)
CLIP_NAME = {'AKB': 'Akeelah and the Bee', 'CMIYC': 'Catch Me If You Can',
             'GWH': 'Good Will Hunting', 'MIR': 'Miracle', 'MOON': 'Moonlight',
             'NCOM': 'No Country for Old Men', 'PT': 'The Parent Trap', 'PC': 'Partly Cloudy'}
RNG = np.random.default_rng(20260731)
NBOOT = 5000

def unit(v):
    return v / np.linalg.norm(v)

def cohen_d(a, b):
    a, b = np.asarray(a, float), np.asarray(b, float)
    s = np.sqrt(((len(a) - 1) * a.var(ddof=1) + (len(b) - 1) * b.var(ddof=1)) / (len(a) + len(b) - 2))
    return (a.mean() - b.mean()) / s

def main():
    inv = pd.read_csv(OUT / 'inventory.csv')
    cemb = pd.read_csv(OUT / 'concept_embeddings.csv')
    ecols = [c for c in cemb.columns if c.startswith('emb_')]
    cvecs = {clip: g[ecols].to_numpy(float) for clip, g in cemb.groupby('clip')}
    cids = {clip: g['concept_id'].tolist() for clip, g in cemb.groupby('clip')}

    ue = pd.read_csv(EMB / 'utterance_embeddings.csv')
    ucols = [c for c in ue.columns if c.startswith('emb_')]
    utt = {}
    for (pid, clip), g in ue.groupby(['participant_id', 'clip'], sort=False):
        U = g[ucols].to_numpy(float)
        utt[(pid, clip)] = U / np.linalg.norm(U, axis=1, keepdims=True)

    ana = pd.read_csv(DATA / 'features.csv')
    HC = sorted(ana[ana.Group == 'HC'].Participant.unique())
    PWA = sorted(ana[ana.Group == 'PWA'].Participant.unique())
    print(f'analysis sample: {len(HC)} HC, {len(PWA)} PWA')

    rows = []
    for clip in CLIPS:
        V = cvecs[clip]
        hits = np.zeros(len(V), int)
        n = 0
        for pid in HC:
            U = utt.get((pid, clip))
            if U is None:
                continue
            n += 1
            sims = U @ V.T
            best, val = sims.argmax(axis=1), sims.max(axis=1)
            for k in set(best[val > MATCH_MIN].tolist()):
                hits[k] += 1
        for k, cid in enumerate(cids[clip]):
            lab = inv[(inv.Clip == clip) & (inv.MC_ID == cid)].iloc[0]
            rows.append(dict(Clip=clip, ClipName=CLIP_NAME[clip], MC_ID=cid,
                             Concept=lab.Concept, Role=lab.Role, Grounding=lab.Grounding,
                             SupportRuns=int(lab.SupportRuns), N_HC=n, N_HC_matched=int(hits[k]),
                             Pct_HC=round(100.0 * hits[k] / n, 1),
                             Meets33='Yes' if 100.0 * hits[k] / n >= 33 else 'No',
                             Meets70='Yes' if 100.0 * hits[k] / n >= 70 else 'No'))
    s13 = pd.DataFrame(rows)
    s13.to_csv(OUT / 'hc_production_by_concept.csv', index=False)
    print(f'\n[1] per-concept HC production: {len(s13)} concepts; '
          f'median {s13.Pct_HC.median():.1f}%, range {s13.Pct_HC.min():.1f}-{s13.Pct_HC.max():.1f}%; '
          f'>=20% {int((s13.Pct_HC>=20).sum())}/{len(s13)}; '
          f'>=33% {int((s13.Pct_HC>=33).sum())}/{len(s13)}; '
          f'>=50% {int((s13.Pct_HC>=50).sum())}/{len(s13)}; '
          f'>=70% {int((s13.Pct_HC>=70).sum())}/{len(s13)}')
    perclip_prod = s13.groupby('Clip').Pct_HC.agg(['size', 'mean', 'median', 'min', 'max'])
    print('    per-clip mean production: '
          + ', '.join(f'{c} {perclip_prod.loc[c,"mean"]:.0f}%' for c in CLIPS))
    perclip_prod.round(1).to_csv(OUT / 'per_clip_production_summary.csv')

    cent_rows, mc_cent_rows = [], []
    for clip in CLIPS:
        V = cvecs[clip]
        M = unit(V.mean(axis=0))

        def part_dist(ids):
            out = []
            for pid in ids:
                U = utt.get((pid, clip))
                if U is None:
                    continue
                out.append(float((1.0 - U @ M).mean()))
            return np.array(out)

        dh, dp = part_dist(HC), part_dist(PWA)
        diff = dp.mean() - dh.mean()
        bs = np.array([RNG.choice(dp, len(dp), True).mean() - RNG.choice(dh, len(dh), True).mean()
                       for _ in range(NBOOT)])
        lo, hi = np.percentile(bs, [2.5, 97.5])
        cent_rows.append(dict(Clip=clip, ClipName=CLIP_NAME[clip], N_HC=len(dh), N_PWA=len(dp),
                              HC_mean_distance=round(dh.mean(), 4), HC_sd=round(dh.std(ddof=1), 4),
                              PWA_mean_distance=round(dp.mean(), 4), PWA_sd=round(dp.std(ddof=1), 4),
                              Difference=round(diff, 4), CI_lo=round(lo, 4), CI_hi=round(hi, 4),
                              Cohens_d=round(cohen_d(dp, dh), 3),
                              CI_excludes_zero='Yes' if lo > 0 else 'No'))

        def group_mc_centroid(ids):
            keep, allu = [], []
            for pid in ids:
                U = utt.get((pid, clip))
                if U is None:
                    continue
                allu.append(U)
                sims = U @ V.T
                keep.append(U[sims.max(axis=1) > MATCH_MIN])
            keep = np.vstack([k for k in keep if len(k)])
            allu = np.vstack(allu)
            return unit(keep.mean(axis=0)), unit(allu.mean(axis=0)), len(keep), len(allu)

        hmc, hall, nhk, nha = group_mc_centroid(HC)
        pmc, pall, npk, npa = group_mc_centroid(PWA)
        mc_cent_rows.append(dict(
            Clip=clip, ClipName=CLIP_NAME[clip],
            HC_mc_to_inventory=round(1 - float(hmc @ M), 4),
            PWA_mc_to_inventory=round(1 - float(pmc @ M), 4),
            HC_all_to_inventory=round(1 - float(hall @ M), 4),
            PWA_all_to_inventory=round(1 - float(pall @ M), 4),
            PWA_minus_HC=round(float(1 - pmc @ M) - float(1 - hmc @ M), 4),
            n_HC_mc_utterances=nhk, n_HC_utterances=nha,
            n_PWA_mc_utterances=npk, n_PWA_utterances=npa))

    cent = pd.DataFrame(cent_rows)
    cent.to_csv(OUT / 'per_clip_centroid_hc_vs_pwa.csv', index=False)
    mcc = pd.DataFrame(mc_cent_rows)
    mcc.to_csv(OUT / 'per_clip_group_mc_centroid_vs_inventory.csv', index=False)
    print(f'\n[2] per-clip distance to the inventory centroid, PWA minus HC:')
    print(cent[['Clip', 'HC_mean_distance', 'PWA_mean_distance', 'Difference',
                'CI_lo', 'CI_hi', 'Cohens_d', 'CI_excludes_zero']].to_string(index=False))
    print(f'    clips with a CI excluding zero: {int((cent.CI_excludes_zero=="Yes").sum())}/8')
    print('\n[3] group main concept centroid to inventory centroid (cosine distance):')
    print(mcc[['Clip', 'HC_mc_to_inventory', 'PWA_mc_to_inventory', 'PWA_minus_HC']]
          .to_string(index=False))
    print(f'    HC closer than PWA in {int((mcc.PWA_minus_HC>0).sum())}/8 clips')

    v2clip = pd.read_csv(OUT / 'mc_features.csv')
    v2clip['Group'] = np.where(v2clip.Participant.isin(HC), 'HC',
                               np.where(v2clip.Participant.isin(PWA), 'PWA', 'other'))
    v2clip = v2clip[v2clip.Group != 'other']
    disc = []
    for clip in CLIPS:
        g = v2clip[v2clip.clip_code == clip]
        h = g[g.Group == 'HC'].mc_coverage_percentage.dropna()
        p = g[g.Group == 'PWA'].mc_coverage_percentage.dropna()
        hd = g[g.Group == 'HC'].mc_avg_distance_to_centroid.dropna()
        pd_ = g[g.Group == 'PWA'].mc_avg_distance_to_centroid.dropna()
        disc.append(dict(Clip=clip, ClipName=CLIP_NAME[clip],
                         n_concepts=int((inv.Clip == clip).sum()),
                         mean_HC_production=round(perclip_prod.loc[clip, 'mean'], 1),
                         d_completeness=round(cohen_d(p, h), 3),
                         d_distance=round(cohen_d(pd_, hd), 3)))
    disc = pd.DataFrame(disc)
    r_comp = np.corrcoef(disc.mean_HC_production, disc.d_completeness.abs())[0, 1]
    r_dist = np.corrcoef(disc.mean_HC_production, disc.d_distance.abs())[0, 1]
    disc.to_csv(OUT / 'per_clip_production_vs_discrimination.csv', index=False)
    print('\n[4] production correspondence vs discrimination, across the 8 clips:')
    print(disc.to_string(index=False))
    print(f'    r(mean HC production, |d| completeness) = {r_comp:+.3f}')
    print(f'    r(mean HC production, |d| distance)     = {r_dist:+.3f}')
    json.dump(dict(r_production_vs_d_completeness=float(r_comp),
                   r_production_vs_d_distance=float(r_dist)),
              open(OUT / 'production_vs_discrimination_r.json', 'w'), indent=2)

    s13['AV_only'] = s13.Grounding == 'Audiovisual'
    s13['has_subtitle'] = s13.Grounding.isin(['Subtitles', 'Both'])
    av = s13[s13.AV_only]
    sub = s13[s13.has_subtitle]
    print(f'\n[5] grounding: {len(av)}/{len(s13)} concepts rest on audiovisual content with no '
          f'subtitle quote; {int((s13.Grounding=="Subtitles").sum())} on subtitles alone; '
          f'{int((s13.Grounding=="Both").sum())} on both')
    print(f'    HC production, audiovisual-only {av.Pct_HC.mean():.1f}% (median {av.Pct_HC.median():.1f}) '
          f'vs subtitle-grounded {sub.Pct_HC.mean():.1f}% (median {sub.Pct_HC.median():.1f})')
    print(f'    Partly Cloudy (wordless): {int((s13[s13.Clip=="PC"].Grounding=="Audiovisual").sum())}'
          f'/{int((s13.Clip=="PC").sum())} concepts audiovisual-only')
    s13.groupby('Grounding').Pct_HC.agg(['size', 'mean', 'median', 'min', 'max']).round(1) \
        .to_csv(OUT / 'production_by_grounding.csv')

    allc = pd.read_csv(OUT / 'panel_clusters_all.csv')
    print(f'\n[6] panel: {len(allc)} clusters reached >=3/5 support; {len(inv)} retained after the '
          f'20% floor; {len(allc)-len(inv)} dropped')
    print(f'    support among retained concepts: mean {inv.SupportRuns.mean():.2f} of 5 runs, '
          f'{int((inv.SupportRuns==5).sum())} unanimous, {int((inv.SupportRuns==4).sum())} at 4/5, '
          f'{int((inv.SupportRuns==3).sum())} at 3/5')
    dropped = pd.read_csv(OUT / 'panel_dropped_by_hc_floor.csv')
    if len(dropped):
        print(f'    dropped by the floor, production: '
              f'{", ".join(f"{r.pct_hc:.1f}%" for r in dropped.itertuples())}')

    json.dump(dict(
        n_concepts=int(len(inv)), per_clip={c: int((inv.Clip == c).sum()) for c in CLIPS},
        median_production=float(s13.Pct_HC.median()),
        min_production=float(s13.Pct_HC.min()), max_production=float(s13.Pct_HC.max()),
        n_ge20=int((s13.Pct_HC >= 20).sum()), n_ge33=int((s13.Pct_HC >= 33).sum()),
        n_ge50=int((s13.Pct_HC >= 50).sum()), n_ge70=int((s13.Pct_HC >= 70).sum()),
        clips_ci_excludes_zero=int((cent.CI_excludes_zero == 'Yes').sum()),
        clips_hc_closer=int((mcc.PWA_minus_HC > 0).sum()),
        n_av_only=int(len(av)), n_subtitle_only=int((s13.Grounding == 'Subtitles').sum()),
        n_both=int((s13.Grounding == 'Both').sum()),
        mean_production_av_only=round(float(av.Pct_HC.mean()), 1),
        mean_production_subtitle=round(float(sub.Pct_HC.mean()), 1),
        mean_panel_support=round(float(inv.SupportRuns.mean()), 2),
        r_production_vs_d_completeness=round(float(r_comp), 3),
        r_production_vs_d_distance=round(float(r_dist), 3),
        n_boot=NBOOT,
    ), open(OUT / 'validation_key_numbers.json', 'w'), indent=2)
    print(f'\nwrote validation_key_numbers.json')

if __name__ == '__main__':
    main()
