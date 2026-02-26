#!/bin/bash
set -e

################################################################################
#
#                 EXTRACT ATLAS STATISTICS (c3d lstat)
#
# This script:
# 1. Loops through Hemispheres (L, R).
# 2. Loops through Map Types (Chimap, R2star, SWI, etc.).
# 3. Uses c3d -lstat to calculate Mean, StdDev, etc. for every label in the atlas.
# 4. Saves everything into a single CSV file.
#
################################################################################

# --- Configuration ---
BASE_DIR="/nfs/khan/trainees/msalma29/amygdala_project/atlas/scripts/results/adult94TLabeledROIV2"
OUTPUT_CSV="${BASE_DIR}/amygdala_atlas_statistics.csv"

# List of map types (correspond to the folder prefixes)
MAP_TYPES=(
  "Chimap" 
  "R2starmap" 
  "swi" 
  "T2starmap" 
  "minIP" 
  "desc-singlepass_Chimap"
)

HEMISPHERES=("L" "R")

# --- Initialize CSV ---
echo "Creating CSV file: $OUTPUT_CSV"
# Header columns based on standard c3d -lstat output + identifiers
echo "Hemisphere,MapType,LabelID,Vol(mm3),Voxels,Mean,StdDev,Min,Max" > "$OUTPUT_CSV"

# --- Main Loop ---
for hemi in "${HEMISPHERES[@]}"; do
    
    # Define Atlas Path
    ATLAS_FILE="${BASE_DIR}/atlas_${hemi}H/hard_atlas/amygdala_atlas_hemi-${hemi}_majority.nii.gz"
    
    if [ ! -f "$ATLAS_FILE" ]; then
        echo "⚠️  WARNING: Atlas not found for Hemi ${hemi}: $ATLAS_FILE"
        continue
    fi

    echo "=========================================================="
    echo "Processing Hemisphere: ${hemi}"
    echo "Atlas: $(basename "$ATLAS_FILE")"

    for map_type in "${MAP_TYPES[@]}"; do
        
        # Define Map Directory
        MAP_DIR="${BASE_DIR}/${map_type}_template_${hemi}"
        
        # Check if directory exists
        if [ -d "$MAP_DIR" ]; then
            
            # Find the average file inside the directory. 
            # We look for *average.nii.gz to cover naming variations.
            MAP_FILE=$(find "$MAP_DIR" -name "*average_masked.nii.gz" | head -n 1)

            if [ -n "$MAP_FILE" ] && [ -f "$MAP_FILE" ]; then
                echo "  -> Analyzing Map: ${map_type}"
                
                # Run c3d -lstat
                # Syntax: c3d <GreyScaleImage> <LabelImage> -lstat
                # awk is used to parse the output and format it to CSV
                # We skip the first line (NR>1) because c3d outputs a header row.
                c3d "$MAP_FILE" "$ATLAS_FILE" -lstat | awk -v h="$hemi" -v m="$map_type" '
                    NR > 1 {
                        # c3d output cols: LabelID(1) Vol(2) Voxels(3) Mean(4) StdDev(5) Min(6) Max(7)
                        # We print: Hemi,Map,Label,Vol,Voxels,Mean,Std,Min,Max
                        printf "%s,%s,%s,%s,%s,%s,%s,%s,%s\n", h, m, $1, $2, $3, $4, $5, $6, $7
                    }
                ' >> "$OUTPUT_CSV"
                
            else
                echo "     ❌ No average file found in $MAP_DIR"
            fi
        else
            echo "     ❌ Directory not found: $MAP_DIR"
        fi
    done
done

echo "=========================================================="
echo "✅ Done! Statistics saved to: $OUTPUT_CSV"