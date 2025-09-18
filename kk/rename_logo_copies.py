import os

logo_dir = os.path.join(os.path.dirname(__file__), 'static', 'uploads', 'car_brand_logos')

for filename in os.listdir(logo_dir):
    if filename.endswith(' - Copy.png'):
        new_name = filename.replace(' - Copy.png', '.png')
        src = os.path.join(logo_dir, filename)
        dst = os.path.join(logo_dir, new_name)
        if os.path.exists(dst):
            print(f"Skipping {filename}: {new_name} already exists.")
        else:
            os.rename(src, dst)
            print(f"Renamed {filename} -> {new_name}") 