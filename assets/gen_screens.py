#!/usr/bin/env python3
"""Generate App Store marketing screenshots for Brainrot3d at 3840x2160 (visionOS spec).
Each frame: a stylized spatial backdrop + a portrait app-window mock (original mascot
content, no real Instagram media) + a headline. Rendered via rsvg-convert."""
import os, subprocess, math
from gen_icon import brain, DEFS as ICON_DEFS

OUT = os.path.dirname(os.path.abspath(__file__)) + "/../marketing"
W, H = 3840, 2160
PINK, CYAN, LIME, PURP = "#ff3ea5", "#4cc9f0", "#c6ff3d", "#7b2ff7"

# window geometry (portrait 9:16) placed on the right
WW, WH = 760, 1351
WX, WY = 2560, 405

def esc(s): return s.replace("&", "&amp;")

def defs():
    return ICON_DEFS + f'''
  <linearGradient id="space" x1="0" y1="0" x2="0.6" y2="1">
    <stop offset="0" stop-color="#1a0636"/><stop offset="0.55" stop-color="#2a0a4a"/>
    <stop offset="1" stop-color="#06101f"/>
  </linearGradient>
  <linearGradient id="reelbg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#4a148c"/><stop offset="0.5" stop-color="#b3187a"/>
    <stop offset="1" stop-color="#1b2a6b"/>
  </linearGradient>
  <linearGradient id="head" x1="0" y1="0" x2="1" y2="0">
    <stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#ffd6f2"/>
  </linearGradient>
  <clipPath id="win"><rect x="{WX}" y="{WY}" width="{WW}" height="{WH}" rx="54"/></clipPath>
  <filter id="ds" x="-30%" y="-30%" width="160%" height="160%">
    <feDropShadow dx="0" dy="30" stdDeviation="50" flood-color="#000" flood-opacity="0.55"/>
  </filter>
  <filter id="soft"><feGaussianBlur stdDeviation="42"/></filter>
'''

def backdrop():
    blooms = (f'<circle cx="780" cy="600" r="560" fill="{PINK}" opacity="0.22" filter="url(#soft)"/>'
              f'<circle cx="3100" cy="1650" r="640" fill="{CYAN}" opacity="0.16" filter="url(#soft)"/>'
              f'<circle cx="2700" cy="380" r="420" fill="{PURP}" opacity="0.3" filter="url(#soft)"/>')
    # perspective floor grid
    grid = ""
    for i in range(-9, 10):
        x = 1920 + i * 360
        grid += f'<line x1="{x}" y1="1640" x2="{1920 + i*150}" y2="2160" stroke="#ff6ad5" stroke-width="2" opacity="0.18"/>'
    for j, y in enumerate([1700, 1780, 1880, 2010, 2160]):
        grid += f'<line x1="0" y1="{y}" x2="{W}" y2="{y}" stroke="#ff6ad5" stroke-width="2" opacity="{0.20-j*0.03:.2f}"/>'
    return f'<rect width="{W}" height="{H}" fill="url(#space)"/>{blooms}<g>{grid}</g>'

def text_block(headline, sub, tag):
    lines = headline.split("\n")
    tx, ty = 300, 760 - (len(lines)-1)*80
    out = (f'<g transform="translate(300,360)">'
           f'<rect width="118" height="118" rx="28" fill="url(#bg)"/>'
           f'<g transform="translate(59,57) scale(0.085)">{brain(512,512,1.0)}</g>'
           f'<text x="150" y="52" font-family="Helvetica Neue,Arial,sans-serif" font-size="44" font-weight="800" fill="#fff">Brainrot3d</text>'
           f'<text x="152" y="98" font-family="Helvetica Neue,Arial,sans-serif" font-size="30" fill="{CYAN}">{tag}</text></g>')
    for i, ln in enumerate(lines):
        out += (f'<text x="{tx}" y="{ty + i*168}" font-family="Helvetica Neue,Arial,sans-serif" '
                f'font-size="150" font-weight="800" fill="url(#head)">{esc(ln)}</text>')
    sy = ty + len(lines)*168 + 30
    for i, sl in enumerate(sub.split("\n")):
        out += (f'<text x="{tx+4}" y="{sy + i*72}" font-family="Helvetica Neue,Arial,sans-serif" '
                f'font-size="54" fill="#d9c9ff">{esc(sl)}</text>')
    return out

