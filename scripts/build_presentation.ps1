$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$outputPath = Join-Path $projectRoot 'report\presentation_evacuation.pptx'

$ppt = New-Object -ComObject PowerPoint.Application
$ppt.Visible = -1
$presentation = $ppt.Presentations.Add()
$presentation.PageSetup.SlideSize = 16
$slideWidth = 960.0
$slideHeight = 540.0

$script:C = @{
	Ink = 0x18333B
	Muted = 0x53696E
	Red = 0x3D56BF
	RedDark = 0x2F438E
	Teal = 0x788B35
	Pale = 0xF2F7F6
	White = 0xFFFFFF
	Grid = 0xE2E9E7
	Warm = 0xE8F1FF
	WarmInk = 0x744534
}

function Add-Rect($slide, [double]$x, [double]$y, [double]$w, [double]$h, [int]$color, [bool]$rounded = $false, [int]$lineColor = -1) {
	$type = if ($rounded) { 5 } else { 1 }
	$shape = $slide.Shapes.AddShape($type, $x, $y, $w, $h)
	$shape.Fill.Solid()
	$shape.Fill.ForeColor.RGB = $color
	if ($lineColor -lt 0) { $shape.Line.Visible = 0 } else { $shape.Line.ForeColor.RGB = $lineColor; $shape.Line.Weight = 1.2 }
	return $shape
}

function Add-Line($slide, [double]$x1, [double]$y1, [double]$x2, [double]$y2, [int]$color, [double]$weight = 1.2) {
	$line = $slide.Shapes.AddLine($x1, $y1, $x2, $y2)
	$line.Line.ForeColor.RGB = $color
	$line.Line.Weight = $weight
	return $line
}

function Add-Text($slide, [string]$text, [double]$x, [double]$y, [double]$w, [double]$h, [double]$size, [int]$color, [bool]$bold = $false, [string]$font = 'Aptos', [int]$align = 1) {
	$box = $slide.Shapes.AddTextbox(1, $x, $y, $w, $h)
	$box.Line.Visible = 0
	$box.Fill.Visible = 0
	$box.TextFrame.MarginLeft = 0
	$box.TextFrame.MarginRight = 0
	$box.TextFrame.MarginTop = 0
	$box.TextFrame.MarginBottom = 0
	$box.TextFrame.WordWrap = -1
	$range = $box.TextFrame.TextRange
	$range.Text = $text
	$range.Font.Name = $font
	$range.Font.Size = $size
	$range.Font.Bold = if ($bold) { -1 } else { 0 }
	$range.Font.Color.RGB = $color
	$range.ParagraphFormat.Alignment = $align
	return $box
}

function New-Slide([int]$number, [string]$section) {
	$slide = $presentation.Slides.Add($number, 12)
	$slide.FollowMasterBackground = 0
	$slide.Background.Fill.Solid()
	$slide.Background.Fill.ForeColor.RGB = $script:C.White
	Add-Rect $slide 0 0 13 540 $script:C.Red | Out-Null
	Add-Text $slide $section.ToUpper() 52 27 840 20 11 $script:C.Red $true | Out-Null
	Add-Line $slide 52 510 908 510 $script:C.Grid 1 | Out-Null
	Add-Text $slide 'SIMULATION D’ÉVACUATION  ·  TEST B' 52 518 600 15 9 $script:C.Muted $false | Out-Null
	Add-Text $slide ('{0:D2}' -f $number) 866 516 42 18 10 $script:C.Muted $true 'Aptos' 3 | Out-Null
	return $slide
}

function Add-Bullet($slide, [string]$text, [double]$x, [double]$y, [double]$w, [double]$size = 19, [int]$color = -1) {
	if ($color -lt 0) { $color = $script:C.Ink }
	Add-Rect $slide $x ($y + 9) 7 7 $script:C.Red $true | Out-Null
	Add-Text $slide $text ($x + 20) $y ($w - 20) 48 $size $color $false | Out-Null
}

