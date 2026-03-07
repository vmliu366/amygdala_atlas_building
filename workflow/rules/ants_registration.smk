import os
import itertools
############################################
# helper functions
############################################

def get_dseg_path(wildcards):
    return config['in_dseg'][wildcards.channel].format(subject=wildcards.subject)

def get_lut_path(wildcards):
    return config['in_lut'][wildcards.channel].format(subject=wildcards.subject)


############################################
# Main
############################################

rule gen_init_avg_template:
    input: lambda wildcards: expand(config['in_images'][wildcards.channel],subject=subjects[wildcards.cohort])
    output: 'results/cohort-{cohort}/iter_0/init/init_avg_template_{channel}.nii.gz'
    params:
        dim = config['ants']['dim'],
        use_n4 = '2'
    log: 'logs/gen_init_avg_template_{channel}_{cohort}.log'
    # container: config['singularity']['ants']
    group: 'init_template'
    shell:
        'greedy_template_average -d {params.dim} -i {input} {output} &> {log}'
        # AverageImages {params.dim} {output} {params.use_n4} {input} &> {log}


rule get_existing_template:
    input: lambda wildcards: config['init_template'][wildcards.channel]
    output: 'results/cohort-{cohort}/iter_0/init/existing_template_{channel}.nii.gz'
    log: 'logs/get_existing_template_{channel}_{cohort}.log'
    group: 'init_template'
    shell: 'cp -v {input} {output} &> {log}'


rule gen_init_avg_aux_template:
    input:
        lambda wildcards: expand(
            config['aux_images'][wildcards.aux_channel],
            subject=subjects[wildcards.cohort]
        )
    output:
        'results/cohort-{cohort}/iter_0/init/init_avg_aux_template_{aux_channel}.nii.gz'
    params:
        dim=config['ants']['dim']
    log:
        'logs/gen_init_avg_aux_template_{aux_channel}_{cohort}.log'
    group:
        'init_template'
    shell:
        'greedy_template_average -d {params.dim} -i {input} {output} &> {log}'

rule set_init_template:
    input:
        'results/cohort-{cohort}/iter_0/init/init_avg_template_{channel}.nii.gz' if config['init_template'] == None else 'results/cohort-{cohort}/iter_0/init/existing_template_{channel}.nii.gz'
    params: 
        cmd = lambda wildcards, input, output:
                'ResampleImageBySpacing {dim} {input} {output} {vox_dims}'.format(
                        dim = config['ants']['dim'], input = input, output = output,
                        vox_dims=' '.join([str(d) for d in config['resample_vox_dims']]))
                     if config['resample_init_template'] else f"cp -v {input} {output}"
    output: 'results/cohort-{cohort}/iter_0/template_{channel}.nii.gz'
    log: 'logs/set_init_template_{channel}_{cohort}.log'
    group: 'init_template'
    container: config['singularity']['ants']
    shell: '{params.cmd} &> {log}'


rule set_init_aux_template:
    input:
        'results/cohort-{cohort}/iter_0/init/init_avg_aux_template_{aux_channel}.nii.gz'
    output:
        'results/cohort-{cohort}/iter_0/aux_template_{aux_channel}.nii.gz'
    log:
        'logs/set_init_aux_template_{aux_channel}_{cohort}.log'
    group:
        'init_template'
    shell:
        'cp -v {input} {output} &> {log}'
        
rule reg_to_template:
    input:
        fixed_t1=lambda wc: f"results/cohort-{wc.cohort}/iter_{int(wc.iteration)-1}/template_T1w.nii.gz",
        moving_t1=lambda wc: config['in_images']['T1w'].format(subject=wc.subject),
        fixed_r1=lambda wc: f"results/cohort-{wc.cohort}/iter_{int(wc.iteration)-1}/aux_template_LH_R1map.nii.gz",
        moving_r1=lambda wc: config['aux_images']['LH_R1map'].format(subject=wc.subject),
    output:
        warp='results/cohort-{cohort}/iter_{iteration}/{subject}_1Warp.nii.gz',
        invwarp='results/cohort-{cohort}/iter_{iteration}/{subject}_1InverseWarp.nii.gz',
        affine='results/cohort-{cohort}/iter_{iteration}/{subject}_0GenericAffine.mat'
    log:
        'logs/reg_to_template/cohort-{cohort}/iter_{iteration}_{subject}.log'
    threads: 4
    group: 'reg'
    container: config['singularity']['ants']
    resources:
        mem_mb=24000,
        time=120
    params:
        prefix=lambda wc: f"results/cohort-{wc.cohort}/iter_{wc.iteration}/{wc.subject}_"
    shell:
        r"""
        antsRegistration \
          -d 3 \
          --float 1 \
          --verbose 1 \
          --collapse-output-transforms 1 \
          -o [{params.prefix}] \
          -r [{input.fixed_t1},{input.moving_t1},1] \
          \
          -t Rigid[0.1] \
          -m MI[{input.fixed_t1},{input.moving_t1},1,32,Regular,0.25] \
          -c [1000x500x250x0,1e-6,10] \
          -s 4x2x1x0vox \
          -f 8x4x2x1 \
          \
          -t Affine[0.1] \
          -m Mattes[{input.fixed_t1},{input.moving_t1},1,32,Regular,0.25] \
          -c [1000x500x250x0,1e-6,10] \
          -s 4x2x1x0vox \
          -f 8x4x2x1 \
          \
          -t SyN[0.1,3,0] \
          -m CC[{input.fixed_t1},{input.moving_t1},1,4] \
          -m CC[{input.fixed_r1},{input.moving_r1},0.5,4] \
          -c [200x100x50x20,1e-7,10] \
          -s 3x2x1x0vox \
          -f 6x4x2x1 \
          &> {log}
        """

