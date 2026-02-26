#!/bin/bash
# Exit script if any command fails
set -e

################################################################################
#
#                      ATLAS GENERATION SCRIPT
#
# This script performs the following steps:
# 1. Retains specific labels (1001-1009) and remaps them to 1-9.
# 2. Warps the remapped labels into the final template space using ANTs.
# 3. Generates a "hard" atlas using majority voting (LabelStats).
# 4. Generates a probabilistic atlas for each label.
# 5. Creates a 4D NIfTI file containing all probabilistic atlas labels.
#
################################################################################

# --- 1. CONFIGURATION ---
# Set the base directory and define paths for inputs and outputs.

echo "🧠 Setting up paths and parameters..."

BASE_DIR="/nfs/khan/trainees/msalma29/amygdala_project/atlas/scripts"
LABEL_DIR="${BASE_DIR}/data_94T/training/smoothed_labels"

# Hemisphere-specific configurations
declare -A HEMI_CONFIG
HEMI_CONFIG[L,TRANSFORM_DIR]="${BASE_DIR}/results/cohort-adult94TLabeledROILH/iter_150"
HEMI_CONFIG[L,TEMPLATE_REF]="${BASE_DIR}/results/cohort-adult94TLabeledROILH/iter_150/template_LH_T2w.nii.gz"
HEMI_CONFIG[L,OUTPUT_DIR]="${BASE_DIR}/results/adult94TLabeledROI/atlas_LH"
HEMI_CONFIG[L,SUBJECTS]="2054 2070 2073 2081 2082 2087 2091 2092"

HEMI_CONFIG[R,TRANSFORM_DIR]="${BASE_DIR}/results/cohort-adult94TLabeledROIRH/iter_150"
HEMI_CONFIG[R,TEMPLATE_REF]="${BASE_DIR}/results/cohort-adult94TLabeledROIRH/iter_150/template_RH_T2w.nii.gz"
HEMI_CONFIG[R,OUTPUT_DIR]="${BASE_DIR}/results/adult94TLabeledROI/atlas_RH"
HEMI_CONFIG[R,SUBJECTS]="2054 2070 2081 2087 2091 2092"

# Process both hemispheres
HEMISPHERES=(L R)

# --- 2. SETUP ---
# Create the directory structure for the outputs.

echo "⚙️  Creating output directories..."
for hemi in "${HEMISPHERES[@]}"; do
  OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_DIR]}"
  mkdir -p "${OUTPUT_DIR}/preprocessed_labels"
  mkdir -p "${OUTPUT_DIR}/warped_labels"
  mkdir -p "${OUTPUT_DIR}/prob_atlas/temp_binary_masks"
  mkdir -p "${OUTPUT_DIR}/hard_atlas"
done

# Clean up any existing warped labels to start fresh
echo "🧹 Cleaning up existing warped labels..."
for hemi in "${HEMISPHERES[@]}"; do
  OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_DIR]}"
  rm -f "${OUTPUT_DIR}/warped_labels/"*.nii.gz
done

# --- 3. PREPROCESS LABELS (RETAIN AND REMAP VALUES) ---
# For each subject label file, retain labels 1001-1009 and then remap them to 1-9.

echo "🎨 Step 1/4: Retaining and remapping label values..."
for hemi in "${HEMISPHERES[@]}"; do
  OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_DIR]}"
  SUBJECTS_STR="${HEMI_CONFIG[$hemi,SUBJECTS]}"
  SUBJECTS_ARRAY=($SUBJECTS_STR)
  
  echo "  -> Processing Hemisphere ${hemi}"
  for sub in "${SUBJECTS_ARRAY[@]}"; do
    INPUT_LABEL="${LABEL_DIR}/sub-${sub}_ses-000_hemi-${hemi}.nii.gz"
    OUTPUT_LABEL="${OUTPUT_DIR}/preprocessed_labels/sub-${sub}_hemi-${hemi}_labels_remapped.nii.gz"

    if [ -f "$INPUT_LABEL" ]; then
      echo "    -> Processing Subject ${sub}, Hemisphere ${hemi}"
      # UPDATED COMMAND: Chain retain and replace operations for efficiency
      c3d "$INPUT_LABEL" \
        -retain-labels 1 2 3 4 5 6 7 9 \
        -replace 1 1 2 2 3 3 4 4 5 5 6 6 7 7 9 8 \
        -o "$OUTPUT_LABEL"
    fi
  done
