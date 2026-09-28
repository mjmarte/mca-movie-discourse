import warnings

import numpy as np
import pandas as pd

warnings.filterwarnings('ignore', category=DeprecationWarning)
warnings.filterwarnings('ignore', category=FutureWarning)
warnings.filterwarnings('ignore', category=UserWarning)
from pathlib import Path
from scipy.spatial.distance import squareform
from scipy.stats import spearmanr
from sklearn.decomposition import PCA
from sklearn.manifold import MDS, TSNE, Isomap, trustworthiness
import umap

import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from config import CLIPS, CLIP_SHORT, SEED, TABLES, data_root

DATA = data_root()
EMB = DATA
OUT = TABLES
DEST = TABLES

SHORT = CLIP_SHORT
ORDER = CLIPS
ce=pd.read_csv(OUT/'concept_embeddings.csv'); ec=[c for c in ce.columns if c.startswith('emb_')]
ue=pd.read_csv(EMB/'utterance_embeddings.csv');  eu=[c for c in ue.columns if c.startswith('emb_')]
ana=pd.read_csv(DATA/'features.csv')
grp=dict(zip(ana.Participant,ana.Group))

def cohen(a,b):
    na,nb=len(a),len(b); s=np.sqrt(((na-1)*np.var(a,ddof=1)+(nb-1)*np.var(b,ddof=1))/(na+nb-2))
    return (np.mean(b)-np.mean(a))/s

coords,mets=[],[]
for clip in ORDER:
    V=ce[ce['clip']==clip][ec].to_numpy(float); V/=np.linalg.norm(V,axis=1,keepdims=True)
    cen=V.mean(0); cen/=np.linalg.norm(cen)
    sub=ue[(ue['clip']==clip)&(ue.participant_id.isin(grp))]
    P,lab=[],[]
    for pid,g in sub.groupby('participant_id'):
        U=g[eu].to_numpy(float); U/=np.linalg.norm(U,axis=1,keepdims=True)
        m=U.mean(0); P.append(m/np.linalg.norm(m)); lab.append(grp[pid])
    P=np.array(P); X=np.vstack([P,V,cen[None,:]]); kind=lab+['Concept']*len(V)+['Centroid']
    D=np.clip(1-X@X.T,0,None); np.fill_diagonal(D,0); D=(D+D.T)/2
    n=len(X)

    dtrue=1-P@cen; d768=cohen(dtrue[np.array(lab)=='HC'],dtrue[np.array(lab)=='PWA'])
    projs={
      'PCA'        : PCA(n_components=2,random_state=SEED).fit_transform(X),
      'Metric MDS' : MDS(n_components=2,metric=True,dissimilarity='precomputed',n_init=8,
                         max_iter=500,random_state=SEED,normalized_stress=False).fit_transform(D),
      't-SNE'      : TSNE(n_components=2,metric='precomputed',init='random',
                          perplexity=min(20,(n-1)//3),random_state=SEED).fit_transform(D),
      'UMAP'       : umap.UMAP(n_components=2,metric='precomputed',n_neighbors=min(15,n-1),
                               min_dist=0.1,random_state=SEED).fit_transform(D),
      'Isomap'     : Isomap(n_components=2,n_neighbors=10,metric='precomputed').fit_transform(D),
    }
    dv=squareform(D,checks=False)
    for name,Y in projs.items():
        Dy=np.linalg.norm(Y[:,None,:]-Y[None,:,:],axis=-1)
        yv=squareform(Dy,checks=False)
        rho=spearmanr(dv,yv).statistic

        stress1=np.sqrt(((dv-yv*(dv@yv)/(yv@yv))**2).sum()/(dv**2).sum())
        tw=trustworthiness(D,Y,n_neighbors=12,metric='precomputed')

        c2=Y[-1]; d2=np.linalg.norm(Y[:len(P)]-c2,axis=1)
        d2d=cohen(d2[np.array(lab)=='HC'],d2[np.array(lab)=='PWA'])
        mets.append(dict(clip=SHORT[clip],method=name,shepard_rho=rho,stress1=stress1,
                         trustworthiness=tw,d_768=d768,d_2d=d2d))
        for (x,y),k in zip(Y,kind): coords.append(dict(clip=SHORT[clip],method=name,kind=k,x=x,y=y))
pd.DataFrame(coords).to_csv(DEST/'projection_coords.csv',index=False)
m=pd.DataFrame(mets); m.to_csv(DEST/'projection_metrics.csv',index=False)
s=m.groupby('method').agg(shepard_rho=('shepard_rho','mean'),stress1=('stress1','mean'),
      trustworthiness=('trustworthiness','mean'),d_768=('d_768','mean'),d_2d=('d_2d','mean'))

s['d_recovered_%']=100*s.d_2d/s.d_768
print(s.reindex(['PCA','Metric MDS','Isomap','t-SNE','UMAP']).round(3).to_string())