def chip(x, y, w, h, fill, txt, tcol="#fff", fs=26, r=None):
    r = r or h/2
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{r}" fill="{fill}"/>'
            f'<text x="{x+w/2}" y="{y+h/2+fs*0.35}" text-anchor="middle" font-family="Helvetica Neue,Arial,sans-serif" font-size="{fs}" font-weight="700" fill="{tcol}">{esc(txt)}</text>')

def reel_content():
    # placeholder "reel" = gradient + mascot + motion, clipped to the window
    return (f'<rect x="{WX}" y="{WY}" width="{WW}" height="{WH}" fill="url(#reelbg)"/>'
            f'<g transform="translate({WX+380},{WY+560})"><g transform="scale(0.62)">{brain(0,0,1.0)}</g></g>'
            f'<text x="{WX+WW/2}" y="{WY+1015}" text-anchor="middle" font-family="Helvetica Neue,Arial,sans-serif" font-size="40" font-weight="800" fill="#ffffff" opacity="0.92">POV: your brain at 3am</text>')

def chrome(like="59.7K", comment="148", show_caption=True):
    g = ""
    # top bar
    g += chip(WX+26, WY+26, 150, 56, "rgba(0,0,0,0.45)", "@grossed")
    g += chip(WX+WW-250, WY+26, 150, 56, LIME, "Signals", "#11210a")
    g += chip(WX+WW-86, WY+26, 60, 56, "rgba(0,0,0,0.45)", "♪")
    # action rail
    rx = WX+WW-92
    for i,(ic,ct,col) in enumerate([("♥", like, PINK), ("💬", comment, "#fff"), ("➤", "", "#fff")]):
        ry = WY+760 + i*150
        g += f'<circle cx="{rx}" cy="{ry}" r="44" fill="rgba(0,0,0,0.35)"/>'
        g += f'<text x="{rx}" y="{ry+18}" text-anchor="middle" font-size="46" fill="{col}">{ic}</text>'
        if ct: g += f'<text x="{rx}" y="{ry+78}" text-anchor="middle" font-family="Helvetica Neue,Arial,sans-serif" font-size="28" font-weight="700" fill="#fff">{ct}</text>'
    # bottom meta
    if show_caption:
        g += f'<text x="{WX+34}" y="{WY+WH-150}" font-family="Helvetica Neue,Arial,sans-serif" font-size="34" font-weight="800" fill="#fff">@grossed</text>'
        g += f'<text x="{WX+34}" y="{WY+WH-108}" font-family="Helvetica Neue,Arial,sans-serif" font-size="28" fill="#e8d8ff">triple body cam activation</text>'
    return g

def ornament():
    ox, oy, ow, oh = WX+WW/2-150, WY+WH+30, 300, 96
    g = f'<rect x="{ox}" y="{oy}" width="{ow}" height="{oh}" rx="48" fill="rgba(30,20,45,0.85)" stroke="#ffffff22"/>'
    for i,ic in enumerate(["⟲","❚❚","⏏"]):
        cx = ox+70+i*80
        if i==1: g += f'<rect x="{cx-34}" y="{oy+18}" width="68" height="60" rx="16" fill="#ffffff"/>'
        g += f'<text x="{cx}" y="{oy+oh/2+16}" text-anchor="middle" font-size="40" fill="{"#1a0030" if i==1 else "#fff"}">{ic}</text>'
    return g

def algo_panel():
    px, py, pw, ph = WX-120, WY+150, 560, 470
    rows = [("Watch time","6.2 s"),("Completion","38%"),("Audio","on"),("Visibility","100%"),
            ("Media PK","3929…2481"),("Viewer ID","tracked"),("ranked_at","1702770272")]
    g = f'<rect x="{px}" y="{py}" width="{pw}" height="{ph}" rx="34" fill="rgba(24,16,36,0.92)" stroke="#ffffff26" filter="url(#ds)"/>'
    g += f'<text x="{px+34}" y="{py+64}" font-family="Helvetica Neue,Arial,sans-serif" font-size="38" font-weight="800" fill="#fff">Algorithm signals</text>'
    g += f'<text x="{px+34}" y="{py+108}" font-family="Helvetica Neue,Arial,sans-serif" font-size="26" font-weight="700" fill="{LIME}">Reporting watch signal to Instagram</text>'
    for i,(k,v) in enumerate(rows):
        yy = py+165 + i*42
        g += f'<text x="{px+34}" y="{yy}" font-family="Helvetica Neue,Arial,sans-serif" font-size="28" fill="#b8a9d6">{k}</text>'
        g += f'<text x="{px+pw-34}" y="{yy}" text-anchor="end" font-family="Menlo,monospace" font-size="28" fill="#fff">{v}</text>'
    return g

