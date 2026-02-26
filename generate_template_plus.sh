#!/bin/bash
set -e

################################################################################
#
#              QUANTITATIVE MAPS TEMPLATE GENERATION SCRIPT (Final)
#
# Steps:
# 1. Warps original maps directly into final template space (antsApplyTransforms).
# 2. Generates an average template for each map (AverageImages).
# 3. Masks the final average with the template_mask (c3d).
#
################################################################################

echo "🧠 Setting up paths and parameters..."

BASE_DIR="/nfs/khan/trainees/msalma29/amygdala_project/atlas/scripts"
QUANTITATIVE_MAPS_DIR="${BASE_DIR}/data_94T/training/quantitative_maps"

# Define all available quantitative maps
MAPS=(Chimap desc-singlepass_Chimap minIP R2starmap swi T2starmap) 

# Maps that rely on phase data (exclude 2092 for these)
PHASE_MAPS=(Chimap desc-singlepass_Chimap minIP swi)
# Maps that use magnitude only (include 2092 for these)
MAGNITUDE_MAPS=(R2starmap T2starmap)

declare -A HEMI_CONFIG

# --- Left Hemisphere Config ---
HEMI_CONFIG[L,TRANSFORM_DIR]="${BASE_DIR}/results/cohort-adult94TLabeledROILH/iter_150"
HEMI_CONFIG[L,TEMPLATE_REF]="${BASE_DIR}/results/cohort-adult94TLabeledROILH/iter_150/template_LH_T2w.nii.gz"
HEMI_CONFIG[L,OUTPUT_PARENT]="${BASE_DIR}/results/adult94TLabeledROIV2"
# Specific mask path for Left Hemisphere
HEMI_CONFIG[L,TEMPLATE_MASK]="${BASE_DIR}/results/adult94TLabeledROIV2/atlas_LH/hard_atlas/amygdala_atlas_hemi-L_majority_binmask.nii.gz"
HEMI_CONFIG[L,SUBJECTS]="2054 2070 2073 2081 2082 2087 2091 2092"
HEMI_CONFIG[L,SUBJECTS_PHASE]="2054 2070 2073 2081 2082 2087 2091"

# --- Right Hemisphere Config ---
HEMI_CONFIG[R,TRANSFORM_DIR]="${BASE_DIR}/results/cohort-adult94TLabeledROIRH/iter_150"
HEMI_CONFIG[R,TEMPLATE_REF]="${BASE_DIR}/results/cohort-adult94TLabeledROIRH/iter_150/template_RH_T2w.nii.gz"
HEMI_CONFIG[R,OUTPUT_PARENT]="${BASE_DIR}/results/adult94TLabeledROIV2"
# Specific mask path for Right Hemisphere (Assuming atlas_RH folder exists)
HEMI_CONFIG[R,TEMPLATE_MASK]="${BASE_DIR}/results/adult94TLabeledROIV2/atlas_RH/hard_atlas/amygdala_atlas_hemi-R_majority_binmask.nii.gz"
HEMI_CONFIG[R,SUBJECTS]="2054 2070 2081 2087 2091 2092"
HEMI_CONFIG[R,SUBJECTS_PHASE]="2054 2070 2081 2087 2091"

HEMISPHERES=(L R)

# echo "⚙️  Creating output directories..."
# for map in "${MAPS[@]}"; do
#   for hemi in "${HEMISPHERES[@]}"; do
#     OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_PARENT]}/${map}_template_${hemi}"
#     mkdir -p "${OUTPUT_DIR}/warped_images"
#   done
# done

# echo "🧹 Cleaning up existing intermediate files..."
# for map in "${MAPS[@]}"; do
#   for hemi in "${HEMISPHERES[@]}"; do
#     OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_PARENT]}/${map}_template_${hemi}"
#     rm -f "${OUTPUT_DIR}/warped_images/"*.nii.gz
#   done
# done

# # ------------------------------------------------------------------------------
# # STEP 1: WARPING
# # ------------------------------------------------------------------------------
# echo "🔄 Step 1/3: Warping quantitative map images directly to template..."
# for map in "${MAPS[@]}"; do
#   echo "🗂️  Processing map: ${map}"
#   IMG_DIR="${QUANTITATIVE_MAPS_DIR}/${map}"
  
#   # Check if this map uses phase (exclude 2092) or magnitude only (include 2092)
#   IS_PHASE_MAP=false
#   for phase_map in "${PHASE_MAPS[@]}"; do
#     if [ "$map" == "$phase_map" ]; then
#       IS_PHASE_MAP=true
#       break
#     fi
#   done
  
