from PIL import Image, ImageDraw
import os

sizes = {"drawable": 24, "drawable-mdpi": 24, "drawable-hdpi": 36, "drawable-xhdpi": 48, "drawable-xxhdpi": 72, "drawable-xxxhdpi": 96}

for folder, size in sizes.items():
    path = f"flutter_app/android/app/src/main/res/{folder}"
    os.makedirs(path, exist_ok=True)
    # Notification icon must be white-on-transparent
    img = Image.new("RGBA", (size, size), (0,0,0,0))
    draw = ImageDraw.Draw(img)
    # Simple heart shape approximation with circle + cross
    r = int(size * 0.35)
    draw.ellipse([size//2-r-r//2, size//4, size//2+r//2, size//4+2*r], fill="white")
    draw.ellipse([size//2-r//2, size//4, size//2+r+r//2, size//4+2*r], fill="white")
    draw.polygon([(int(size*0.15), int(size*0.45)), (size//2, int(size*0.85)), (int(size*0.85), int(size*0.45))], fill="white")
    img.save(f"{path}/ic_notification.png")

print("Notification icons created")