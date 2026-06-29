#!/usr/bin/env python3
"""Generate the Brainrot3d app icon as visionOS layered art (Back / Middle / Front),
each 1024x1024, plus a flat 1024 marketing icon. Vaporwave 'brainrot' theme: a glossy
melting brain with googly eyes. Original mascot — no trademarked characters."""
import os, subprocess

OUT = os.path.dirname(os.path.abspath(__file__)) + "/icon"
S = 1024

def render(name, svg):
    p = f"{OUT}/{name}.svg"
    open(p, "w").write(svg)
    subprocess.run(["rsvg-convert", "-w", str(S), "-h", str(S), p, "-o", f"{OUT}/{name}.png"], check=True)
    print("rendered", name)

# ---- shared brain mascot (used by Front + flat) ----------------------------
def brain(cx=512, cy=505, scale=1.0, eyes=True):
    # lumpy silhouette = a cluster of same-fill blobs + a base ellipse; gyri squiggles;
    # central fissure; gloss highlight; two big googly eyes; a melty drip.
    def t(x, y): return (cx + (x-512)*scale, cy + (y-512)*scale)
    def c(x, y, r):
        X, Y = t(x, y); return f'<circle cx="{X:.1f}" cy="{Y:.1f}" r="{r*scale:.1f}" fill="url(#brain)"/>'
    lobes = "".join([
        c(512,470,250),
        c(360,420,130), c(470,360,135), c(600,355,140), c(690,430,125),
        c(380,560,120), c(640,560,120), c(512,600,140),
    ])
    # fissure + gyri
    def path(d, w=14, col="#c01566", op=0.55):
        return f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{w*scale:.1f}" stroke-linecap="round" opacity="{op}"/>'
    def P(x, y): X, Y = t(x, y); return f"{X:.1f},{Y:.1f}"
    fissure = path(f"M {P(512,300)} C {P(540,380)} {P(484,450)} {P(512,520)} S {P(500,640)} {P(512,690)}", 16, "#b01060", 0.5)
    gyri = "".join([
        path(f"M {P(360,430)} C {P(420,400)} {P(420,470)} {P(470,450)}"),
        path(f"M {P(560,440)} C {P(620,410)} {P(630,480)} {P(680,455)}"),
        path(f"M {P(380,560)} C {P(440,535)} {P(450,600)} {P(500,575)}"),
        path(f"M {P(560,575)} C {P(620,550)} {P(640,610)} {P(690,585)}"),
    ])
    # gloss
    gx, gy = t(420, 380)
    gloss = f'<ellipse cx="{gx:.1f}" cy="{gy:.1f}" rx="{120*scale:.1f}" ry="{70*scale:.1f}" fill="#ffffff" opacity="0.22" transform="rotate(-25 {gx:.1f} {gy:.1f})"/>'
    # drip
    dx, dy = t(512, 690)
    drip = (f'<path d="M {t(450,640)[0]:.1f} {t(450,640)[1]:.1f} q {30*scale:.0f} {120*scale:.0f} 0 {180*scale:.0f} '
            f'q {32*scale:.0f} {30*scale:.0f} {62*scale:.0f} 0 q {-30*scale:.0f} {-90*scale:.0f} 0 {-180*scale:.0f} z" '
            f'fill="url(#brain)"/>')
    eyeart = ""
    if eyes:
        for ex, ey in [(440, 470), (600, 470)]:
            EX, EY = t(ex, ey)
            px, py = t(ex+18, ey+16)
            eyeart += (f'<circle cx="{EX:.1f}" cy="{EY:.1f}" r="{72*scale:.1f}" fill="#fff" stroke="#1a0030" stroke-width="{6*scale:.1f}"/>'
                       f'<circle cx="{px:.1f}" cy="{py:.1f}" r="{34*scale:.1f}" fill="#140026"/>'
                       f'<circle cx="{px-12*scale:.1f}" cy="{py-12*scale:.1f}" r="{11*scale:.1f}" fill="#fff"/>')
    return lobes + drip + fissure + gyri + gloss + eyeart

DEFS = '''
  <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
    <stop offset="0" stop-color="#3a0ca3"/><stop offset="0.5" stop-color="#f72585"/>
    <stop offset="1" stop-color="#4cc9f0"/>
  </linearGradient>
  <radialGradient id="glow" cx="0.5" cy="0.46" r="0.55">
    <stop offset="0" stop-color="#ffffff" stop-opacity="0.55"/>
    <stop offset="0.55" stop-color="#ff7ad9" stop-opacity="0.18"/>
    <stop offset="1" stop-color="#ffffff" stop-opacity="0"/>
  </radialGradient>
  <radialGradient id="brain" cx="0.42" cy="0.34" r="0.85">
    <stop offset="0" stop-color="#ffd1ec"/><stop offset="0.45" stop-color="#ff8fd0"/>
    <stop offset="1" stop-color="#ff3ea5"/>
  </radialGradient>
'''

def svg(body): return f'<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}"><defs>{DEFS}</defs>{body}</svg>'

def _main():
 # Back: opaque gradient + sun rays
 rays = "".join(f'<polygon points="512,512 {512+1448*__import__("math").cos(a):.0f},{512+1448*__import__("math").sin(a):.0f} {512+1448*__import__("math").cos(a+0.13):.0f},{512+1448*__import__("math").sin(a+0.13):.0f}" fill="#ffffff" opacity="0.05"/>' for a in [i*0.52 for i in range(12)])
 render("Back", svg(f'<rect width="{S}" height="{S}" fill="url(#bg)"/>{rays}<rect width="{S}" height="{S}" fill="url(#glow)"/>'))

 # Middle: soft glow + sparkles (transparent)
 spark = "".join(f'<g transform="translate({x},{y}) rotate({r})"><path d="M0,-{s} L{s*0.28:.0f},-{s*0.28:.0f} L{s},0 L{s*0.28:.0f},{s*0.28:.0f} L0,{s} L-{s*0.28:.0f},{s*0.28:.0f} L-{s},0 L-{s*0.28:.0f},-{s*0.28:.0f} Z" fill="#fff" opacity="{o}"/></g>'
                 for x,y,s,r,o in [(210,250,46,10,0.85),(815,300,32,20,0.7),(800,760,40,0,0.6),(230,790,28,15,0.6),(512,170,24,0,0.5)])
 render("Middle", svg(f'<rect width="{S}" height="{S}" fill="url(#glow)"/>{spark}'))

 # Front: the brain mascot (transparent bg)
 render("Front", svg(f'<g filter="url(#none)">{brain(512, 500, 0.92)}</g>'))

 # Flat marketing icon (all combined, opaque, rounded handled by store)
 render("flat1024", svg(f'<rect width="{S}" height="{S}" fill="url(#bg)"/>{rays}<rect width="{S}" height="{S}" fill="url(#glow)"/>{spark}{brain(512,500,0.92)}'))
 print("done")


if __name__ == '__main__':
    _main()
