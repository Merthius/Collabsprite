param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

# One 16 x 16 pixel master: two people contribute different halves of one image.
$heart = @(
    '................',
    '................',
    '...CCC....OOO...',
    '..CCCCC..OOOOO..',
    '..CCCCCCOOOOOO..',
    '..CCCCCPPOOOOO..',
    '...CCCCPPOOOO...',
    '....CCCPPOOO....',
    '.....CCPPOO.....',
    '......CPPO......',
    '.......PP.......',
    '................',
    '................',
    '................',
    '................',
    '................'
)

foreach ($row in $heart) {
    if ($row.Length -ne 16) { throw 'Logo-Zeile ist nicht 16 Pixel breit.' }
}

$colors = @{
    border = '#101522'
    ground = '#20283A'
    tileA = '#263248'
    tileB = '#2A3850'
    shadow = '#111628'
    C = '#58D5EA'
    O = '#FFB866'
    P = '#BD86F5'
}

function Color([string]$hex) {
    return [System.Drawing.ColorTranslator]::FromHtml($hex)
}

function Pixel([System.Drawing.Graphics]$g, [int]$x, [int]$y, [int]$size, [string]$hex) {
    $brush = [System.Drawing.SolidBrush]::new((Color $hex))
    try { $g.FillRectangle($brush, $x, $y, $size, $size) }
    finally { $brush.Dispose() }
}

function IconPixels([int]$originX, [int]$originY, [int]$scale) {
    $items = [System.Collections.Generic.List[object]]::new()
    for ($y = 0; $y -lt 16; $y++) {
        for ($x = 0; $x -lt 16; $x++) {
            $corner = (($y -eq 0 -or $y -eq 15) -and ($x -lt 2 -or $x -gt 13)) -or
                (($y -eq 1 -or $y -eq 14) -and ($x -eq 0 -or $x -eq 15))
            if ($corner) { continue }
            $base = if ($x -eq 0 -or $x -eq 15 -or $y -eq 0 -or $y -eq 15) {
                $colors.border
            } elseif ($x -eq 1 -or $x -eq 14 -or $y -eq 1 -or $y -eq 14) {
                $colors.ground
            } elseif ((([int][math]::Floor($x / 2) + [int][math]::Floor($y / 2)) % 2) -eq 0) {
                $colors.tileA
            } else {
                $colors.tileB
            }
            $items.Add(@{ X = $originX + $x * $scale; Y = $originY + $y * $scale; S = $scale; Fill = $base })
        }
    }
    # One-pixel drop shadow keeps the bright heart legible on the checkerboard.
    for ($y = 0; $y -lt 16; $y++) {
        for ($x = 0; $x -lt 16; $x++) {
            if ($heart[$y][$x] -ne '.') {
                $items.Add(@{ X = $originX + $x * $scale; Y = $originY + ($y + 1) * $scale; S = $scale; Fill = $colors.shadow })
            }
        }
    }
    for ($y = 0; $y -lt 16; $y++) {
        for ($x = 0; $x -lt 16; $x++) {
            $key = [string]$heart[$y][$x]
            if ($key -ne '.') {
                $items.Add(@{ X = $originX + $x * $scale; Y = $originY + $y * $scale; S = $scale; Fill = $colors[$key] })
            }
        }
    }
    return $items
}

function DrawItems([System.Drawing.Graphics]$g, [object[]]$items) {
    foreach ($item in $items) { Pixel $g $item.X $item.Y $item.S $item.Fill }
}

$iconItems = @(IconPixels 0 0 1)
$svgLines = [System.Collections.Generic.List[string]]::new()
$svgLines.Add('<svg xmlns="http://www.w3.org/2000/svg" width="512" height="512" viewBox="0 0 16 16" shape-rendering="crispEdges" role="img" aria-labelledby="title desc">')
$svgLines.Add('  <title id="title">Collabsprite</title>')
$svgLines.Add('  <desc id="desc">Ein Pixel-Herz: eine tuerkise und eine orange Haelfte treffen sich in der Mitte.</desc>')
foreach ($item in $iconItems) {
    $svgLines.Add("  <rect x=`"$($item.X)`" y=`"$($item.Y)`" width=`"1`" height=`"1`" fill=`"$($item.Fill)`"/>")
}
$svgLines.Add('</svg>')
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'collabsprite-icon.svg'), $svgLines, [Text.UTF8Encoding]::new($false))

$icon = [System.Drawing.Bitmap]::new(512, 512, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$iconGraphics = [System.Drawing.Graphics]::FromImage($icon)
try {
    $iconGraphics.Clear([System.Drawing.Color]::Transparent)
    DrawItems $iconGraphics @(IconPixels 0 0 32)
    $icon.Save((Join-Path $PSScriptRoot 'collabsprite-icon-512.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $iconGraphics.Dispose()
    $icon.Dispose()
}

$preview = [System.Drawing.Bitmap]::new(1280, 640, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($preview)
try {
    $g.Clear((Color '#151B2A'))
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    DrawItems $g @(IconPixels 96 112 26)

    $small = [System.Drawing.Font]::new('Consolas', 25, [System.Drawing.FontStyle]::Bold)
    $title = [System.Drawing.Font]::new('Consolas', 64, [System.Drawing.FontStyle]::Bold)
    $subtitle = [System.Drawing.Font]::new('Consolas', 29, [System.Drawing.FontStyle]::Regular)
    $mutedBrush = [System.Drawing.SolidBrush]::new((Color '#94A6BD'))
    $whiteBrush = [System.Drawing.SolidBrush]::new((Color '#F5F7FB'))
    try {
        $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
        $g.DrawString('ASEPRITE EXTENSION', $small, $mutedBrush, 550, 177)
        $g.DrawString('COLLABSPRITE', $title, $whiteBrush, 544, 241)
        $g.DrawString('Pixel art, together.', $subtitle, $mutedBrush, 550, 370)
        $cyanBrush = [System.Drawing.SolidBrush]::new((Color $colors.C))
        $purpleBrush = [System.Drawing.SolidBrush]::new((Color $colors.P))
        $orangeBrush = [System.Drawing.SolidBrush]::new((Color $colors.O))
        try {
            $g.FillRectangle($cyanBrush, 550, 463, 90, 12)
            $g.FillRectangle($purpleBrush, 640, 463, 90, 12)
            $g.FillRectangle($orangeBrush, 730, 463, 90, 12)
        } finally {
            $cyanBrush.Dispose(); $purpleBrush.Dispose(); $orangeBrush.Dispose()
        }
    } finally {
        $small.Dispose(); $title.Dispose(); $subtitle.Dispose()
        $mutedBrush.Dispose(); $whiteBrush.Dispose()
    }
    $preview.Save((Join-Path $PSScriptRoot 'collabsprite-social-preview.png'), [System.Drawing.Imaging.ImageFormat]::Png)
} finally {
    $g.Dispose()
    $preview.Dispose()
}

Write-Host 'Logo (SVG/PNG) und GitHub-Vorschau erzeugt.'
