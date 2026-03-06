#ruleorder: set_init_template_mask > set_init_template

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


#rule set_init_template_mask:
#    input:
#        mask = lambda wildcards: config['mask_template'][wildcards.channel]
#    output:
#        'results/cohort-{cohort}/iter_0/template_mask_{channel}.nii.gz'
#    log: 'logs/set_init_template_mask_{channel}_{cohort}.log'
#    group: 'init_mask'
#    shell:
#        'cp -v {input.mask} {output} &> {log}'


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

rule reg_to_template:
    input:
#        mask = lambda wildcards: [f"results/cohort-{wildcards.cohort}/iter_0/template_mask_{channel}.nii.gz" for channel in channels], 
        template = lambda wildcards: ['results/cohort-{cohort}/iter_{iteration}/template_{channel}.nii.gz'.format(
                                iteration=iteration,channel=channel,cohort=wildcards.cohort) for iteration,channel in itertools.product([int(wildcards.iteration)-1],channels)],
        target = lambda wildcards: [config['in_images'][channel] for channel in channels],
#        affine_xfm_ras = 'iter_90_atlas_p2mm/{subject}_affine_ras.txt'
    params:
        input_fixed_moving = lambda wildcards, input: [f'-i {fixed} {moving}' for fixed,moving in zip(input.template, input.target) ],
        input_moving_warped = lambda wildcards, input, output: [f'-rm {moving} {warped}' for moving,warped in zip(input.target,output.warped) ],
    output:
        warp = 'results/cohort-{cohort}/iter_{iteration}/{subject}_1Warp.nii.gz',
        invwarp = 'results/cohort-{cohort}/iter_{iteration}/{subject}_1InverseWarp.nii.gz',
        affine = 'results/cohort-{cohort}/iter_{iteration}/{subject}_0GenericAffine.mat',
        affine_xfm_ras = 'results/cohort-{cohort}/iter_{iteration}/{subject}_affine_ras.txt',
        warped = expand('results/cohort-{cohort}/iter_{iteration}/{subject}_WarpedToTemplate_{channel}.nii.gz',channel=channels,allow_missing=True),
        # rigid_tmp = temp('results/cohort-{cohort}/iter_{iteration}/rigid_tmp_{cohort}_{iteration}_{subject}.mat')
    log: 'logs/reg_to_template/cohort-{cohort}/iter_{iteration}_{subject}.log'
    threads: 1
    group: 'reg'
    container: config['singularity']['itksnap']
    resources:
        # this is assuming 1mm
        mem_mb = 16000,
        time = 30
    shell: 
        # affine refinement (final output)
        'greedy -d 3 -threads {threads} -a -dof 6 -m SSD {params.input_fixed_moving}  -o {output.affine_xfm_ras} -n 200x100x50x25 &>> {log} && '
    #        'cp {input.affine_xfm_ras} {output.affine_xfm_ras} && '
        #then deformable:
        'greedy -d 3 -threads {threads} -m SSD {params.input_fixed_moving} -it {output.affine_xfm_ras} -o {output.warp} -oinv {output.invwarp} -n 200x100x50x25 &>> {log} && '
        #then convert affine to itk format that ants uses
        'c3d_affine_tool {output.affine_xfm_ras} -oitk {output.affine} &>> {log} && '
        #and finally warp the moving image
        'greedy -d 3 -threads {threads} -rf {input.template[0]} {params.input_moving_warped} -r {output.warp} {output.affine_xfm_ras} &>> {log}'