done

# --- 4. WARP LABELS TO TEMPLATE SPACE ---
# Apply the final transforms to the remapped labels.

echo "🔄 Step 2/4: Warping remapped labels to template space..."
for hemi in "${HEMISPHERES[@]}"; do
  OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_DIR]}"
  TRANSFORM_DIR="${HEMI_CONFIG[$hemi,TRANSFORM_DIR]}"
  TEMPLATE_REF="${HEMI_CONFIG[$hemi,TEMPLATE_REF]}"
  SUBJECTS_STR="${HEMI_CONFIG[$hemi,SUBJECTS]}"
  SUBJECTS_ARRAY=($SUBJECTS_STR)
  
  echo "  -> Processing Hemisphere ${hemi}"
  for sub in "${SUBJECTS_ARRAY[@]}"; do
    INPUT_REMAPPED_LABEL="${OUTPUT_DIR}/preprocessed_labels/sub-${sub}_hemi-${hemi}_labels_remapped.nii.gz"
    
    if [ -f "$INPUT_REMAPPED_LABEL" ]; then
      OUTPUT_WARPED_LABEL="${OUTPUT_DIR}/warped_labels/sub-${sub}_hemi-${hemi}_labels_warped.nii.gz"
      AFFINE_TRANSFORM="${TRANSFORM_DIR}/sub-${sub}_0GenericAffine.mat"
      WARP_TRANSFORM="${TRANSFORM_DIR}/sub-${sub}_1Warp.nii.gz"

      echo "    -> Warping Subject ${sub}, Hemisphere ${hemi}"
      echo "      Input label: $INPUT_REMAPPED_LABEL"
      echo "      Template ref: $TEMPLATE_REF"
      echo "      Affine: $AFFINE_TRANSFORM"
      echo "      warp: $WARP_TRANSFORM"
      
      # CORRECTED: Use proper atlas generation approach
      # Warp labels FROM subject space TO template space using inverse transforms
      # Order: inverse warp first, then affine (opposite of registration order)
      antsApplyTransforms \
        -d 3 \
        --verbose 1 \
        -i "$INPUT_REMAPPED_LABEL" \
        -r "$TEMPLATE_REF" \
        -o "$OUTPUT_WARPED_LABEL" \
        -n GenericLabel \
        -t "$WARP_TRANSFORM" \
        -t "$AFFINE_TRANSFORM"
      
      # # Post-process: Apply morphological operations to clean up labels
      # TEMP_CLEANED="${OUTPUT_DIR}/warped_labels/temp_cleaned_sub-${sub}_hemi-${hemi}.nii.gz"
      # c3d "$OUTPUT_WARPED_LABEL" -dilate 1 1x1x1vox -erode 1 1x1x1vox -o "$TEMP_CLEANED"
      # mv "$TEMP_CLEANED" "$OUTPUT_WARPED_LABEL"
    fi
  done
done

# --- 5. GENERATE HARD ATLAS (MAJORITY VOTE) ---
# Fuse the warped labels using majority voting.

