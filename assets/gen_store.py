#!/usr/bin/env python3
"""Build App Store screenshots (3840x2160) from REAL Vision Pro captures.
Technique: blur+darken the passthrough room into a branded backdrop, keep the app
window sharp via a feathered focus mask, redact private info, add caption + icon."""
import os
from PIL import Image, ImageFilter, ImageDraw, ImageFont, ImageEnhance, ImageOps

ROOT = os.path.dirname(os.path.abspath(__file__)) + "/.."
OUT = ROOT + "/marketing"
ICON = ROOT + "/assets/icon/flat1024.png"
W, H = 3840, 2160

def font(sz, bold=True):
    for p in ["/System/Library/Fonts/Supplemental/Arial Bold.ttf" if bold else "/System/Library/Fonts/Supplemental/Arial.ttf",
              "/System/Library/Fonts/SFNS.ttf", "/Library/Fonts/Arial Bold.ttf"]:
        if os.path.exists(p):
            try: return ImageFont.truetype(p, sz)
            except Exception: pass
    return ImageFont.load_default()

def rounded_mask(size, radius, feather):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0,0,size[0]-1,size[1]-1], radius=radius, fill=255)
    return m.filter(ImageFilter.GaussianBlur(feather))

def build(src_path, out_name, headline, sub, win_box, redact=None):
    # win_box / redact are in source (1920x1080) coords
    src = Image.open(src_path).convert("RGB")
    sx, sy = W/src.width, H/src.height
    big = src.resize((W, H), Image.LANCZOS)

    # backdrop: blurred + darkened + purple tint
    bg = big.filter(ImageFilter.GaussianBlur(36))
    bg = ImageEnhance.Brightness(bg).enhance(0.42)
    tint = Image.new("RGB", (W, H), (40, 10, 70))
    bg = Image.blend(bg, tint, 0.28)
    # brand glow blooms
    glow = Image.new("RGB", (W, H), (0,0,0)); gd = ImageDraw.Draw(glow)
    gd.ellipse([ -300,-200, 1500,1200], fill=(255,40,160))
    gd.ellipse([2600,1200, 4200,2600], fill=(60,200,255))
    bg = Image.blend(bg, glow.filter(ImageFilter.GaussianBlur(260)), 0.20)

    # sharp app window, feathered onto the backdrop
    bx = [int(win_box[0]*sx), int(win_box[1]*sy), int(win_box[2]*sx), int(win_box[3]*sy)]
    win = big.crop(bx)
    if redact:  # blur a private region before compositing
        rb = [int(redact[0]*sx)-bx[0], int(redact[1]*sy)-bx[1], int(redact[2]*sx)-bx[0], int(redact[3]*sy)-bx[1]]
        patch = win.crop(rb).filter(ImageFilter.GaussianBlur(14))
        win.paste(patch, rb[:2])
    mask = rounded_mask(win.size, radius=46, feather=70)
    # soft drop shadow
    shadow = Image.new("RGBA", (W, H), (0,0,0,0))
    sh = Image.new("RGBA", win.size, (0,0,0,150)); sh.putalpha(mask)
    shadow.paste(sh, (bx[0], bx[1]+26), sh)
    shadow = shadow.filter(ImageFilter.GaussianBlur(40))
    out = bg.convert("RGBA"); out.alpha_composite(shadow)
    out.paste(win, (bx[0], bx[1]), mask)
    out = out.convert("RGB")
    d = ImageDraw.Draw(out)

    # caption (top-left)
    for i, ln in enumerate(headline.split("\n")):
        d.text((210, 250 + i*170), ln, font=font(150), fill=(255,255,255))
    sy0 = 250 + len(headline.split("\n"))*170 + 24
    for i, sl in enumerate(sub.split("\n")):
        d.text((214, sy0 + i*72), sl, font=font(52, bold=False), fill=(220,205,255))

    # icon + wordmark (bottom-left)
    ic = Image.open(ICON).convert("RGBA").resize((150,150), Image.LANCZOS)
    out.paste(ic, (212, H-250), ic)
    d.text((384, H-235), "Brainrot3d", font=font(56), fill=(255,255,255))
    d.text((386, H-170), "Apple Vision Pro", font=font(34, bold=False), fill=(180,210,255))

    out.save(f"{OUT}/{out_name}.png")
    print("built", out_name)

os.makedirs(OUT, exist_ok=True)

# real captures (1920x1080). win_box estimated from the captures.
build(ROOT+"/incoming/comments.png", "store_comments",
      "Comment without\nleaving the headset.",
      "Threaded replies, GIFs, and likes — the full\nInstagram comments, floating in your space.",
      win_box=(885, 0, 1420, 770))

build(ROOT+"/incoming/algorithm.png", "store_algorithm",
      "See what the\nalgorithm sees.",
      "A live ranking + watch-time x-ray on every reel.\nOr flip one switch and watch privately.",
      win_box=(985, 12, 1480, 824),
      redact=(1300, 250, 1475, 372))
print("done")
