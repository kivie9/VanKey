"""Sinh logo VanKey (chữ V trắng viền đen + khiên) ra PNG cho icon Android.
Chạy:  python docs/brand/make_icons.py   (cần Pillow)
Hình học khớp với docs/brand/vankey-logo.svg và AppLogo trong app/lib/app/widgets/ui.dart."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
RES = os.path.join(ROOT, 'app', 'android', 'app', 'src', 'main', 'res')
BRAND = os.path.dirname(os.path.abspath(__file__))
DARK, WHITE, BLUE = (14, 19, 48, 255), (255, 255, 255, 255), (79, 107, 237, 255)
TILE, SHIFT = 180, (7, 3)  # hệ toạ độ 180x180, cả logo dời (7,3)
HI = 8                      # vẽ ở 8 px/đơn vị rồi thu nhỏ để mịn cạnh


def quad(p0, c, p1, n=240):
    return [((1 - t) ** 2 * p0[0] + 2 * t * (1 - t) * c[0] + t * t * p1[0],
             (1 - t) ** 2 * p0[1] + 2 * t * (1 - t) * c[1] + t * t * p1[1]) for t in (i / n for i in range(n + 1))]


def cubic(p0, c1, c2, p1, n=120):
    out = []
    for i in range(n + 1):
        t = i / n; u = 1 - t
        out.append((u**3 * p0[0] + 3 * u * u * t * c1[0] + 3 * u * t * t * c2[0] + t**3 * p1[0],
                    u**3 * p0[1] + 3 * u * u * t * c1[1] + 3 * u * t * t * c2[1] + t**3 * p1[1]))
    return out


def line(a, b, n=40):
    return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]


V = quad((54, 80), (72, 106), (90, 128)) + quad((90, 128), (112, 98), (134, 46))
SHIELD = (line((44, 34), (62, 41)) + line((62, 41), (62, 58)) + cubic((62, 58), (62, 68), (54, 74), (44, 78))
          + cubic((44, 78), (34, 74), (26, 68), (26, 58)) + line((26, 58), (26, 41)) + line((26, 41), (44, 34)))


def blobs(d, pts, r, fill, s):
    for x, y in pts:
        X, Y = (x + SHIFT[0]) * s, (y + SHIFT[1]) * s
        d.ellipse((X - r * s, Y - r * s, X + r * s, Y + r * s), fill=fill)


def mark(size_px):
    """Logo trên nền trong suốt, hệ 180 đơn vị phủ kín ảnh size_px."""
    s = size_px / TILE
    img = Image.new('RGBA', (size_px, size_px), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    blobs(d, V, 19, DARK, s)
    blobs(d, V, 12, WHITE, s)
    blobs(d, SHIELD, 3, DARK, s)  # viền khiên 6 đơn vị, 3 nằm ngoài
    d.polygon([((x + SHIFT[0]) * s, (y + SHIFT[1]) * s) for x, y in SHIELD], fill=WHITE)
    return img


def tile(size_px):
    big = TILE * HI
    img = Image.new('RGBA', (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, big - 1, big - 1), radius=44 * HI, fill=BLUE)
    img.alpha_composite(mark(big))
    return img.resize((size_px, size_px), Image.LANCZOS)


def foreground(size_px, radius_frac=0.345):
    """Lớp nổi của adaptive icon: logo căn giữa, mọi điểm nằm trong vòng an toàn (bán kính ~36/108)."""
    big = mark(TILE * HI)
    box = big.getbbox()
    cx, cy = (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
    a = big.getchannel('A').resize((TILE * 2, TILE * 2))
    k = big.size[0] / a.size[0]
    pts = [(x * k, y * k) for y in range(a.size[1]) for x in range(a.size[0]) if a.getpixel((x, y)) > 8]
    rmax = max(((x - cx) ** 2 + (y - cy) ** 2) ** 0.5 for x, y in pts)
    f = radius_frac * size_px / rmax
    crop = big.crop(box)
    crop = crop.resize((max(1, round(crop.size[0] * f)), max(1, round(crop.size[1] * f))), Image.LANCZOS)
    out = Image.new('RGBA', (size_px, size_px), (0, 0, 0, 0))
    out.alpha_composite(crop, (round(size_px / 2 - (cx - box[0]) * f), round(size_px / 2 - (cy - box[1]) * f)))
    return out


if __name__ == '__main__':
    for folder, base in {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}.items():
        d = os.path.join(RES, 'mipmap-' + folder)
        tile(round(48 * base)).save(os.path.join(d, 'ic_launcher.png'))
        foreground(round(108 * base)).save(os.path.join(d, 'ic_launcher_foreground.png'))
        print(folder, 'ok')
    tile(512).save(os.path.join(BRAND, 'vankey-logo-512.png'))
    print('512 ok')