rule apply_transform:
    input:
        warp='results/cohort-{cohort}/iter_{iteration}/{subject}_1Warp.nii.gz',
        affine='results/cohort-{cohort}/iter_{iteration}/{subject}_0GenericAffine.mat',
        t1=lambda wc: config['in_images']['T1w'].format(subject=wc.subject),
        r1=lambda wc: config['aux_images']['LH_R1map'].format(subject=wc.subject),
        dseg=lambda wc: config['in_dseg']['T1w'].format(subject=wc.subject),
        lut=lambda wc: config['in_lut']['T1w'].format(subject=wc.subject),
        ref_t1=lambda wc: f"results/cohort-{wc.cohort}/iter_{int(wc.iteration)-1}/template_T1w.nii.gz",
        ref_r1=lambda wc: f"results/cohort-{wc.cohort}/iter_{int(wc.iteration)-1}/aux_template_LH_R1map.nii.gz",
    output:
        warped_t1='results/cohort-{cohort}/iter_{iteration}/{subject}_WarpedToTemplate_T1w.nii.gz',
        warped_r1='results/cohort-{cohort}/iter_{iteration}/{subject}_WarpedAuxToTemplate_LH_R1map.nii.gz',
        warped_dseg='results/cohort-{cohort}/iter_{iteration}/warped_dseg/{subject}_T1w_dseg.nii.gz',
        lut='results/cohort-{cohort}/iter_{iteration}/warped_dseg/{subject}_T1w_LUT.txt'
    params:
        dim=config['ants']['dim']
    log:
        'logs/apply_transform/cohort-{cohort}/iter_{iteration}_{subject}.log'
    threads: 4
    group:
        'reg'
    container:
        config['singularity']['ants']
    resources:
        mem_mb=16000,
        time=60
    shell:
        r"""
        mkdir -p $(dirname {output.warped_dseg})

        antsApplyTransforms \
          -d {params.dim} \
          --float 1 \
          --verbose 1 \
          -i {input.t1} \
          -r {input.ref_t1} \
          -o {output.warped_t1} \
          -n Linear \
          -t {input.warp} \
          -t {input.affine} \
          &> {log}

        antsApplyTransforms \
          -d {params.dim} \
          --float 1 \
          --verbose 1 \
          -i {input.r1} \
          -r {input.ref_r1} \
          -o {output.warped_r1} \
          -n Linear \
          -t {input.warp} \
          -t {input.affine} \
          &>> {log}

        antsApplyTransforms \
          -d {params.dim} \
          --float 1 \
          --verbose 1 \
          -i {input.dseg} \
          -r {input.ref_t1} \
          -o {output.warped_dseg} \
          -n GenericLabel \
          -t {input.warp} \
          -t {input.affine} \
          &>> {log}

        cp {input.lut} {output.lut}
        """

rule avg_warped:
    input: 
        targets = lambda wildcards: expand('results/cohort-{cohort}/iter_{iteration}/{subject}_WarpedToTemplate_{channel}.nii.gz',subject=subjects[wildcards.cohort],iteration=wildcards.iteration,channel=wildcards.channel,cohort=wildcards.cohort,allow_missing=True)
    params:
        dim = config['ants']['dim'],
        use_n4 = '0'  # changed to no normalization
    output: 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_warped_{channel}.nii.gz'
    group: 'shape_update'
    log: 'logs/avg_warped/cohort-{cohort}/iter_{iteration}_{channel}.log'
    # container: config['singularity']['ants']
    shell:
        'greedy_template_average -d {params.dim} -i {input} {output} &> {log}'
        # AverageImages {params.dim} {output} {params.use_n4} {input} &> {log}
       
