"""Regenerate the Roku icon/splash. Requires Pillow; not needed to build the app."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parent.parent
out = root / 'roku' / 'images'
out.mkdir(parents=True, exist_ok=True)
font_path = root / 'roku' / 'fonts' / 'JetBrainsMono-Bold.ttf'

SUNSET = [(0, '#2f1250'), (.18, '#4b2141'), (.40, '#682f31'), (.62, '#843d22'), (.82, '#a14c13'), (1, '#be5a03')]
ORANGE_BAND = [(0, '#bc5904'), (.25, '#a34d11'), (.50, '#8b421d'), (.75, '#723629'), (1, '#4e243c')]
ORANGE_BUTTON = [(0, '#bc5904'), (.45, '#974717'), (1, '#4e243c')]

def gradient(size, stops):
    image = Image.new('RGB', size)
    draw = ImageDraw.Draw(image)
    colors = [(at, tuple(bytes.fromhex(color.lstrip('#')))) for at, color in stops]
    for y in range(size[1]):
        at = y / max(1, size[1] - 1)
        for (start, c1), (end, c2) in zip(colors, colors[1:]):
            if start <= at <= end:
                mix = (at - start) / (end - start)
                color = tuple(round(a + (b - a) * mix) for a, b in zip(c1, c2))
                draw.line((0, y, size[0], y), fill=color)
                break
    return image

gradient((1280, 720), SUNSET).save(out / 'background.png', optimize=True)
gradient((16, 96), ORANGE_BUTTON).save(out / 'button-fill.png', optimize=True)
band = gradient((500, 48), ORANGE_BAND).convert('RGBA')
mask = Image.new('L', band.size)
ImageDraw.Draw(mask).polygon([(0, 0), (499, 0), (465, 47), (0, 47)], fill=255)
band.putalpha(mask)
band.save(out / 'header-band.png', optimize=True)

def draw_brand(size, filename, splash=False):
    image = gradient(size, SUNSET)
    draw = ImageDraw.Draw(image)
    width, height = size
    scale = width / 1280
    brand = ImageFont.truetype(str(font_path), int(100 * scale))
    small = ImageFont.truetype(str(font_path), max(10, int(19 * scale)))
    text = 'SPELUNKR.'
    box = draw.textbbox((0, 0), text, font=brand)
    x = (width - box[2]) / 2
    y = height * .38
    draw.text((x + 2 * scale, y + 2 * scale), text, font=brand, fill='#000000')
    draw.text((x, y), text, font=brand, fill='#ffff00')
    draw.rectangle((x, y + 130 * scale, width - x, y + 133 * scale), fill='#2652b2')
    subtitle = 'CABLE TV, BUT WEIRDER.'
    box = draw.textbbox((0, 0), subtitle, font=small)
    draw.text(((width - box[2]) / 2, y + 165 * scale), subtitle, font=small, fill='#ffffff')
    if splash:
        note = 'ORIGINAL PROJECT BY SPELUNKR.TV'
        box = draw.textbbox((0, 0), note, font=small)
        draw.text(((width - box[2]) / 2, height * .82), note, font=small, fill='#ffff00')
    image.save(out / filename, optimize=True)

draw_brand((540, 405), 'channel-icon.png')
draw_brand((1280, 720), 'splash.png', True)
print('Created Roku channel icon and splash screen.')