# 1. Cover
$s = New-Slide 1 'Projet multi-agents · présentation'
Add-Text $s 'Quand une sortie\nétroite bloque\nune foule' 58 106 600 190 39 $script:C.Ink $true | Out-Null
Add-Text $s 'Simulation d’évacuation d’un bureau sous Godot' 61 312 570 34 18 $script:C.Muted $false | Out-Null
Add-Rect $s 690 92 205 312 $script:C.Pale $true | Out-Null
Add-Rect $s 726 138 132 20 $script:C.Teal $true | Out-Null
Add-Rect $s 726 346 132 20 $script:C.Red $true | Out-Null
Add-Text $s 'BUREAU' 730 111 125 20 11 $script:C.Muted $true 'Aptos' 2 | Out-Null
for ($i = 0; $i -lt 8; $i++) {
	$x = 745 + (($i % 4) * 28)
	$y = 195 + ([math]::Floor($i / 4) * 48)
	$dot = $s.Shapes.AddShape(9, $x, $y, 13, 13)
	$dot.Fill.Solid(); $dot.Fill.ForeColor.RGB = if ($i % 2 -eq 0) { $script:C.Red } else { $script:C.Teal }; $dot.Line.Visible = 0
}
Add-Text $s '60 agents  ·  alarme  ·  une ou deux sorties' 61 390 610 26 14 $script:C.Muted $false | Out-Null
Add-Text $s 'Question : comment les décisions individuelles produisent-elles un résultat collectif ?' 61 429 750 42 17 $script:C.Ink $true | Out-Null

# 2. Research question
$s = New-Slide 2 '01 · Problématique'
Add-Text $s 'Une règle simple. Un résultat collectif.' 52 70 830 46 28 $script:C.Ink $true | Out-Null
Add-Rect $s 54 150 360 255 $script:C.Pale $true | Out-Null
Add-Text $s 'CHAQUE AGENT' 80 174 300 24 13 $script:C.Teal $true | Out-Null
Add-Text $s 'Cherche une sortie\n\nRéagit à l’alarme\n\nAvance vers son objectif' 80 214 295 150 21 $script:C.Ink $false | Out-Null
Add-Rect $s 515 150 360 255 $script:C.Warm $true | Out-Null
Add-Text $s 'LA FOULE' 542 174 300 24 13 $script:C.Red $true | Out-Null
Add-Text $s 'Contacts et compression\n\nArche devant la porte\n\nDébit réduit ou blocage' 542 214 300 150 21 $script:C.Ink $false | Out-Null
Add-Text $s 'Comment la largeur de porte modifie-t-elle le débit d’évacuation ?' 72 438 790 42 22 $script:C.Ink $true | Out-Null

# 3. Simulation model
$s = New-Slide 3 '02 · Modèle du système'
Add-Text $s 'Un bureau simulé, des agents autonomes' 52 70 850 46 28 $script:C.Ink $true | Out-Null
Add-Rect $s 55 140 515 320 $script:C.Pale $true | Out-Null
Add-Rect $s 83 167 459 268 0xE7EEE9 $false 0xB5C6C1 | Out-Null
Add-Rect $s 250 167 115 268 0xDCEBE7 | Out-Null
Add-Rect $s 83 412 194 23 $script:C.White | Out-Null
Add-Rect $s 338 412 204 23 $script:C.White | Out-Null
Add-Text $s 'SORTIE' 245 439 120 18 10 $script:C.Red $true 'Aptos' 2 | Out-Null
for ($i = 0; $i -lt 20; $i++) {
	$x = 104 + (($i % 5) * 35)
	$y = 205 + ([math]::Floor($i / 5) * 39)
	$agentDot = $s.Shapes.AddShape(9, $x, $y, 12, 12)
	$agentDot.Fill.Solid(); $agentDot.Fill.ForeColor.RGB = if ($i % 3 -eq 0) { $script:C.Red } else { $script:C.Teal }; $agentDot.Line.Visible = 0
}
Add-Text $s 'Plan schématique du bureau' 84 447 455 18 11 $script:C.Muted $false | Out-Null
Add-Bullet $s '60 agents, placés à des postes et en salles.' 615 157 280 19 | Out-Null
Add-Bullet $s 'Départ assis; alarme après 5 s.' 615 225 280 19 | Out-Null
Add-Bullet $s 'Réaction individuelle jusqu’à 3 s.' 615 293 280 19 | Out-Null
Add-Bullet $s 'Collisions physiques et mesure CSV.' 615 361 280 19 | Out-Null

