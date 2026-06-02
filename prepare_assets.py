import os
import urllib.request
import zipfile
import io

def download_file(url, filepath):
    print(f"Downloading {url} to {filepath}")
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req) as response, open(filepath, 'wb') as out_file:
        out_file.write(response.read())

def prepare_fonts():
    fonts_dir = "fonts"
    os.makedirs(fonts_dir, exist_ok=True)
    
    fonts = {
        "Rajdhani-Regular.ttf": "https://github.com/google/fonts/raw/main/ofl/rajdhani/Rajdhani-Regular.ttf",
        "Rajdhani-Medium.ttf": "https://github.com/google/fonts/raw/main/ofl/rajdhani/Rajdhani-Medium.ttf",
        "Rajdhani-Bold.ttf": "https://github.com/google/fonts/raw/main/ofl/rajdhani/Rajdhani-Bold.ttf",
        "Outfit-Regular.ttf": "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit-Regular.ttf",
        "Outfit-Medium.ttf": "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit-Medium.ttf",
        "Outfit-Bold.ttf": "https://github.com/google/fonts/raw/main/ofl/outfit/Outfit-Bold.ttf"
    }
    
    for filename, url in fonts.items():
        filepath = os.path.join(fonts_dir, filename)
        if not os.path.exists(filepath):
            try:
                download_file(url, filepath)
            except Exception as e:
                print(f"Failed to download {filename}: {e}")

def create_icon():
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        import subprocess
        import sys
        subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
        from PIL import Image, ImageDraw, ImageFont

    os.makedirs("icons", exist_ok=True)
    size = 1024
    img = Image.new('RGBA', (size, size), color='#0F0F3D')
    d = ImageDraw.Draw(img)
    
    # We will try to load Rajdhani bold if available to draw 'X', else default
    font_path = os.path.join("fonts", "Rajdhani-Bold.ttf")
    try:
        fnt = ImageFont.truetype(font_path, int(size * 0.7))
    except Exception:
        fnt = ImageFont.load_default()
        
    text = "X"
    bbox = d.textbbox((0, 0), text, font=fnt)
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    
    # Simple orange/purple colors
    d.text(((size-w)/2, (size-h)/2 - (size*0.1)), text, font=fnt, fill='#FF5C35')
    
    # Save the master icon
    img.save("icons/app_icon_1024.png")
    
    # Save Android mipmap sizes
    android_sizes = {
        "mdpi": 48,
        "hdpi": 72,
        "xhdpi": 96,
        "xxhdpi": 144,
        "xxxhdpi": 192
    }
    for name, s in android_sizes.items():
        resized = img.resize((s, s), Image.Resampling.LANCZOS)
        resized.save(f"icons/ic_launcher_{name}.png")
        
    print("Generated app icons.")

if __name__ == "__main__":
    prepare_fonts()
    create_icon()
