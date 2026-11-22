"""Draw the CludesUI Clean theme art: a 1500x1154 canvas whose window rect,
sidebar edge, header band, footer rule, logo box and close box sit where the
existing art has them (the panel's layout code is tied to those positions).
Flat panels, 1px rules, square corners, no glow, no ornaments."""

import sys

from PIL import Image, ImageDraw, ImageFont

media = sys.argv[1]  # CludesUI/Media
out = sys.argv[2]

W, H = 1500, 1154
L, T, R, B = 99, 104, 1399, 1049  # window rect (inclusive border pixels)
SIDE = 395  # sidebar / main divider x
TABS_BOTTOM = 282  # header + tab band ends here; content starts below
FOOT = 968  # footer rule y

BORDER = (58, 64, 69, 255)
SIDEBAR = (30, 33, 36, 255)
HEADER = (40, 44, 48, 255)
CONTENT = (36, 40, 43, 255)
FOOTER = (40, 44, 48, 255)
RULE = (52, 58, 63, 255)
TEXT = (232, 236, 239, 255)
ACCENT = (76, 201, 240, 255)

im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(im)

# Window: border then fills (radius 4 on the outer edge only).
d.rounded_rectangle((L, T, R, B), radius=4, fill=BORDER)
d.rounded_rectangle((L + 1, T + 1, R - 1, B - 1), radius=3, fill=CONTENT)
d.rectangle((L + 1, T + 1, SIDE - 1, B - 1), fill=SIDEBAR)
d.rectangle((SIDE + 1, T + 1, R - 1, TABS_BOTTOM - 1), fill=HEADER)
d.rectangle((SIDE + 1, FOOT + 1, R - 1, B - 1), fill=FOOTER)
# The fills squared off the inner corners: put the border back outside the inner rounded rect.
mask = Image.new("L", (W, H), 0)
ImageDraw.Draw(mask).rounded_rectangle((L, T, R, B), radius=4, fill=255)
inner = Image.new("L", (W, H), 0)
ImageDraw.Draw(inner).rounded_rectangle((L + 1, T + 1, R - 1, B - 1), radius=3, fill=255)
border_only = Image.new("RGBA", (W, H), BORDER)
im = Image.composite(im, border_only, inner)
im.putalpha(Image.eval(mask, lambda v: v))
d = ImageDraw.Draw(im)

# Rules: sidebar edge, header/content, footer.
d.line((SIDE, T + 1, SIDE, B - 1), fill=RULE)
d.line((SIDE + 1, TABS_BOTTOM, R - 1, TABS_BOTTOM), fill=RULE)
d.line((SIDE + 1, FOOT, R - 1, FOOT), fill=RULE)
# A quiet rule under the logo, the width of the sidebar's inner column.
d.line((118, 190, 376, 190), fill=RULE)

# Logo emblem: the white mask tinted to the accent, no glow, centred where the
# old emblem sat (its 76 unit box at 118, 110). The emblem and the "UI" go in
# the accent overlay (white, tinted in game with the live UI accent), so the
# base art holds only the neutral "Cludes".
OV_X, OV_Y, OV_W, OV_H = 118, 110, 202, 76
overlay = Image.new("RGBA", (OV_W, OV_H), (0, 0, 0, 0))
mark = Image.open(media + "/logo-full-thin.png").convert("RGBA").resize((46, 46), Image.LANCZOS)
white = Image.new("RGBA", mark.size, (255, 255, 255, 255))
white.putalpha(mark.getchannel("A"))
overlay.alpha_composite(white, (156 - 23 - OV_X, 148 - 23 - OV_Y))

# Wordmark.
font = ImageFont.truetype(media + "/fonts/Poppins.ttf", 23)
d.text((196, 148), "Cludes", font=font, fill=TEXT, anchor="lm")
cw = d.textlength("Cludes", font=font)
ImageDraw.Draw(overlay).text((196 + cw - OV_X, 148 - OV_Y), "UI", font=font, fill=(255, 255, 255, 255), anchor="lm")

# Close box: square, 1px ring, flat fill, X centred at (1367, 136).
CX0, CY0, CX1, CY1 = 1345, 115, 1388, 157
d.rounded_rectangle((CX0, CY0, CX1, CY1), radius=2, fill=(48, 52, 56, 255), outline=(74, 80, 85, 255))
g = 7
d.line((1367 - g, 136 - g, 1367 + g, 136 + g), fill=(200, 204, 208, 255), width=2)
d.line((1367 - g, 136 + g, 1367 + g, 136 - g), fill=(200, 204, 208, 255), width=2)

im.save(out, optimize=True)
overlay.save(sys.argv[3], optimize=True)
print("wrote", out, sys.argv[3], "overlay at", OV_X, OV_Y, OV_W, OV_H)
