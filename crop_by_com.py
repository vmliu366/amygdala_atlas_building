#!/usr/bin/env python3

"""
Crops a NIfTI image and label file around the center-of-mass (CoM) 
of the label, based on a threshold.
"""

import nibabel as nib
import numpy as np
from scipy import ndimage as ndi
import argparse
import sys
import json

def crop_images_by_com(input_image_path, input_label_path, output_image_path, output_label_path, crop_size=200, lower_threshold=None, upper_threshold=None):
    """
    Crop a NIfTI image to match a pre-cropped binary mask's dimensions and bounding box.
    The mask is assumed to be pre-cropped; we extract its bounding box and apply it to the image.
    
    Args:
        input_image_path: Path to input image file (full size)
        input_label_path: Path to input binary mask file (already cropped, e.g., 200x200x200)
        output_image_path: Path for output cropped image
        output_label_path: Path for output cropped mask
        crop_size: Unused (kept for backward compatibility)
        lower_threshold: Unused (kept for backward compatibility)
        upper_threshold: Unused (kept for backward compatibility)
    """
    
    try:
        # Load images
        img = nib.load(input_image_path)
        lab = nib.load(input_label_path)
        
        # The mask is already cropped, we need to find where it came from in the original image
        # We'll use the mask's affine to figure out the bounding box in the original image space
        
        img_data = img.get_fdata(dtype=np.float32)
        lab_data = lab.get_fdata(dtype=np.float32)
        
        # Get the affine transforms
        img_affine = img.affine
        lab_affine = lab.affine
        
        # Create a mapping: mask voxel coords -> world coords -> original image voxel coords
        # For each corner of the mask bounding box, find where it maps in the original image
        
        lab_shape = np.array(lab_data.shape, dtype=int)
        
        # Get all 8 corners of the mask bounding box in voxel space
        corners_mask_vox = np.array([
            [0, 0, 0],
            [lab_shape[0]-1, 0, 0],
            [0, lab_shape[1]-1, 0],
            [0, 0, lab_shape[2]-1],
            [lab_shape[0]-1, lab_shape[1]-1, 0],
            [lab_shape[0]-1, 0, lab_shape[2]-1],
            [0, lab_shape[1]-1, lab_shape[2]-1],
            [lab_shape[0]-1, lab_shape[1]-1, lab_shape[2]-1],
        ], dtype=float)
        
        # Convert mask voxel coords to world coords
        corners_mask_world = np.array([
            lab_affine @ np.append(c, 1)
            for c in corners_mask_vox
        ])[:, :3]
        
        # Convert world coords to original image voxel coords
        img_affine_inv = np.linalg.inv(img_affine)
        corners_img_vox = np.array([
            img_affine_inv @ np.append(c, 1)
            for c in corners_mask_world
        ])[:, :3]
        
        # Find the bounding box in original image space
        img_start = np.floor(corners_img_vox.min(axis=0)).astype(int)
        img_end = np.ceil(corners_img_vox.max(axis=0)).astype(int)
        
        # Clamp to image bounds
        img_shape = np.array(img_data.shape, dtype=int)
        img_start = np.maximum(img_start, 0)
        img_end = np.minimum(img_end, img_shape)
        
        # Crop the image
        slicer = tuple(slice(s, e) for s, e in zip(img_start, img_end))
        img_arr = np.asarray(img.dataobj[slicer])
        
        # Update affine for crop
        def update_affine_for_crop(affine, start_ijk):
            start_coords = np.array(start_ijk, dtype=float)
            A = np.array(affine, dtype=float)
            A_prime = A.copy()
            A_prime[:3, 3] = A[:3, 3] + A[:3, :3] @ start_coords
            return A_prime
        
        img_aff = update_affine_for_crop(img.affine, img_start)
        img_cropped = nib.Nifti1Image(img_arr, img_aff, img.header)
        
        # Preserve metadata for cropped image
        try:
            zooms = list(img.header.get_zooms())
            if len(zooms) > 3:
                zooms = zooms[:3]
            img_cropped.header.set_zooms(zooms)
        except Exception:
            pass
        
        try:
            img_cropped.set_data_dtype(img.header.get_data_dtype())
        except Exception:
            pass
        
        try:
            scode = img.header.get_sform(coded=True)[1]
            qcode = img.header.get_qform(coded=True)[1]
            img_cropped.set_sform(img_cropped.affine, int(scode) if scode else 1)
            img_cropped.set_qform(img_cropped.affine, int(qcode) if qcode else 1)
        except Exception:
            img_cropped.set_sform(img_cropped.affine, 1)
            img_cropped.set_qform(img_cropped.affine, 1)
        
        # Save cropped image
        nib.save(img_cropped, output_image_path)
        
        # Skip saving the mask output (we don't use it anyway)
        # The original masked_filled is used directly in the next step
        
        # Return info as a JSON string
        return_data = {
            'original_shape': tuple(img_shape.tolist()),
            'mask_shape': tuple(lab_shape.tolist()),
            'crop_start': tuple(img_start.tolist()),
            'crop_end': tuple(img_end.tolist()),
            'crop_size': tuple((img_end - img_start).tolist()),
        }
        print(json.dumps(return_data))
        return 0

    except Exception as e:
        print(f"Error cropping {input_image_path}: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        return 1

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Crop NIfTI image around binary mask CoM.")
    parser.add_argument("-i", "--input_image", required=True, help="Path to input image file")
    parser.add_argument("-l", "--input_label", required=True, help="Path to input binary mask file")
    parser.add_argument("-o", "--output_image", required=True, help="Path for output cropped image")
    parser.add_argument("-p", "--output_label", required=True, help="Path for output cropped mask")
    parser.add_argument("--crop_size", type=int, default=200, help="Cubic crop size in voxels (default: 200)")
    parser.add_argument("--lower_threshold", type=float, default=None, help="Unused (kept for backward compatibility)")
    parser.add_argument("--upper_threshold", type=float, default=None, help="Unused (kept for backward compatibility)")
    
    args = parser.parse_args()
    
    sys.exit(crop_images_by_com(
        args.input_image,
        args.input_label,
        args.output_image,
        args.output_label,
        args.crop_size,
        args.lower_threshold,
        args.upper_threshold
    ))