#   for hemi in "${HEMISPHERES[@]}"; do
#     OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_PARENT]}/${map}_template_${hemi}"
#     TRANSFORM_DIR="${HEMI_CONFIG[$hemi,TRANSFORM_DIR]}"
#     TEMPLATE_REF="${HEMI_CONFIG[$hemi,TEMPLATE_REF]}"
    
#     if [ "$IS_PHASE_MAP" = true ]; then
#       SUBJECTS_STR="${HEMI_CONFIG[$hemi,SUBJECTS_PHASE]}"
#     else
#       SUBJECTS_STR="${HEMI_CONFIG[$hemi,SUBJECTS]}"
#     fi
#     SUBJECTS_ARRAY=($SUBJECTS_STR)
    
#     for sub in "${SUBJECTS_ARRAY[@]}"; do
#       INPUT_MAP="${IMG_DIR}/sub-${sub}_ses-000_hemi-${hemi}.nii.gz"
#       OUTPUT_WARPED_IMG="${OUTPUT_DIR}/warped_images/sub-${sub}_hemi-${hemi}_warped.nii.gz"
#       AFFINE_TRANSFORM="${TRANSFORM_DIR}/sub-${sub}_0GenericAffine.mat"
#       WARP_TRANSFORM="${TRANSFORM_DIR}/sub-${sub}_1Warp.nii.gz"

#       if [ -f "$INPUT_MAP" ]; then
#         if [ ! -f "$OUTPUT_WARPED_IMG" ]; then
#           echo "    -> Warping ${map} (Sub: ${sub}, Hemi: ${hemi})"
#           antsApplyTransforms \
#             -d 3 \
#             --verbose 0 \
#             -i "$INPUT_MAP" \
#             -r "$TEMPLATE_REF" \
#             -o "$OUTPUT_WARPED_IMG" \
#             -n Linear \
#             -t "$WARP_TRANSFORM" \
#             -t "$AFFINE_TRANSFORM"
#         fi
#       else
#         echo "    -> ⚠️ WARNING: Cannot find ${map}: $INPUT_MAP. Skipping."
#       fi
#     done
#   done
# done

# ------------------------------------------------------------------------------
# STEP 2 & 3: AVERAGING & MASKING
# ------------------------------------------------------------------------------
echo "🗳️ Step 2 & 3: Generating averages and applying final masks..."
for map in "${MAPS[@]}"; do
  echo "📊 Processing map: ${map}"
  for hemi in "${HEMISPHERES[@]}"; do
    OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_PARENT]}/${map}_template_${hemi}"
    TEMPLATE_MASK="${HEMI_CONFIG[$hemi,TEMPLATE_MASK]}"
    WARPED_IMAGES_HEMI=($(find "${OUTPUT_DIR}/warped_images/" -name "*_hemi-${hemi}_warped.nii.gz"))
    
    if [ ${#WARPED_IMAGES_HEMI[@]} -gt 0 ]; then
      
      # # 2. Average
      AVG_RAW="${OUTPUT_DIR}/template_${map}_hemi-${hemi}_average.nii.gz"
      # echo "  -> Averaging ${#WARPED_IMAGES_HEMI[@]} images for Hemisphere ${hemi}..."
      # AverageImages 3 "$AVG_RAW" 0 "${WARPED_IMAGES_HEMI[@]}"
      
      # 3. Mask
      AVG_FINAL="${OUTPUT_DIR}/template_${map}_hemi-${hemi}_average_masked.nii.gz"
      
      if [ -f "$TEMPLATE_MASK" ]; then
        echo "  -> Applying mask to average: $(basename "$TEMPLATE_MASK")"
        c3d "$AVG_RAW" "$TEMPLATE_MASK" -multiply -o "$AVG_FINAL"
      else
        echo "  -> ⚠️ ERROR: Mask not found at $TEMPLATE_MASK. Saving raw average as final."
        cp "$AVG_RAW" "$AVG_FINAL"
      fi
      
    else
      echo "  -> ⚠️ WARNING: No warped images found for Hemisphere ${hemi}."
    fi
  done
done

echo "✅ All done!"
for map in "${MAPS[@]}"; do
  echo ""
  echo "📁 Output files for map: ${map}"
  for hemi in "${HEMISPHERES[@]}"; do
    OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_PARENT]}/${map}_template_${hemi}"
    echo "   Hemisphere ${hemi}:"
    echo "     • Final Masked Template: ${OUTPUT_DIR}/template_${map}_hemi-${hemi}_average_masked.nii.gz"
  done
done