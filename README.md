# amygdala_atlas_building

This repository contains scripts and workflows for generating a high-resolution amygdala atlas and quantitative map templates from 9.4T MRI scans. 

## Snakemake Pipeline Configuration & Execution

The heaviest part of the pipeline—which generates iterative ANTs templates and handles the large-scale image registration across cohorts—is managed by Snakemake.

### 1. Preparing the Data and Configuration

Before running the workflow, you must adjust the configuration files located in the `config/` directory:

1.  **`config/config.yml`**
    This is the core configuration file. You will need to update the following crucial paths specific to your environment:
    *   **Input Data:** Check `in_images` (e.g., `LH_T2w`). It expects a template string like `/path/to/data/{subject}_ses-000_hemi-L.nii.gz` indicating where your raw input NIfTI files live.
    *   **Participants TSV:** Ensure `participants_tsv` maps back to your subject list TSV (default is `'config/participants_adult_94T.tsv'`).
    *   **Initialization:** Update `init_template` paths to point to your chosen initial boot-strapping template (e.g., a specific subject like `sub-2092`).
    *   **Singularity Paths:** Update the paths under the `singularity:` block so Snakemake points to the correct `.sif` containers for `ants`, `itksnap`, and `prepdwi`.

2.  **`config/participants_adult_94T.tsv`**
    This TSV file controls which subjects are processed in the cohort. It must contain a `participant_id` column where each row specifies a subject using the `sub-XXXX` format (e.g., `sub-2054`, `sub-2070`).

### 2. Running the Pipeline

Once your data paths are properly configured and your TSV file is updated, you can run the pipeline from the root directory of this repository (where the `workflow` and `config` directories reside).

To execute the pipeline using Snakemake:

```bash
# Perform a dry-run to ensure all paths and rules resolve correctly
snakemake -n

# Run the pipeline allowing Snakemake to use all available cores
snakemake --cores all
```

By default, the workflow will run the number of iterations specified in `config.yml` (`max_iters: 10`). You can also override configuration variables via the command line (for example, targeting a specific iteration or cohort):

```bash
snakemake --cores all --config run_iter=10
```

---

## Standalone Post-Processing Scripts

After the Snakemake pipeline has converged and produced the final ANTs transformations and base templates, use the following standalone scripts to compile the atlases and extract statistics:


*   **`generate_atlas.sh`**
    The central script for constructing both hard and probabilistic atlases of the amygdala.
    *   **Preprocessing**: Refines raw label maps by retaining specific subnuclei labels (1001-1009) and remapping them to a continuous sequence (1-9) using `c3d`.
    *   **Template Warping**: Applies pre-calculated ANTs transformations (inverse warp and affine) to move the subject-specific labels into the final common template space.
    *   **Hard Atlas Generation**: Fuses warped labels from multiple subjects into a single "hard" atlas using different voting strategies (e.g., strict majority voting or a custom 25% threshold).
    *   **Probabilistic Maps**: Creates continuous probability maps (0-1) for each sub-nucleus and assembles them into a 4D NIfTI volume representing the probabilistic atlas.

*   **`generate_template_plus.sh`**
    Responsible for generating group-average templates for various quantitative MRI modalities (e.g., Chimap, R2starmap, swi, T2starmap).
    *   Warps individual subject quantitative maps directly into the final template space.
    *   Averages these datasets across subjects (while properly separating phase and magnitude maps across subjects where data might be missing).
    *   Masks the resulting average templates using the binary mask derived from the hard majority-vote atlas to constrain the data to the amygdala region.

*   **`extract_atlas_stats.sh`**
    Automates the extraction of structural and intensity statistics from the generated templates.
    *   Iterates over the quantitative map templates for both hemispheres.
    *   Uses `c3d -lstat` to calculate the volume (mm³), voxel count, mean, standard deviation, minimum, and maximum intensity values for every individual label within the amygdala atlas.
    *   Outputs the aggregated results into a structured CSV file (`amygdala_atlas_statistics.csv`) for downstream statistical analysis.

*   **`crop_by_com.py`**
    A Python utility script that accurately crops a large NIfTI image to the bounding box of a much smaller region of interest (like an amygdala mask).
    *   Instead of blindly slicing data arrays, it calculates the corners of a pre-cropped binary mask in world coordinates using its affine matrix.
    *   It then projects these world coordinates back into the original large image's voxel space to determine the precise bounding box.
    *   Generates a tightly cropped output image while completely preserving all spatial metadata, qform/sform codes, and zoom headers.

### Snakemake Pipeline

*   **`workflow/`** and **`config/`**
    These directories contain a Snakemake workflow designed to systematically orchestrate the heavier, iterative tasks of the atlas building process (such as running multi-stage ANTs alignments to generate the intermediate templates and affine/warp transforms used by the `.sh` scripts above). They define the environment dependencies, job execution rules, and parameter configurations.