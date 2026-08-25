# -*- coding: utf-8 -*-
"""영문판 카톡·SNS 공유 썸네일(en/og.png)을 만든다.
   한글판 og.png에서 로고·배경은 그대로 두고 글자만 영어로 바꿔 그린다."""
from PIL import Image, ImageDraw, ImageFont

SRC, DST = 'og.png', 'en/og.png'
BG      = (244, 246, 242)
GREEN   = (47, 93, 74)
INK     = (24, 33, 29)
MUTED   = (94, 107, 100)
LEFT    = 96
MAXW    = 1010                      # 오른쪽 여백을 남기기 위한 최대 글자 너비

BOLD    = 'C:/Windows/Fonts/arialbd.ttf'
REG     = 'C:/Windows/Fonts/arial.ttf'

im = Image.open(SRC).convert('RGB')
d  = ImageDraw.Draw(im)

# 글자 영역만 배경색으로 지운다 (로고 y97~242 · 상단 초록바 y0~14 는 건드리지 않는다)
d.rectangle([0, 295, im.width, 610], fill=BG)

def measure(font, text, track=0):
    if track:
        return sum(font.getlength(c) for c in text) + track * (len(text) - 1)
    return font.getlength(text)

def fit(path, text, target_h, track=0):
    """글자 높이를 target_h 에 맞추되, 너비가 MAXW 를 넘으면 줄인다."""
    size = int(target_h * 1.4)
    for _ in range(200):
        f = ImageFont.truetype(path, size)
        a, t, b, bt = f.getbbox(text)
        h = bt - t
        if h > target_h or measure(f, text, track) > MAXW:
            size -= 1
            if size < 8: break
            continue
        return f
    return ImageFont.truetype(path, max(size, 8))

def draw(text, top, target_h, font_path, color, track=0):
    f = fit(font_path, text, target_h, track)
    _, t, _, _ = f.getbbox(text)
    y = top - t                      # 글자 윗변이 top 에 오도록 보정
    if track:
        x = LEFT
        for c in text:
            d.text((x, y), c, font=f, fill=color)
            x += f.getlength(c) + track
    else:
        d.text((LEFT, y), text, font=f, fill=color)

# 원본 한글판과 같은 자리 · 같은 크기로 영어를 앉힌다
draw('JEJU SUCHANG CO., LTD.',                              306, 27, BOLD, GREEN, track=2.5)
draw('PRODUCT CATALOG',                                     361, 82, BOLD, INK)
draw('237 Raw Materials from Pristine Jeju  ·  B2B Bulk Supply', 462, 30, REG, MUTED)
draw('Agricultural 89  ·  Marine Algae 88  ·  Medicinal Herbs 60', 515, 27, REG, MUTED)
draw('www.jejusuchang.com   ·   TEL +82-64-713-6696',       570, 25, REG, MUTED)

im.save(DST, optimize=True)
print('만들었습니다:', DST, im.size)
