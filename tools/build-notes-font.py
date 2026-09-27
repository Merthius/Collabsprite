"""Rebuild the small OFL font atlas; Pillow, no system font dependency."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
chars = list(range(32, 127)) + list(range(160, 384)) + [0x2022, 0x2026, 0x2013, 0x2014, 0x20ac, 0x2192]
atlas = Image.new('RGBA', (1024, 1024))
draw = ImageDraw.Draw(atlas)
rows = ['return {']
x = y = 0
for key, name, size, height in [('body', 'Regular', 14, 20), ('heading', 'Bold', 21, 29)]:
    font = ImageFont.truetype(str(root / 'tools' / 'fonts' / f'AtkinsonHyperlegible-{name}.ttf'), size)
    rows.append(f'{key}={{height={height},glyphs={{')
    for cp in chars:
        advance = round(font.getlength(chr(cp)))
        width = max(advance+4, 8)
        if x+width > atlas.width:
            x = 0
            y += 32
        draw.text((x+2,y+2), chr(cp), font=font, fill=(40,48,58,255), anchor='lt')
        # Use the font's ascender alignment, not per-glyph top alignment.
        draw.rectangle((x,y,x+width-1,y+31), fill=(0,0,0,0))
        draw.text((x+2,y), chr(cp), font=font, fill=(40,48,58,255))
        rows.append(f'[{cp}]={{{x},{y},{width},{height},{advance}}},')
        x += width
    rows.append('}},')
atlas = atlas.crop((0,0,1024,y+32))
# Embedded bytes avoid Aseprite's fromFile permission dialog for a bundled UI
# asset, especially while the main native window is still starting.
rows.append(f'width={atlas.width},height={atlas.height},pixels=[[{atlas.tobytes().hex()}]],')
rows.append('}')
atlas.save(root/'extension'/'notes-font.png')
(root/'extension'/'notes-font-data.lua').write_text('\n'.join(rows)+'\n', encoding='utf-8')