rule avg_inverse_warps:
    input:
        warps = lambda wildcards: expand('results/cohort-{cohort}/iter_{iteration}/{subject}_1Warp.nii.gz',subject=subjects[wildcards.cohort],iteration=wildcards.iteration,cohort=wildcards.cohort,allow_missing=True),
    params:
        dim = config['ants']['dim'],
        use_n4 = '0'
    output: 
        invwarp = 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_inverse_warps.nii.gz'
    group: 'shape_update'
    log: 'logs/avg_inverse_warps/cohort-{cohort}/iter_{iteration}.log'
    # container: config['singularity']['ants']
    shell:
        'greedy_template_average -d {params.dim} -i {input} {output} &> {log}'
        # AverageImages {params.dim} {output} {params.use_n4} {input} &> {log}
         
rule scale_by_gradient_step:
    input: 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_inverse_warps.nii.gz'
    params:
        dim = config['ants']['dim'],
        gradient_step = '-{gradient_step}'.format(gradient_step = config['ants']['shape_update']['gradient_step'])
    output: 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_inverse_warps_scaled.nii.gz'
    group: 'shape_update'
    log: 'logs/scale_by_gradient_step/cohort-{cohort}/iter_{iteration}.log'
    container: config['singularity']['ants']
    shell:
        'MultiplyImages {params.dim} {input} {params.gradient_step} {output} &> {log}' 

rule avg_affine_transforms:
    input:
        affine = lambda wildcards: expand('results/cohort-{cohort}/iter_{iteration}/{subject}_0GenericAffine.mat',subject=subjects[wildcards.cohort],iteration=wildcards.iteration,cohort=wildcards.cohort,allow_missing=True),
    params:
        dim = config['ants']['dim']
    output:
        affine = 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_affine.mat'
    group: 'shape_update'
    log: 'logs/avg_affine_transforms/cohort-{cohort}/iter_{iteration}.log'
    container: config['singularity']['ants']
    shell:
        'AverageAffineTransformNoRigid {params.dim} {output} {input} &> {log}'

rule transform_inverse_warp:
    input:
        affine = 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_affine.mat',
        invwarp = 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_inverse_warps_scaled.nii.gz',
        ref = lambda wildcards: 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_warped_{channel}.nii.gz'.format(iteration=wildcards.iteration,channel=channels[0],cohort=wildcards.cohort) #just use 1st channel as ref
    params:
        dim = '-d {dim}'.format(dim = config['ants']['dim'])
    output: 
        invwarp = 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_inverse_warps_scaled_transformed.nii.gz'
    group: 'shape_update'
    log: 'logs/transform_inverse_warp/cohort-{cohort}/iter_{iteration}.log'
    container: config['singularity']['ants']
    shell:
        'antsApplyTransforms {params.dim} -e vector -i {input.invwarp} -o {output} -t [{input.affine},1] -r {input.ref} --verbose 1 &> {log}'

rule apply_template_update:
    input:
        template =  'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_warped_{channel}.nii.gz',
        affine = 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_affine.mat',
        invwarp = 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_inverse_warps_scaled_transformed.nii.gz'
    params:
        dim = '-d {dim}'.format(dim = config['ants']['dim'])
    output:
        template =  'results/cohort-{cohort}/iter_{iteration}/template_{channel}.nii.gz'
    log: 'logs/apply_template_update/cohort-{cohort}/iter_{iteration}_{channel}_{cohort}.log'
    group: 'shape_update'
    container: config['singularity']['ants']
    shell:
        'antsApplyTransforms {params.dim} --float 1 --verbose 1 -i {input.template} -o {output.template} -t [{input.affine},1] '
        ' -t {input.invwarp} -t {input.invwarp} -t {input.invwarp} -t {input.invwarp} -r {input.template} &> {log}' #apply warp 4 times

rule avg_aux_warped:
    input:
        targets=lambda wildcards: expand(
            'results/cohort-{cohort}/iter_{iteration}/{subject}_WarpedAuxToTemplate_{aux_channel}.nii.gz',
            subject=subjects[wildcards.cohort],
            iteration=wildcards.iteration,
            aux_channel=wildcards.aux_channel,
            cohort=wildcards.cohort
        )
    params:
        dim = config['ants']['dim']
    output:
        'results/cohort-{cohort}/iter_{iteration}/aux_template_{aux_channel}.nii.gz'
    log:
        'logs/avg_aux_warped/cohort-{cohort}/iter_{iteration}_{aux_channel}.log'
    group: 'aux_maps'
    container: config['singularity']['ants']
    shell:
        r'''
        AverageImages {params.dim} {output} 0 {input.targets} &> {log}
        '''

