"""Generează iconița aplicației: caiet cu spirală + pix, desenate în alb
pe fundal verde (nuanța Evernote). Rulare: python tool/make_icon.py"""

import math
import os

from PIL import Image, ImageChops, ImageDraw

S = 4  # supraeșantionare pentru margini netede
N = 1024 * S
# Verdele iconiței Evernote, măsurat de pe captura userului.
GREEN_TOP = (98, 210, 86)
GREEN_BOTTOM = (56, 136, 48)
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'icon')


def gradient():
    img = Image.new('RGBA', (N, N))
    d = ImageDraw.Draw(img)
    for y in range(N):
        t = y / (N - 1)
        c = tuple(round(a + (b - a) * t) for a, b in zip(GREEN_TOP, GREEN_BOTTOM))
        d.line([(0, y), (N, y)], fill=c + (255,))
    return img


def p(x, y):
    return (x * S, y * S)


def w(v):
    return round(v * S)


def symbol():
    """Simbolul alb pe fundal transparent, în coordonate 0..1024."""
    # ---- caietul
    book = Image.new('RGBA', (N, N), CLEAR)
    d = ImageDraw.Draw(book)
    left, top, right, bottom = 262, 214, 682, 810
    d.rounded_rectangle([p(left, top), p(right, bottom)], radius=w(54),
                        outline=WHITE, width=w(46))
    for y in (390, 490, 590):  # rândurile paginii
        d.rounded_rectangle([p(372, y - 16), p(590, y + 16)], radius=w(16),
                            fill=WHITE)
    for y in (300, 420, 540, 660):  # spirala
        d.rounded_rectangle([p(left - 60, y - 22), p(left + 58, y + 22)],
                            radius=w(22), fill=WHITE)

    # ---- pixul: vârful în jos-stânga, spre pagină
    angle = math.radians(130)
    cx, cy = 636, 520
    ca, sa = math.cos(angle), math.sin(angle)

    def rot(x, y):
        return p(cx + x * ca - y * sa, cy + x * sa + y * ca)

    half_len, half_w, tip = 196, 48, 86
    body = [rot(-half_len, -half_w), rot(half_len, -half_w),
            rot(half_len, half_w), rot(-half_len, half_w)]
    point = [rot(half_len, -half_w), rot(half_len + tip, 0),
             rot(half_len, half_w)]

    pen = Image.new('RGBA', (N, N), CLEAR)
    dp = ImageDraw.Draw(pen)
    dp.polygon(body, fill=WHITE)
    dp.polygon(point, fill=WHITE)
    # capacul: o fantă transparentă lângă capătul din spate
    dp.polygon([rot(-half_len + 64, -half_w - 2), rot(-half_len + 88, -half_w - 2),
                rot(-half_len + 88, half_w + 2), rot(-half_len + 64, half_w + 2)],
               fill=CLEAR)
    # linie fină între corp și vârf
    dp.polygon([rot(half_len - 6, -half_w - 2), rot(half_len + 10, -half_w - 2),
                rot(half_len + 10, half_w + 2), rot(half_len - 6, half_w + 2)],
               fill=CLEAR)

    # ---- spațiu liber în jurul pixului, ca să se despartă de caiet
    halo = Image.new('L', (N, N), 0)
    dh = ImageDraw.Draw(halo)
    # Conturul unui poligon în Pillow e desenat spre interior, deci marginea
    # o construim din linii groase de-a lungul laturilor (se extind și în afară).
    for poly in (body, point):
        dh.polygon(poly, fill=255)
        dh.line(poly + [poly[0]], fill=255, width=w(44), joint='curve')
        for x, y in poly:
            r0 = w(22)
            dh.ellipse([x - r0, y - r0, x + r0, y + r0], fill=255)
    r, g, b, a = book.split()
    a = ImageChops.subtract(a, halo)
    book = Image.merge('RGBA', (r, g, b, a))

    return Image.alpha_composite(book, pen)


def centered(sym):
    """Mută desenul (caiet + pix) exact în centrul pânzei, după conturul
    lui real — pixul și spirala îl făceau să pară decalat."""
    left, top, right, bottom = sym.getchannel('A').getbbox()
    out = Image.new('RGBA', (N, N), CLEAR)
    out.paste(sym.crop((left, top, right, bottom)),
              ((N - (right - left)) // 2, (N - (bottom - top)) // 2))
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    sym = centered(symbol())

    # Iconița completă (iOS, web, Windows): fundal + simbol, fără transparență.
    full = Image.alpha_composite(gradient(), sym)
    full.resize((1024, 1024), Image.LANCZOS).convert('RGB').save(
        os.path.join(OUT, 'app_icon.png'))

    # Android adaptiv: simbolul pe transparent, în zona sigură (~80% din pânză).
    small = sym.resize((round(N * 0.8), round(N * 0.8)), Image.LANCZOS)
    fg = Image.new('RGBA', (N, N), CLEAR)
    off = (N - small.width) // 2
    fg.paste(small, (off, off), small)
    fg.resize((1024, 1024), Image.LANCZOS).save(
        os.path.join(OUT, 'app_icon_foreground.png'))
    print('ok')


if __name__ == '__main__':
    main()
