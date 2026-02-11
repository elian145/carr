import sys, io
from PIL import Image, ImageOps
p = sys.argv[1]
img = Image.open(p)
img = ImageOps.exif_transpose(img).convert('RGB')
w,h = img.size; longest = max(w,h)
if longest > 2200:
    from PIL import Image as _I
    img = img.resize((int(round(w*1600/longest)), int(round(h*1600/longest))), _I.Resampling.LANCZOS)
buf = io.BytesIO()
img.save(buf, format='JPEG', quality=85, optimize=True)
open(p+'.normalized.jpg','wb').write(buf.getvalue())
print('normalized_size:', img.size)