# 4. Agent lifecycle
$s = New-Slide 4 '03 · Cycle d’un agent'
Add-Text $s 'De l’alarme à l’évacuation' 52 70 850 46 28 $script:C.Ink $true | Out-Null
$labels = @('Assis','Attend\nl’alarme','Réagit','Se lève','Évacue','Sorti')
$xPositions = @(70, 215, 360, 505, 650, 795)
for ($i = 0; $i -lt $labels.Count; $i++) {
	$shapeColor = if ($i -ge 4) { $script:C.Warm } else { $script:C.Pale }
	Add-Rect $s $xPositions[$i] 205 112 74 $shapeColor $true 0x9CB4B0 | Out-Null
	Add-Text $s $labels[$i] ($xPositions[$i] + 7) 225 98 40 16 $script:C.Ink $true 'Aptos' 2 | Out-Null
	if ($i -lt $labels.Count - 1) { Add-Line $s ($xPositions[$i] + 114) 242 ($xPositions[$i + 1] - 7) 242 $script:C.Muted 1.8 | Out-Null }
}
Add-Text $s 'Si 180 s s’écoulent après l’alarme :' 86 359 500 28 17 $script:C.Red $true | Out-Null
Add-Rect $s 585 341 225 63 $script:C.Warm $true 0xD6A28E | Out-Null
Add-Text $s 'TIMEOUT\nrestants enregistrés' 595 350 205 48 15 $script:C.WarmInk $true 'Aptos' 2 | Out-Null
Add-Text $s 'Le chronomètre d’évacuation démarre au déclenchement de l’alarme.' 86 441 780 30 17 $script:C.Muted $false | Out-Null

# 5. Method
$s = New-Slide 5 '04 · Protocole du test B'
Add-Text $s 'On ne change qu’un facteur : la porte' 52 70 850 46 28 $script:C.Ink $true | Out-Null
$settings = @(
	@('60','agents'),
	@('40','force provisoire'),
	@('1','sortie'),
	@('0','pilier')
)
for ($i = 0; $i -lt $settings.Count; $i++) {
	$x = 65 + $i * 205
	Add-Rect $s $x 143 170 83 $script:C.Pale $true | Out-Null
	Add-Text $s $settings[$i][0] $x 153 170 36 25 $script:C.Ink $true 'Aptos' 2 | Out-Null
	Add-Text $s $settings[$i][1] $x 191 170 22 13 $script:C.Muted $false 'Aptos' 2 | Out-Null
}
Add-Text $s '6 largeurs' 70 275 180 28 18 $script:C.Red $true | Out-Null
$widths = @('0,8','1,0','1,2','1,5','2,0','3,0')
for ($i = 0; $i -lt $widths.Count; $i++) {
	$x = 70 + $i * 133
	Add-Rect $s $x 318 110 54 $script:C.White $true 0xB9CAC6 | Out-Null
	Add-Text $s ($widths[$i] + ' m') $x 331 110 28 15 $script:C.Ink $true 'Aptos' 2 | Out-Null
}
Add-Text $s '5 seeds par largeur  =  30 lancements' 70 405 700 34 22 $script:C.Ink $true | Out-Null
Add-Text $s 'Débit d’un essai complet = 60 agents ÷ temps d’évacuation' 70 452 790 26 16 $script:C.Muted $false | Out-Null

