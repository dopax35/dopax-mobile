import os
import glob
from PIL import Image

def remove_transparency(img_path, bg_colour=(255, 255, 255)):
    try:
        image = Image.open(img_path)
        # Check if the image has an alpha channel or transparency
        if image.mode in ('RGBA', 'LA') or (image.mode == 'P' and 'transparency' in image.info):
            print(f"Processing {img_path}...")
            # Convert to RGBA to ensure we have an alpha channel to work with
            alpha = image.convert('RGBA')

            # Create a solid white background
            background = Image.new('RGBA', alpha.size, bg_colour + (255,))

            # Paste the original image on top of the background, using its alpha as the mask
            background.paste(alpha, mask=alpha)

            # Convert to pure RGB, stripping the alpha channel
            final_image = background.convert('RGB')
            
            # Overwrite the original file
            final_image.save(img_path, 'PNG')
            print(f"Successfully removed alpha channel from {os.path.basename(img_path)}")
        else:
            print(f"No alpha channel found in {os.path.basename(img_path)} (already opaque).")
    except Exception as e:
        print(f"Error processing {img_path}: {e}")

if __name__ == "__main__":
    appiconset_dir = "ios_app/PDCollectiOS/Assets.xcassets/AppIcon.appiconset"
    png_files = glob.glob(os.path.join(appiconset_dir, "*.png"))
    
    if not png_files:
        print(f"No PNG files found in {appiconset_dir}")
    
    for file in png_files:
        remove_transparency(file)
