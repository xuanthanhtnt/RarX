"""Tạo biểu tượng ứng dụng và biểu tượng tệp của RarX từ hai ảnh thiết kế trong Resources/Artwork.

    app-icon-source.png   ->  Resources/AppIcon.icns + AppIcon.png        (biểu tượng ứng dụng)
    file-icon-source.png  ->  Resources/DocIcons/*.icns                   (biểu tượng tệp .rar, .7z, .zip…)

Chạy:  python3 scripts/make_icons.py [ảnh_xem_trước.png] [--no-badge]
Cần:   Pillow, NumPy, SciPy  (pip install pillow numpy scipy)

Cách làm: dò viền "squircle" trong ảnh nguồn (khớp siêu elip), cắt đúng khung, phóng to lên lưới biểu tượng macOS
(824/1024), tạo mặt nạ bo góc khử răng cưa, thêm bóng đổ. Biểu tượng tệp có thêm nhãn phần mở rộng (RAR, 7Z…)
ở dưới để phân biệt các định dạng — tắt bằng --no-badge.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont
from scipy import ndimage as ndi
from scipy import optimize

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "Resources", "Artwork")
RES = os.path.join(ROOT, "Resources")
DOC_OUT = os.path.join(RES, "DocIcons")

CANVAS = 1024          # kích thước biểu tượng macOS
BODY = 824             # phần thân theo lưới biểu tượng macOS
SS = 4                 # siêu lấy mẫu cho mặt nạ

# tên tệp -> nhãn phần mở rộng
FORMATS = {
    "RarDoc": "RAR",
    "SevenZipDoc": "7Z",
    "ZipDoc": "ZIP",
    "TarDoc": "TAR",
    "GzDoc": "GZ",
    "Bz2Doc": "BZ2",
    "XzDoc": "XZ",
    "ZstDoc": "ZST",
    "CabDoc": "CAB",
    "WimDoc": "WIM",
    "VolumeDoc": "001",
    "ArchiveDoc": "ARC",
}

FONT_CANDIDATES = [
    "/usr/share/fonts/opentype/inter/Inter-Black.otf",
    "/usr/share/fonts/opentype/inter/Inter-ExtraBold.otf",
    "/usr/share/fonts/truetype/google-fonts/Poppins-Bold.ttf",
    "/System/Library/Fonts/SFNSRounded.ttf",
    "/System/Library/Fonts/Supplemental/Arial Black.ttf",
    "/Library/Fonts/Arial Bold.ttf",
]


# ---------------------------------------------------------------- dò viền squircle

def _r_expected(theta, a, b, n):
    c, s = np.abs(np.cos(theta)), np.abs(np.sin(theta))
    return ((c / a) ** n + (s / b) ** n) ** (-1.0 / n)


def fit_squircle(img):
    """Trả về (cx, cy, a, b, n) của viền squircle trong ảnh nguồn."""
    arr = np.asarray(img.convert("RGB")).astype(float)
    gray = ndi.gaussian_filter(arr.mean(axis=2), 0.8)
    h, w = gray.shape
    p = np.array([w / 2, h * 0.5, w * 0.19, w * 0.20, 5.0])
    for it in range(4):
        cx, cy, a, b, n = p
        span = 14 if it == 0 else 7
        pts = []
        for th in np.linspace(0, 2 * np.pi, 720, endpoint=False):
            r0 = _r_expected(th, a, b, n)
            rs = np.arange(r0 - span, r0 + span, 0.25)
            xs, ys = cx + rs * np.cos(th), cy + rs * np.sin(th)
            v = ndi.map_coordinates(gray, [ys, xs], order=1, mode="nearest")
            k = np.argmax(np.abs(np.gradient(v)))
            pts.append((xs[k], ys[k]))
        pts = np.array(pts)

        def resid(q):
            x = np.abs((pts[:, 0] - q[0]) / q[2])
            y = np.abs((pts[:, 1] - q[1]) / q[3])
            return (x ** q[4] + y ** q[4]) ** (1 / q[4]) - 1

        p = optimize.least_squares(resid, p, loss="soft_l1", f_scale=0.01).x
    return p


def squircle_mask(size, n, inset=0.0):
    """Mặt nạ siêu elip khử răng cưa (size x size), co vào `inset` điểm ảnh."""
    big = size * SS
    ax = np.linspace(-1, 1, big, endpoint=False) + 1.0 / big
    k = 1.0 - (inset * SS) / (big / 2)
    u = np.abs(ax)[None, :] / k
    v = np.abs(ax)[:, None] / k
    m = ((u ** n + v ** n) <= 1.0).astype(np.uint8) * 255
    return Image.fromarray(m, "L").resize((size, size), Image.BOX)


def font_file():
    for path in FONT_CANDIDATES:
        if os.path.exists(path):
            return path
    sys.exit("Không tìm thấy phông chữ đậm — sửa FONT_CANDIDATES.")


# ---------------------------------------------------------------- dựng biểu tượng

def cut_body(path, src_inset=1.2):
    """Cắt phần squircle của ảnh nguồn, phóng lên BODY x BODY và áp mặt nạ. Trả về ảnh RGBA."""
    src = Image.open(path).convert("RGB")
    cx, cy, a, b, n = fit_squircle(src)
    box = (cx - a, cy - b, cx + a, cy + b)
    # phóng 2 bước cho mượt, rồi làm nét nhẹ để chữ không bị mờ
    mid = src.resize((BODY * 3 // 2, BODY * 3 // 2), Image.LANCZOS, box=box)
    body = mid.resize((BODY, BODY), Image.LANCZOS)
    body = body.filter(ImageFilter.UnsharpMask(radius=1.6, percent=55, threshold=2))
    inset = src_inset * BODY / (2 * a)
    mask = squircle_mask(BODY, n, inset=inset)
    out = body.convert("RGBA")
    out.putalpha(mask)
    return out, mask


def place_with_shadow(body, mask):
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    off = (CANVAS - BODY) // 2
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 105), (off, off + 14), mask)
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(16)))
    canvas.alpha_composite(body, (off, off))
    return canvas


def add_badge(canvas, label, fontpath):
    """Nhãn phần mở rộng ở dưới biểu tượng tệp."""
    off = (CANVAS - BODY) // 2
    pill_h = int(BODY * 0.125)
    cy = off + int(BODY * 0.925)
    cx = CANVAS // 2

    size = int(pill_h * 0.62)
    font = ImageFont.truetype(fontpath, size)
    l, t, r, b = font.getbbox(label)
    text_w, text_h = r - l, b - t
    pill_w = max(int(BODY * 0.30), text_w + int(pill_h * 0.9))
    pill_w += pill_w % 2
    pill_h += pill_h % 2
    box = (cx - pill_w // 2, cy - pill_h // 2, cx + pill_w // 2, cy + pill_h // 2)

    layer = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((box[0], box[1] + 8, box[2], box[3] + 8), radius=pill_h // 2, fill=(40, 10, 70, 130))
    layer.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(9)))

    pill = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    grad = Image.new("RGBA", (1, pill_h))
    for y in range(pill_h):
        t_ = y / max(1, pill_h - 1)
        grad.putpixel((0, y), (int(96 - 34 * t_), int(44 - 22 * t_), int(150 - 56 * t_), 255))
    pm = Image.new("L", (CANVAS, CANVAS), 0)
    ImageDraw.Draw(pm).rounded_rectangle(box, radius=pill_h // 2, fill=255)
    pill.paste(grad.resize((pill_w, pill_h)), (box[0], box[1]), pm.crop(box))
    layer.alpha_composite(pill)
    ImageDraw.Draw(layer).rounded_rectangle(box, radius=pill_h // 2, outline=(255, 255, 255, 235), width=6)

    tx = cx - text_w / 2 - l
    ty = cy - text_h / 2 - t
    ImageDraw.Draw(layer).text((tx, ty), label, font=font, fill=(255, 255, 255, 255))
    canvas.alpha_composite(layer)
    return canvas


def save_icns(img, path):
    img.save(path, sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    badge = "--no-badge" not in sys.argv
    preview = args[0] if args else None

    fontpath = font_file()

    # Biểu tượng ứng dụng
    body, mask = cut_body(os.path.join(ART, "app-icon-source.png"))
    app = place_with_shadow(body, mask)
    app.save(os.path.join(RES, "AppIcon.png"))
    save_icns(app, os.path.join(RES, "AppIcon.icns"))
    print("ok AppIcon")

    # Biểu tượng tệp
    os.makedirs(DOC_OUT, exist_ok=True)
    body, mask = cut_body(os.path.join(ART, "file-icon-source.png"))
    base = place_with_shadow(body, mask)
    docs = []
    for name, label in FORMATS.items():
        icon = add_badge(base.copy(), label, fontpath) if badge else base.copy()
        save_icns(icon, os.path.join(DOC_OUT, name + ".icns"))
        docs.append(icon)
        print("ok", name)

    if preview:
        cell = 256
        sheet = Image.new("RGBA", (cell * 6, cell * 3), (236, 238, 242, 255))
        sheet.alpha_composite(app.resize((cell, cell), Image.LANCZOS), (0, 0))
        for i, icon in enumerate(docs):
            idx = i + 6
            sheet.alpha_composite(icon.resize((cell, cell), Image.LANCZOS), ((idx % 6) * cell, (idx // 6) * cell))
        # hàng trên: biểu tượng ứng dụng ở nhiều cỡ
        x = cell
        for s in (128, 64, 32, 16):
            sheet.alpha_composite(app.resize((s, s), Image.LANCZOS), (x + 20, 20))
            x += s + 24
        sheet.save(preview)


if __name__ == "__main__":
    main()