# 6. Results graph
$s = New-Slide 6 '05 · Résultats obtenus'
Add-Text $s 'La porte plus large améliore globalement le débit' 52 65 850 46 27 $script:C.Ink $true | Out-Null
Add-Text $s 'Débit moyen des évacuations complètes (agents/s)' 92 119 650 24 14 $script:C.Muted $false | Out-Null
$gx = 120.0; $gy = 175.0; $gw = 590.0; $gh = 250.0
$yMin = 2.0; $yMax = 3.7
foreach ($tick in @(2.0,2.5,3.0,3.5)) {
	$ty = $gy + $gh - (($tick - $yMin) / ($yMax - $yMin) * $gh)
	Add-Line $s $gx $ty ($gx + $gw) $ty $script:C.Grid 1 | Out-Null
	Add-Text $s ([string]::Format('{0:0.0}', $tick)) 74 ($ty - 8) 36 18 11 $script:C.Muted $false 'Aptos' 3 | Out-Null
}
Add-Line $s $gx $gy $gx ($gy + $gh) $script:C.Muted 1.4 | Out-Null
Add-Line $s $gx ($gy + $gh) ($gx + $gw) ($gy + $gh) $script:C.Muted 1.4 | Out-Null
$data = @(
	@(.8,2.327,'2,33*'),
	@(1.0,2.652,'2,65'),
	@(1.2,3.141,'3,14'),
	@(1.5,3.408,'3,41'),
	@(2.0,3.328,'3,33'),
	@(3.0,3.458,'3,46')
)
foreach ($point in $data) {
	$px = $gx + (($point[0] - 0.5) / 2.5 * $gw)
	$py = $gy + $gh - (($point[1] - $yMin) / ($yMax - $yMin) * $gh)
	$dot = $s.Shapes.AddShape(9, $px - 7, $py - 7, 14, 14)
	$dot.Fill.Solid(); $dot.Fill.ForeColor.RGB = $script:C.Red; $dot.Line.ForeColor.RGB = $script:C.White; $dot.Line.Weight = 1.5
	Add-Text $s $point[2] ($px - 28) ($py - 28) 56 18 11 $script:C.RedDark $true 'Aptos' 2 | Out-Null
	Add-Text $s ([string]::Format('{0:0.0}', [double]$point[0])) ($px - 24) ($gy + $gh + 9) 48 18 11 $script:C.Muted $false 'Aptos' 2 | Out-Null
}
Add-Text $s 'Largeur de porte (m)' 260 457 300 21 13 $script:C.Ink $true 'Aptos' 2 | Out-Null
Add-Rect $s 755 145 165 122 $script:C.Pale $true | Out-Null
Add-Text $s 'TENDANCE' 774 163 128 20 11 $script:C.Teal $true | Out-Null
Add-Text $s '+49 %' 774 188 130 38 27 $script:C.Ink $true | Out-Null
Add-Text $s 'entre 0,8* et 3 m' 774 230 136 25 12 $script:C.Muted $false | Out-Null
Add-Rect $s 755 284 165 159 $script:C.Warm $true | Out-Null
Add-Text $s 'TIMEOUTS' 774 300 128 20 11 $script:C.Red $true | Out-Null
Add-Text $s '0,8 m : 4/5\n1,5 m : 1/5\n3,0 m : 0/5' 774 330 134 90 17 $script:C.Ink $true | Out-Null
Add-Text $s '* Un seul essai complet à 0,8 m après retrait d’un doublon de seed 1; valeur provisoire.' 72 484 825 18 10 $script:C.WarmInk $false | Out-Null

# 7. Conclusion
$s = New-Slide 7 '06 · Conclusion'
Add-Text $s 'Ce que les résultats suggèrent' 52 70 850 46 28 $script:C.Ink $true | Out-Null
Add-Bullet $s 'Le débit augmente globalement avec la largeur de porte.' 75 150 790 20 | Out-Null
Add-Bullet $s 'L’amélioration n’est pas proportionnelle à la largeur.' 75 214 790 20 | Out-Null
Add-Bullet $s 'À 0,8 m, les blocages sont fréquents : 4 timeouts sur 5.' 75 278 790 20 | Out-Null
Add-Rect $s 75 354 800 105 $script:C.Warm $true | Out-Null
Add-Text $s 'Limite importante' 99 374 220 24 14 $script:C.Red $true | Out-Null
Add-Text $s 'Simulation qualitative : comportements et paramètres physiques simplifiés; elle ne prédit pas une évacuation réelle.' 99 407 725 38 17 $script:C.Ink $false | Out-Null
Add-Text $s 'Suite : terminer le test A (force), puis réaliser le test C (pilier).' 75 475 800 24 16 $script:C.Teal $true | Out-Null

$presentation.SaveAs($outputPath, 24)
$presentation.Close()
$ppt.Quit()
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($presentation)
[void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($ppt)
Write-Output "Presentation created: $outputPath"