rule calc_centroid:
    input:
        dseg="results/cohort-{cohort}/iter_{iteration}/warped_dseg/{subject}_T1w_dseg.nii.gz",
        lut="results/cohort-{cohort}/iter_{iteration}/warped_dseg/{subject}_T1w_LUT.txt"
    output:
        csv="results/cohort-{cohort}/iter_{iteration}/prob_atlas/{subject}_iter{iteration}_centroids.csv"
    params:
        participant=lambda wc: wc.subject
    script:
        "../scripts/calc_centroid.py"

rule make_label_binary_mask:
    input:
        dseg="results/cohort-{cohort}/iter_{iteration}/warped_dseg/{subject}_{channel}_dseg.nii.gz"
    output:
        mask="results/cohort-{cohort}/iter_{iteration}/prob_atlas/tmp/{subject}_{channel}_{label}.nii.gz"
    shell:
        """
        mkdir -p $(dirname {output})
        c3d {input.dseg} -thresh {wildcards.label} {wildcards.label} 1 0 -o {output.mask}
        """

rule make_prob_atlas:
    input:
        masks=lambda wc: expand(
            "results/cohort-{cohort}/iter_{iteration}/prob_atlas/tmp/{subject}_{channel}_{label}.nii.gz",
            cohort=wc.cohort,
            iteration=wc.iteration,
            subject=subjects[wc.cohort],
            channel=wc.channel,
            label=wc.label
        )
    output:
        prob="results/cohort-{cohort}/iter_{iteration}/prob_atlas/{channel}_label-{label}_prob.nii.gz"
    shell:
        """
        mkdir -p $(dirname {output.prob})
        AverageImages 3 {output.prob} 0 {input.masks}
        """

rule assemble_prob_atlas:
    input:
        probs=lambda wc: expand(
            "results/cohort-{cohort}/iter_{iteration}/prob_atlas/{channel}_label-{label}_prob.nii.gz",
            cohort=wc.cohort,
            iteration=wc.iteration,
            channel=wc.channel,
            label=config["atlas_labels"]
        )
    output:
        atlas="results/cohort-{cohort}/iter_{iteration}/prob_atlas/prob_atlas_{channel}_4D.nii.gz"
    shell:
        """
        mkdir -p $(dirname {output.atlas})
        ImageMath 4 {output.atlas} TimeSeriesAssemble 1 {input.probs}
        """

rule atlas_binarize_prob:
    input:
        prob="results/cohort-{cohort}/iter_{iteration}/prob_atlas/{channel}_label-{label}_prob.nii.gz"
    output:
        mask="results/cohort-{cohort}/iter_{iteration}/prob_atlas/binary/{channel}_{label}.nii.gz"
    shell:
        """
        mkdir -p $(dirname {output.mask})
        c3d {input.prob} -thresh 0.000001 inf 1 0 -o {output.mask}
        """

rule atlas_mask_to_label:
    input:
        mask="results/cohort-{cohort}/iter_{iteration}/prob_atlas/binary/{channel}_{label}.nii.gz"
    output:
        dseg="results/cohort-{cohort}/iter_{iteration}/prob_atlas/label/{channel}_{label}.nii.gz"
    shell:
        """
        mkdir -p $(dirname {output.dseg})
        ImageMath 3 {output.dseg} m {input.mask} {wildcards.label}
        """

rule calc_centroid_atlas:
    input:
        dseg="results/cohort-{cohort}/iter_{iteration}/prob_atlas/label/{channel}_{label}.nii.gz",
        lut=lambda wc:
        config["in_lut"][wc.channel].format(subject=subjects[wc.cohort][0])
    output:
        csv="results/cohort-{cohort}/iter_{iteration}/prob_atlas/centroids/{channel}_{label}.csv"
    params:
        participant="atlas"
    script:
        "../scripts/calc_centroid.py"

rule calc_euclidean_distance:
    input:
        subj_csv="results/cohort-{cohort}/iter_{iteration}/prob_atlas/{subject}_iter{iteration}_centroids.csv",
        atlas_csv=lambda wc: expand(
            "results/cohort-{cohort}/iter_{iteration}/prob_atlas/centroids/{channel}_{label}.csv",
            cohort=wc.cohort,
            iteration=wc.iteration,
            channel=list(config["in_dseg"].keys()),
            label=config["atlas_labels"]
        )
    output:
        csv="results/cohort-{cohort}/iter_{iteration}/prob_atlas/{subject}_iter{iteration}_euclidean_distance.csv"
    script:
        "../scripts/calc_euclidean_distance.py"
