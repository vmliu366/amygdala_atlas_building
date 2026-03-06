import numpy as np
import nibabel as nib
import pandas as pd
from pathlib import Path
Path(snakemake.output.csv).parent.mkdir(parents=True, exist_ok=True)

dseg = nib.load(snakemake.input.dseg)
data = dseg.get_fdata()
aff = dseg.affine

lut = pd.read_csv(
    snakemake.input.lut,
    sep=r"\s+",
    header=None,
    names=["label", "roi"]
)

rows = []

key = "centroid_atlas" if snakemake.params.participant == "atlas" else "centroid_subj"

for _, r in lut.iterrows():
    label = int(r.label)
    roi = r.roi

    vox = np.argwhere(data == label)

    if vox.size == 0:
        centroid = None
    else:
        xyz = nib.affines.apply_affine(aff, vox)
        centroid = xyz.mean(axis=0).tolist()

    row = {
        "roi": roi,
        key: centroid
    }

    if snakemake.params.participant != "atlas":
        row["participant"] = snakemake.params.participant

    rows.append(row)

pd.DataFrame(rows).to_csv(snakemake.output.csv, index=False)