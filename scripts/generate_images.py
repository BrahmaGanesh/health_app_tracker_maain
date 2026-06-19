from PIL import Image, ImageDraw, ImageFont
import os

os.makedirs("static/images", exist_ok=True)

NAVY  = (20, 45, 76)
MINT  = (159, 211, 199)
SAGE  = (97, 179, 144)
WHITE = (255, 255, 255)

def rounded_icon(size, bg, fg_text, fg_color=WHITE, font_ratio=0.5, radius_ratio=0.22):
    img = Image.new("RGBA", (size, size), (0,0,0,0))
    draw = ImageDraw.Draw(img)
    radius = int(size * radius_ratio)
    draw.rounded_rectangle([0,0,size-1,size-1], radius=radius, fill=bg)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", int(size*font_ratio))
    except Exception:
        font = ImageFont.load_default()
    bbox = draw.textbbox((0,0), fg_text, font=font)
    w = bbox[2]-bbox[0]; h = bbox[3]-bbox[1]
    draw.text(((size-w)/2 - bbox[0], (size-h)/2 - bbox[1]), fg_text, fill=fg_color, font=font)
    return img

# App icons (192, 512) — navy bg, mint heart-ish "H" mark
for size, name in [(192,"icon-192.png"), (512,"icon-512.png")]:
    img = rounded_icon(size, NAVY, "H", MINT, font_ratio=0.55)
    img.save(f"static/images/{name}")

# Badge (small monochrome-ish)
badge = rounded_icon(72, NAVY, "H", MINT, font_ratio=0.55)
badge.save("static/images/badge-72.png")

# Done icon — green check
done = rounded_icon(64, (34,197,94), "✓", WHITE, font_ratio=0.6)
done.save("static/images/done-icon.png")

# Snooze icon — amber clock-ish "Z"
snooze = rounded_icon(64, (245,158,11), "Z", WHITE, font_ratio=0.6)
snooze.save("static/images/snooze-icon.png")

# Default avatar placeholder
avatar = rounded_icon(256, (79,59,120), "U", MINT, font_ratio=0.5)
avatar.save("static/images/default-avatar.png")

# OG/social preview & favicon
favicon = rounded_icon(64, NAVY, "H", MINT, font_ratio=0.55)
favicon.save("static/images/favicon.png")

print("Generated images:")
for f in sorted(os.listdir("static/images")):
    print(" -", f)