def profile_grid():
    # replace reel with a profile header + 3-col thumbnail grid
    g = f'<rect x="{WX}" y="{WY}" width="{WW}" height="{WH}" fill="#120a22"/>'
    g += f'<circle cx="{WX+WW/2}" cy="{WY+150}" r="80" fill="url(#bg)"/>'
    g += f'<g transform="translate({WX+WW/2},{WY+150}) scale(0.12)">{brain(0,0,1.0)}</g>'
    g += f'<text x="{WX+WW/2}" y="{WY+290}" text-anchor="middle" font-family="Helvetica Neue,Arial,sans-serif" font-size="40" font-weight="800" fill="#fff">@creator ✓</text>'
    g += f'<text x="{WX+WW/2}" y="{WY+340}" text-anchor="middle" font-family="Helvetica Neue,Arial,sans-serif" font-size="28" fill="#b8a9d6">2.4M followers · 312 reels</text>'
    cols, pad, top = 3, 12, WY+390
    cw = (WW - pad*4)/cols
    ch = cw*1.6
    for i in range(9):
        r, c = divmod(i, cols)
        x = WX + pad + c*(cw+pad); y = top + r*(ch+pad)
        g += f'<rect x="{x}" y="{y}" width="{cw}" height="{ch}" rx="10" fill="url(#reelbg)"/>'
        g += f'<g transform="translate({x+cw/2},{y+ch/2}) scale(0.16)">{brain(0,0,1.0)}</g>'
        g += f'<text x="{x+14}" y="{y+ch-16}" font-size="24" fill="#fff">▶</text>'
    return g

def frame(name, body, headline, sub, tag, overlay=""):
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
           f'<defs>{defs()}</defs>{backdrop()}{text_block(headline, sub, tag)}'
           f'<rect x="{WX-6}" y="{WY-6}" width="{WW+12}" height="{WH+12}" rx="60" fill="#0c0718" filter="url(#ds)"/>'
           f'<g clip-path="url(#win)">{body}</g>'
           f'<rect x="{WX}" y="{WY}" width="{WW}" height="{WH}" rx="54" fill="none" stroke="#ffffff44" stroke-width="3"/>'
           f'{ornament()}{overlay}'
           f'</svg>')
    p = f"{OUT}/{name}.svg"; open(p, "w").write(svg)
    subprocess.run(["rsvg-convert", "-w", str(W), "-h", str(H), p, "-o", f"{OUT}/{name}.png"], check=True)
    os.remove(p); print("rendered", name)

os.makedirs(OUT, exist_ok=True)

frame("01_feed", reel_content()+chrome(), "Doomscroll\nin 3D.",
      "Your Instagram Reels feed, floating in your space.\nNative, vertical, infinite.", "for Apple Vision Pro")

frame("02_engage", reel_content()+chrome(like="59.7K", comment="148"), "Like. Comment.\nShare.",
      "Double-tap to like, open threaded comments,\nreshare to your DMs — all native.", "full engagement")

frame("03_algo", reel_content()+chrome(), "See what the\nalgorithm sees.",
      "Live ranking signals and a watch-time meter\non every reel. Or watch privately.", "algorithm x-ray",
      overlay=algo_panel())

frame("04_profile", profile_grid(), "Every creator,\none tap away.",
      "Open any profile and binge their reels\nin a spatial grid.", "creator profiles")

frame("05_tech", reel_content()+chrome(), "Built from\nthe binary.",
      "A reverse-engineered Instagram client that\nruns entirely on-device. No server.", "100% native")
print("all screenshots done")