# rule reg_to_template:
#     input:
#         template = lambda wildcards: [
#             f"results/cohort-{wildcards.cohort}/iter_{iteration}/template_{channel}.nii.gz".format(
#                 iteration=iteration, channel=channel, cohort=wildcards.cohort
#             )
#             for iteration, channel in itertools.product([int(wildcards.iteration)-1], channels)
#         ],
#         target = lambda wildcards: [config['in_images'][channel] for channel in channels],
#         # target_labels = lambda wildcards: [config['in_labels'][channel] for channel in channels],
#         # affine_xfm_ras = 'transforms/{subject}_affine_ras.mat'
#     params:
#         input_fixed_moving = lambda wildcards, input: [f'-i {fixed} {moving}' for fixed,moving in zip(input.template, input.target) ],
#         input_moving_warped = lambda wildcards, input, output: [f'-rm {moving} {warped}' for moving,warped in zip(input.target,output.warped) ],
#     output:
#         warp = 'results/cohort-{cohort}/iter_{iteration}/{subject}_1Warp.nii.gz',
#         invwarp = 'results/cohort-{cohort}/iter_{iteration}/{subject}_1InverseWarp.nii.gz',
#         affine = 'results/cohort-{cohort}/iter_{iteration}/{subject}_0GenericAffine.mat',
#         affine_xfm_ras = 'results/cohort-{cohort}/iter_{iteration}/{subject}_affine_ras.txt',
#         warped = expand('results/cohort-{cohort}/iter_{iteration}/{subject}_WarpedToTemplate_{channel}.nii.gz',channel=channels,allow_missing=True)
#     log: 'logs/reg_to_template/cohort-{cohort}/iter_{iteration}_{subject}.log'
#     threads: 1
#     group: 'reg'
#     container: config['singularity']['itksnap']
#     resources:
#         mem_mb = 16000,
#         time = 30
#     shell:
#         # affine first: Add a 4th resolution level and increase iterations
#         'greedy -d 3 -threads {threads} -a -m NCC 4x4x4 {params.input_fixed_moving} -o {output.affine_xfm_ras} -n 200x100x50x20 &> {log} && '
        
#         # then deformable: Increase iterations, add 4th level, and reduce smoothing
#         'greedy -d 3 -threads {threads} -m NCC 2x2x2 {params.input_fixed_moving} -it {output.affine_xfm_ras} -o {output.warp} -oinv {output.invwarp} -n 200x100x100x40 -s 1.2vox 0.5vox &>> {log} && '
        
#         # then convert affine to itk format that ants uses (No changes needed here)
#         'c3d_affine_tool {output.affine_xfm_ras} -oitk {output.affine} &>> {log} && '
        
#         # and finally warp the moving image (No changes needed here)
#         'greedy -d 3 -threads {threads} -rf {input.template[0]} {params.input_moving_warped} -r {output.warp} {output.affine_xfm_ras} &>> {log}'

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

#rule update_template_mask:
#    input:
#        mask = lambda wildcards: ['results/cohort-{cohort}/iter_{iteration}/template_mask_{channel}.nii.gz'.format(
#                                iteration=iteration,channel=channel,cohort=wildcards.cohort) for iteration,channel in itertools.product([int(wildcards.iteration)-1],channels)],
#        affine = 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_affine.mat',
#        invwarp = 'results/cohort-{cohort}/iter_{iteration}/shape_update/avg_inverse_warps_scaled_transformed.nii.gz',
#        ref = 'results/cohort-{cohort}/iter_{iteration}/template_{channel}.nii.gz'
#    params:
#        dim = config['ants']['dim']
#    output:
#        'results/cohort-{cohort}/iter_{iteration}/template_mask_{channel}.nii.gz'
#    log: 'logs/update_template_mask_{channel}_{cohort}_iter_{iteration}.log'
#    group: 'mask_update'
#    container: config['singularity']['ants']
#    shell:
#        '''
#        antsApplyTransforms -d {params.dim} -i {input.mask} -o {output} \
#        -r {input.ref} -t {input.invwarp} -t {input.invwarp} -t {input.invwarp} -t {input.invwarp} -t [{input.affine},1] \
#        --interpolation NearestNeighbor &> {log}
#        ''

rule warp_aux_to_template:
    input:
        aux = lambda wildcards: config['aux_images'][wildcards.aux_channel].format(subject=wildcards.subject),
        warp = 'results/cohort-{cohort}/iter_{iteration}/{subject}_1Warp.nii.gz',
        affine = 'results/cohort-{cohort}/iter_{iteration}/{subject}_0GenericAffine.mat',
        ref = lambda wildcards: f"results/cohort-{wildcards.cohort}/iter_{wildcards.iteration}/template_{channels[0]}.nii.gz"
    output:
        warped = 'results/cohort-{cohort}/iter_{iteration}/{subject}_WarpedAuxToTemplate_{aux_channel}.nii.gz'
    params:
        dim = config['ants']['dim']
    log:
        'logs/warp_aux_to_template/cohort-{cohort}/iter_{iteration}_{subject}_{aux_channel}.log'
    threads: 1
    group: 'aux_maps'
    container: config['singularity']['ants']
    resources:
        mem_mb = 8000,
        time = 15
    shell:
        r'''
        antsApplyTransforms \
          -d {params.dim} \
          --float 1 \
          --verbose 1 \
          -i {input.aux} \
          -r {input.ref} \
          -o {output.warped} \
          -n Linear \
          -t {input.warp} \
          -t {input.affine} &> {log}
        '''

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