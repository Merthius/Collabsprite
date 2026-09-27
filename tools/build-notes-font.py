"""Rebuild the small OFL font atlas; Pillow, no system font dependency."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

root = Path(__file__).resolve().parents[1]
chars = list(range(32, 127)) + list(range(160, 384)) + [0x2022, 0x2026, 0x2013, 0x2014, 0x20ac, 0x2192]
factor = 4
atlas = Image.new('RGBA', (4096, 4096))
draw = ImageDraw.Draw(atlas)
rows = ['return {']
x = y = 0
for key, name, size, height in [('body', 'Regular', 13, 19), ('heading', 'Bold', 19, 26)]:
    path = str(root / 'tools' / 'fonts' / f'AtkinsonHyperlegible-{name}.ttf')
    base_font = ImageFont.truetype(path, size)
    font = ImageFont.truetype(path, size*factor)
    rows.append(f'{key}={{height={height},glyphs={{')
    for cp in chars:
        advance = round(base_font.getlength(chr(cp)))
        width = max(advance+4, 8)
        if x+width > atlas.width//factor:
            x = 0
            y += 32
        # Supersampled antialiased glyphs; shared ascender/baseline alignment.
        draw.text(((x+2)*factor,y*factor), chr(cp), font=font, fill=(40,48,58,255))
        rows.append(f'[{cp}]={{{x},{y},{width},{height},{advance}}},')
        x += width
    rows.append('}},')
atlas = atlas.crop((0,0,4096,(y+32)*factor))
# Embedded bytes avoid Aseprite's fromFile permission dialog for a bundled UI
# asset, especially while the main native window is still starting.
rows.append(f'factor={factor},width={atlas.width},height={atlas.height},alpha=[[{atlas.getchannel("A").tobytes().hex()}]],')
rows.append('}')
atlas.save(root/'extension'/'notes-font.png')
(root/'extension'/'notes-font-data.lua').write_text('\n'.join(rows)+'\n', encoding='utf-8')