echo "🗳️ Step 3/5: Generating hard atlas via majority vote..."
for hemi in "${HEMISPHERES[@]}"; do
  OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_DIR]}"
  WARPED_LABELS_HEMI=($(find "${OUTPUT_DIR}/warped_labels/" -name "*_hemi-${hemi}_labels_warped.nii.gz"))
  
  if [ ${#WARPED_LABELS_HEMI[@]} -gt 0 ]; then
    echo "  -> Fusing labels for Hemisphere ${hemi}"
    
    # Method 1: Max voting (any vote) - preserves all labels including small ones
    ImageMath 3 "${OUTPUT_DIR}/hard_atlas/amygdala_atlas_hemi-${hemi}_max.nii.gz" \
      max "${WARPED_LABELS_HEMI[@]}"
    
    # Method 2: Majority voting - requires >50% overlap
    ImageMath 3 "${OUTPUT_DIR}/hard_atlas/amygdala_atlas_hemi-${hemi}_majority.nii.gz" \
      MajorityVoting "${WARPED_LABELS_HEMI[@]}"
    
    # # Method 3: STAPLE - accounts for individual subject reliability
    # ImageMath 3 "${OUTPUT_DIR}/hard_atlas/amygdala_atlas_hemi-${hemi}_staple.nii.gz" \
    #   STAPLE 1 "${WARPED_LABELS_HEMI[@]}"
    
    # Method 4: Custom 25% threshold voting - balanced approach
    echo "    -> Creating 25% threshold atlas..."
    TEMP_THRESHOLD="${OUTPUT_DIR}/hard_atlas/temp_threshold_hemi-${hemi}.nii.gz"
    
    # Start with zeros
    c3d "${WARPED_LABELS_HEMI[0]}" -scale 0 -o "$TEMP_THRESHOLD"
    
    # For each label (1-9), count votes and apply 25% threshold
    for label in {1..9}; do
      echo "      -> Processing label $label with 25% threshold..."
      TEMP_COUNT="${OUTPUT_DIR}/hard_atlas/temp_count_label${label}_hemi-${hemi}.nii.gz"
      
      # Count how many subjects have this label at each voxel
      c3d "${WARPED_LABELS_HEMI[0]}" -scale 0 -o "$TEMP_COUNT"
      for warped_file in "${WARPED_LABELS_HEMI[@]}"; do
        TEMP_BINARY="${OUTPUT_DIR}/hard_atlas/temp_binary_$(basename $warped_file)_label${label}.nii.gz"
        c3d "$warped_file" -thresh $label $label 1 0 -o "$TEMP_BINARY"
        c3d "$TEMP_COUNT" "$TEMP_BINARY" -add -o "$TEMP_COUNT"
        rm -f "$TEMP_BINARY"
      done
      
      # Apply 25% threshold (need at least 25% of subjects = 2 out of 8 subjects)
      THRESHOLD_VAL=$(echo "scale=0; ${#WARPED_LABELS_HEMI[@]} * 0.25" | bc)
      c3d "$TEMP_COUNT" -thresh $THRESHOLD_VAL inf $label 0 -o "$TEMP_COUNT"
      
      # Add to final atlas
      c3d "$TEMP_THRESHOLD" "$TEMP_COUNT" -max -o "$TEMP_THRESHOLD"
      rm -f "$TEMP_COUNT"
    done
    
    # Move final result
    mv "$TEMP_THRESHOLD" "${OUTPUT_DIR}/hard_atlas/amygdala_atlas_hemi-${hemi}_threshold25.nii.gz"
  fi
done


# --- 6. GENERATE PROBABILISTIC ATLAS ---
# For each label (1-9), create a probability map.

echo "🗺️ Step 4/5: Generating probabilistic atlas maps..."
for hemi in "${HEMISPHERES[@]}"; do
  OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_DIR]}"
  echo "  -> Creating probability maps for Hemisphere ${hemi}"
  WARPED_LABELS_HEMI=($(find "${OUTPUT_DIR}/warped_labels/" -name "*_hemi-${hemi}_labels_warped.nii.gz"))
  
  if [ ${#WARPED_LABELS_HEMI[@]} -gt 0 ]; then
    for label in {1..9}; do
      echo "    --> Processing Label ${label}"
      
      # Create a temporary list of binary masks for the current label
      BINARY_MASKS=()
      for warped_label_file in "${WARPED_LABELS_HEMI[@]}"; do
        sub_id=$(basename "$warped_label_file" | cut -d'_' -f1)
        TEMP_BINARY_MASK="${OUTPUT_DIR}/prob_atlas/temp_binary_masks/${sub_id}_hemi-${hemi}_label-${label}_mask.nii.gz"
        
        # Create a binary mask where the current label is 1 and everything else is 0
        c3d "$warped_label_file" -thresh $label $label 1 0 -o "$TEMP_BINARY_MASK"
        BINARY_MASKS+=("$TEMP_BINARY_MASK")
      done

      # Average the binary masks to create the probability map
      PROB_MAP_OUTPUT="${OUTPUT_DIR}/prob_atlas/amygdala_atlas_hemi-${hemi}_label-${label}_probmap.nii.gz"
      AverageImages 3 "$PROB_MAP_OUTPUT" 0 "${BINARY_MASKS[@]}"
    done
  fi
done


echo "📦 Step 5/5: Creating 4D probabilistic atlas..."
for hemi in "${HEMISPHERES[@]}"; do
  OUTPUT_DIR="${HEMI_CONFIG[$hemi,OUTPUT_DIR]}"
  echo "  -> Combining probability maps for Hemisphere ${hemi}"
  
  # Create list of probability maps for this hemisphere
  PROB_MAPS_HEMI=()
  for label in {1..9}; do
    PROB_MAP="${OUTPUT_DIR}/prob_atlas/amygdala_atlas_hemi-${hemi}_label-${label}_probmap.nii.gz"
    if [ -f "$PROB_MAP" ]; then
      PROB_MAPS_HEMI+=("$PROB_MAP")
    fi
  done
  
  if [ ${#PROB_MAPS_HEMI[@]} -gt 0 ]; then
    # Create 4D NIfTI file with all probability maps
    OUTPUT_4D="${OUTPUT_DIR}/prob_atlas/amygdala_atlas_hemi-${hemi}_4D_probabilistic.nii.gz"
    
    # Use ImageMath to concatenate along 4th dimension
    ImageMath 4 "$OUTPUT_4D" TimeSeriesAssemble 1 "${PROB_MAPS_HEMI[@]}"
    
    echo "    --> Created 4D atlas: $(basename "$OUTPUT_4D")"
    echo "    --> Contains ${#PROB_MAPS_HEMI[@]} probability maps (labels 1-9)"
  fi
  # --- 8. COPY AND MASK TEMPLATE ---
  # Generate a mask from all warped labels (union of all labels >0)
  TEMPLATE_REF="${HEMI_CONFIG[$hemi,TEMPLATE_REF]}"
  WARPED_LABELS_HEMI=( $(find "${OUTPUT_DIR}/warped_labels/" -name "*_hemi-${hemi}_labels_warped.nii.gz") )
  if [ ${#WARPED_LABELS_HEMI[@]} -gt 0 ]; then
    echo "  -> Creating template mask and masked template for Hemisphere ${hemi}"
  # Mask the template using the majority-vote hard atlas
  MAJORITY_ATLAS="${OUTPUT_DIR}/hard_atlas/amygdala_atlas_hemi-${hemi}_majority.nii.gz"
  if [ -f "$MAJORITY_ATLAS" ]; then
    MASK_BIN="${OUTPUT_DIR}/hard_atlas/amygdala_atlas_hemi-${hemi}_majority_binmask.nii.gz"
    MASKED_TEMPLATE="${OUTPUT_DIR}/template_masked_hemi-${hemi}.nii.gz"
    # Threshold majority atlas: all labels >0 become 1, background 0
    c3d "$MAJORITY_ATLAS" -thresh 1 inf 1 0 -o "$MASK_BIN"
    c3d "$TEMPLATE_REF" "$MASK_BIN" -multiply -o "$MASKED_TEMPLATE"
    echo "    --> Masked template saved as: $MASKED_TEMPLATE (using binarized majority-vote atlas as mask)"
  else
    echo "    --> WARNING: Majority-vote atlas not found for Hemisphere ${hemi}, skipping template masking."
  fi
  fi
done