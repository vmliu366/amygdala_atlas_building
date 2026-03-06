import pandas as pd
import ast
import math
from pathlib import Path
Path(snakemake.output.csv).parent.mkdir(parents=True, exist_ok=True)

df=pd.read_csv(snakemake.input.subj_csv)

atlas=pd.concat([pd.read_csv(x) for x in snakemake.input.atlas_csv])

df=df.merge(atlas,on="roi")

def parse(v):

    if isinstance(v,str):
        return ast.literal_eval(v)

    return None

def dist(a,b):

    if a is None or b is None:
        return None

    return math.sqrt(sum((x-y)**2 for x,y in zip(a,b)))

df["centroid_subj"]=df["centroid_subj"].apply(parse)
df["centroid_atlas"]=df["centroid_atlas"].apply(parse)

df["euclidean_distance_mm"]=[
    dist(a,b)
    for a,b in zip(df.centroid_subj,df.centroid_atlas)
]

df.to_csv(snakemake.output.csv,index=False)