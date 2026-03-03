@echo off
setlocal
set "___args="%~f0" %*"

fltmc > nul 2>&1 || (
    echo Administrator privileges are required.
    :start_main
    powershell -c "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList """/c $env:___args"""" 2> nul || (
        echo You must run this script as admin.
        if "%*"=="" pause
        exit /b 1
    )
    exit /b
)

cd /d "%~dp0"


where choco >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo [!] Installing Chocolatey...
    powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))"
    
    :: Обновляем PATH для текущего окна, чтобы сразу увидеть choco
    set "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"
    
    echo [OK] Chocolatey installed. Restarting logic...
    goto :start_main
)

set "PS_SOURCE=%~f0"
set "PS_TARGET=%~f0.ps1"

powershell -NoProfile -Command "$s=$env:PS_SOURCE; $t=$env:PS_TARGET; $txt=[System.IO.File]::ReadAllText($s,[System.Text.Encoding]::UTF8); $m=[regex]::Match($txt,'(?m)^#!ps1\r?\n(.*)$','Singleline'); $ps=$m.Groups[1].Value; [System.IO.File]::WriteAllText($t,$ps,[System.Text.UTF8Encoding]::new($true))"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS_TARGET%"
exit /b

#!ps1
Remove-Item -LiteralPath $MyInvocation.MyCommand.Path -Force -ErrorAction SilentlyContinue

# ScriptRunner.ps1 - TUI Script Runner

#region --- Enable Virtual Terminal Processing ---
$kernel32 = Add-Type -PassThru -Name 'Kernel32VT' -MemberDefinition '
    [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int h);
    [DllImport("kernel32.dll")] public static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll")] public static extern bool SetConsoleMode(IntPtr h, uint m);
'
$STDOUT = $kernel32::GetStdHandle(-11)
$mode   = 0
$kernel32::GetConsoleMode($STDOUT, [ref]$mode) | Out-Null
$kernel32::SetConsoleMode($STDOUT, $mode -bor 0x0004) | Out-Null  # ENABLE_VIRTUAL_TERMINAL_PROCESSING
#endregion

#region --- YAML Module ---
if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Write-Host "Installing powershell-yaml module..." -ForegroundColor Yellow
    Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowClobber
}
Import-Module powershell-yaml -ErrorAction Stop
#endregion

#region --- Config ---
$COLS        = 5
$CELL_WIDTH  = 20
$TOTAL_WIDTH = 2 + $COLS * ($CELL_WIDTH + 3) - 1
#endregion

#region --- ANSI Colors ---
$ESC = [char]27
$ANSI = @{
    DarkGray   = "$ESC[90m"
    Gray       = "$ESC[37m"
    Green      = "$ESC[32m"
    Yellow     = "$ESC[33m"
    DarkYellow = "$ESC[33m"
    Cyan       = "$ESC[96m"
    DarkCyan   = "$ESC[36m"
    Black      = "$ESC[30m"
    BgCyan     = "$ESC[46m"
    Reset      = "$ESC[0m"
}
$DEPTH_COLORS = @("$ESC[33m", "$ESC[36m", "$ESC[93m", "$ESC[96m")
#endregion

#region --- Load YAML Scripts ---
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Load-YamlScripts {
    param([string]$rootPath)
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    Get-ChildItem -Path $rootPath -Recurse -Include "*.yaml","*.yml" | ForEach-Object {
        try {
            $raw  = Get-Content $_.FullName -Raw
            $data = ConvertFrom-Yaml $raw
            if ($data -and $data.name -and $data.script) {
                $rel   = $_.DirectoryName.Substring($rootPath.Length).TrimStart('\','/')
                # All folder parts = full category path, unlimited depth
                $parts = @($rel -split '[/\\]' | Where-Object { $_ -ne '' })
                $results.Add([PSCustomObject]@{
                    Name        = [string]$data.name
                    Script      = [string]$data.script
                    Depends     = if ($data.depends) { [string[]]@($data.depends) } else { [string[]]@() }
					Includes    = if ($data.includes) { [string[]]@($data.includes) } else { [string[]]@() }
                    Description = if ($data.description) { [string]$data.description } else { '' }
                    # CategoryPath = array of folder names, e.g. @('dev','runtimes','lts')
                    CategoryPath = $(if ($parts.Count -gt 0) { [string[]]$parts } else { [string[]]@('General') })
					FilePath     = [string]$_.FullName
                    Selected     = [bool]$false
                    IsDep        = [bool]$false
					IsInc       = [bool]$false
                })
            }
        } catch {}
    }
    return $results
}

[PSCustomObject[]]$allScripts = @(Load-YamlScripts -rootPath $scriptRoot | Sort-Object { [string[]]$_.CategoryPath -join '/' }, Name)

if ($allScripts.Count -eq 0) {
    $allYaml = @(Get-ChildItem -Path $scriptRoot -Recurse -Include "*.yaml","*.yml")
    Write-Host "No valid YAML script files found." -ForegroundColor Red
    Write-Host "Search root: $scriptRoot" -ForegroundColor Yellow
    Write-Host "Total .yaml/.yml files found: $($allYaml.Count)" -ForegroundColor Yellow
    if ($allYaml.Count -gt 0) {
        Write-Host "Files detected:" -ForegroundColor Yellow
        foreach ($f in $allYaml) {
            Write-Host "  $($f.FullName)" -ForegroundColor Gray
            try {
                $raw  = Get-Content $f.FullName -Raw
                $data = ConvertFrom-Yaml $raw
                $hasName   = [bool]($data -and $data.name)
                $hasScript = [bool]($data -and $data.script)
                Write-Host "    name=$hasName script=$hasScript" -ForegroundColor DarkGray
            } catch {
                Write-Host "    PARSE ERROR: $_" -ForegroundColor Red
            }
        }
    }
    Read-Host "Press Enter to exit"; exit
}
#endregion

#region --- Index map ---
$scriptIndexMap = @{}
for ($i = 0; $i -lt $allScripts.Count; $i++) {
    $scriptIndexMap[$allScripts[$i].Name] = $i
}
#endregion

#region --- Build Grid Rows ---
# Build an ordered tree from flat script list using CategoryPath arrays.
# Each node: @{ Name; Children=ordered hashtable of subnodes; Scripts=list }
function New-TreeNode([string]$name) {
    return @{
        Name     = $name
        Children = @{}   # plain hashtable, keys sorted manually when iterating
        Scripts  = [System.Collections.Generic.List[PSCustomObject]]::new()
    }
}

function Build-Tree([PSCustomObject[]]$scripts) {
    $root = New-TreeNode '__root__'
    foreach ($s in $scripts) {
        $node  = $root
        $parts = [string[]]$s.CategoryPath
        foreach ($part in $parts) {
            if (-not $node.Children.ContainsKey($part)) {
                $node.Children[$part] = New-TreeNode $part
            }
            $node = $node.Children[$part]
        }
        $node.Scripts.Add($s)
    }
    return $root
}

function Flatten-Tree {
    param($node, [int]$depth, [System.Collections.Generic.List[hashtable]]$rowList, [hashtable]$idxMap, [int]$cols)

    # Scripts directly in this category
    $sorted = @($node.Scripts | Sort-Object Name)
    for ($i = 0; $i -lt $sorted.Count; $i += $cols) {
        $end     = [Math]::Min($i + $cols - 1, $sorted.Count - 1)
        $idxList = [int[]]@($sorted[$i..$end] | ForEach-Object { $idxMap[$_.Name] })
        $rowList.Add(@{ T='items'; Items=$idxList })
    }

    # Recurse into children sorted by name
    $sortedKeys = @($node.Children.Keys | Sort-Object)
    foreach ($key in $sortedKeys) {
        $child  = $node.Children[$key]
        $rowList.Add(@{ T='cat'; Label=$child.Name; Depth=$depth })
        Flatten-Tree -node $child -depth ($depth + 1) -rowList $rowList -idxMap $idxMap -cols $cols
    }
}

function Build-Rows {
    param([PSCustomObject[]]$scripts, [hashtable]$idxMap, [int]$cols)
    $rowList = [System.Collections.Generic.List[hashtable]]::new()
    $tree    = Build-Tree $scripts
    $sortedKeys = @($tree.Children.Keys | Sort-Object)
    foreach ($key in $sortedKeys) {
        $child = $tree.Children[$key]
        $rowList.Add(@{ T='cat'; Label=$child.Name; Depth=0 })
        Flatten-Tree -node $child -depth 1 -rowList $rowList -idxMap $idxMap -cols $cols
    }
    return $rowList
}

$rows   = Build-Rows -scripts $allScripts -idxMap $scriptIndexMap -cols $COLS

# Flat nav map
$navMap = [System.Collections.Generic.List[hashtable]]::new()
for ($r = 0; $r -lt $rows.Count; $r++) {
    if ($rows[$r].T -eq 'items') {
        for ($c = 0; $c -lt $rows[$r].Items.Count; $c++) {
            $navMap.Add(@{ R=$r; C=$c })
        }
    }
}
#endregion

#region --- Dependency Helpers ---
function Get-AllDependencies([string[]]$names, [ref]$visited) {
    foreach ($name in $names) {
        if ($visited.Value -notcontains $name) {
            $visited.Value += $name
            $dep = $allScripts | Where-Object { $_.Name -eq $name } | Select-Object -First 1
            if ($dep -and $dep.Depends.Count -gt 0) {
                Get-AllDependencies ([string[]]$dep.Depends) $visited
            }
        }
    }
}

function Get-AllIncludes([string[]]$names, [ref]$visited) {
   foreach ($name in $names) {
        if ($visited.Value -notcontains $name) {
            $visited.Value += $name
            $s = $allScripts | Where-Object { $_.Name -eq $name } | Select-Object -First 1
            if ($s -and $s.Includes.Count -gt 0) {
                Get-AllIncludes ([string[]]$s.Includes) $visited
            }
        }
    }
}

function Update-DepMarkers {
    foreach ($s in $allScripts) { $s.IsDep = $false; $s.IsInc = $false }

    # Сначала собираем ВСЕ dep-скрипты (включая транзитивные)
    $allDepNames = [string[]]@()
    foreach ($s in $allScripts) {
        if (-not $s.Selected -or $s.Depends.Count -eq 0) { continue }
        $deps = [string[]]@()
        Get-AllDependencies ([string[]]$s.Depends) ([ref]$deps)
        foreach ($depName in $deps) {
            $d = $allScripts | Where-Object { $_.Name -eq $depName } | Select-Object -First 1
            if ($d -and -not $d.Selected) {
                $d.IsDep = $true
                if ($allDepNames -notcontains $depName) { $allDepNames += $depName }
            }
        }
    }

    # Теперь ищем includes у: [X] + [D] — по всей цепочке
    $sourceNames = [string[]]@(
        @($allScripts | Where-Object { $_.Selected } | ForEach-Object { $_.Name }) +
        $allDepNames
    )
    foreach ($sourceName in $sourceNames) {
        $src = $allScripts | Where-Object { $_.Name -eq $sourceName } | Select-Object -First 1
        if (-not $src -or $src.Includes.Count -eq 0) { continue }
        $incs = [string[]]@()
        Get-AllIncludes ([string[]]$src.Includes) ([ref]$incs)
        foreach ($incName in $incs) {
            $inc = $allScripts | Where-Object { $_.Name -eq $incName } | Select-Object -First 1
            if ($inc -and -not $inc.Selected -and -not $inc.IsDep) { $inc.IsInc = $true }
        }
    }
}
#endregion

#region --- Text Helpers ---
function PadCell([string]$text, [int]$w) {
    if ($text.Length -ge $w) { return $text.Substring(0, $w) }
    return $text.PadRight($w)
}

function WrapText([string]$text, [int]$maxW) {
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($raw in ($text -split "`r?`n")) {
        if ($raw.Length -eq 0) { $lines.Add(''); continue }
        $p = 0
        while ($p -lt $raw.Length) {
            $lines.Add($raw.Substring($p, [Math]::Min($maxW, $raw.Length - $p)))
            $p += $maxW
        }
    }
    if ($lines.Count -eq 0) { $lines.Add('') }
    return $lines
}

function ItemLabel([PSCustomObject]$s) {
    $maxN = $CELL_WIDTH - 4
    $name = $s.Name
    if ($name.Length -gt $maxN) { $name = $name.Substring(0, $maxN - 3) + '...' }
    $px = if ($s.Selected) { '[X]' } elseif ($s.IsDep) { '[D]' } elseif ($s.IsInc) { '[A]' } else { '[ ]' }
    return "$px $name"
}
#endregion

#region --- Edit YAML ---
function Edit-CurrentScript([PSCustomObject]$s) {
    if (-not $s) { return }
    $filePath = $s.FilePath
    if (-not $filePath -or -not (Test-Path $filePath)) { return }

    Start-Process $filePath
}
#endregion

#region --- Cursor ---
$navIdx       = 0
$scrollOffset = 0
$lastGridHeight = 0

function CurR { return $navMap[$navIdx].R }
function CurC { return $navMap[$navIdx].C }
function CurScript {
    $r = $rows[(CurR)]
    return $allScripts[$r.Items[(CurC)]]
}

function MoveCursor([string]$dir) {
    $r = CurR; $c = CurC
    switch ($dir) {
        'Up' {
            for ($i = $navIdx - 1; $i -ge 0; $i--) {
                if ($navMap[$i].R -lt $r) {
                    $targetRow = $navMap[$i].R
                    $bestDist  = 999; $bestIdx = $i
                    for ($j = 0; $j -lt $navMap.Count; $j++) {
                        if ($navMap[$j].R -eq $targetRow) {
                            $dist = [Math]::Abs($navMap[$j].C - $c)
                            if ($dist -lt $bestDist) { $bestDist = $dist; $bestIdx = $j }
                        }
                    }
                    $script:navIdx = $bestIdx; return
                }
            }
        }
        'Down' {
            for ($i = $navIdx + 1; $i -lt $navMap.Count; $i++) {
                if ($navMap[$i].R -gt $r) {
                    $targetRow = $navMap[$i].R
                    $bestDist  = 999; $bestIdx = $i
                    for ($j = 0; $j -lt $navMap.Count; $j++) {
                        if ($navMap[$j].R -eq $targetRow) {
                            $dist = [Math]::Abs($navMap[$j].C - $c)
                            if ($dist -lt $bestDist) { $bestDist = $dist; $bestIdx = $j }
                        }
                    }
                    $script:navIdx = $bestIdx; return
                }
            }
        }
        'Left'  { if ($navIdx -gt 0) { $script:navIdx-- } }
        'Right' { if ($navIdx -lt $navMap.Count - 1) { $script:navIdx++ } }
    }
}
#endregion

#region --- Render ---
function RenderTUI {
    $w      = $TOTAL_WIDTH
    $innerW = $w - 4
    $winH   = $host.UI.RawUI.WindowSize.Height
    $SEP    = '=' * $w

    $curR = CurR
    $curC = CurC
    $curS = CurScript

    # --- Layout constants (1-based row numbers) ---
    # Header: rows 1-2  (helpbar + SEP)
    # Grid:   rows 3 .. (winH - footerLines)
    # Footer: last N rows

    $descPfxLen = 13
    $descWrapW  = $innerW - $descPfxLen
    if ($descWrapW -lt 10) { $descWrapW = 10 }
    $descTxt   = if ($curS) { $curS.Description } else { '' }
    $descLines = WrapText $descTxt $descWrapW

    # footer = SEP + Name + Desc lines + SEP + Status + SEP
    $footerLines = 1 + 1 + $descLines.Count + 1 + 1 + 1
    $headerLines = 2   # helpbar + SEP

    $gridStartRow = $headerLines + 1          # 1-based
    $gridH        = $winH - $headerLines - $footerLines
    if ($gridH -lt 1) { $gridH = 1 }

    $footerStartRow = $gridStartRow + $gridH  # 1-based
    # --- Scroll guard (visual-line aware) ---
    function Count-VisualLines([int]$fromRow, [int]$toRow) {
        $count = 0
        for ($rr = $fromRow; $rr -lt $toRow -and $rr -lt $rows.Count; $rr++) {
            $count++
            $ni = $rr + 1
            $nextIsTopCat = ($ni -ge $rows.Count -or ($rows[$ni].T -eq 'cat' -and $rows[$ni].Depth -eq 0))
            if ($nextIsTopCat) { $count++ }
        }
        return $count
    }

    if ($curR -lt $scrollOffset) { $script:scrollOffset = $curR }
    if ((Count-VisualLines -fromRow $scrollOffset -toRow $curR) -ge $gridH) {
        while ((Count-VisualLines -fromRow $script:scrollOffset -toRow $curR) -ge $gridH) {
            $script:scrollOffset++
        }
    }
    if ($script:scrollOffset -lt 0) { $script:scrollOffset = 0 }
    # Collect output as array of strings + color info
    # Use a simple parallel arrays approach: texts[], fgs[], bgs[]
    # But for item rows we need per-segment coloring, so use a different flag
    # Strategy: build list of "print commands" as hashtables
    $cmds = [System.Collections.Generic.List[hashtable]]::new()

    $sb = [System.Text.StringBuilder]::new(16384)


    # Help bar
    $hbar = "| " + (PadCell "WindowsBatchBox" $CELL_WIDTH) + " | " +
					(PadCell "Navigate: [↑/↓/←/→]" $CELL_WIDTH) + " | " +
                   (PadCell "Select: [SPACE]" $CELL_WIDTH) + " | " +
                   (PadCell "Process: [ENTER]" $CELL_WIDTH) + " | " +
                   (PadCell "github.com/CKATEPTb" $CELL_WIDTH) + " |"
    [void]$sb.Append("$ESC[1;1H")
    [void]$sb.Append($ANSI.DarkGray + $hbar + $ANSI.Reset)
    [void]$sb.Append("$ESC[2;1H")
    [void]$sb.Append($ANSI.DarkGray + $SEP + $ANSI.Reset)

    # ---- GRID (rows gridStartRow .. gridStartRow+gridH-1) ----
    $gridPrinted = 0
    for ($r = $scrollOffset; $r -lt $rows.Count -and $gridPrinted -lt $gridH; $r++) {
        $printRow = $gridStartRow + $gridPrinted
        [void]$sb.Append("$ESC[${printRow};1H")
        $row = $rows[$r]

        if ($row.T -eq 'cat') {
            $prefix = '+-' * ($row.Depth + 1)
            $label  = "$prefix<$($row.Label)>"
            $rest   = ':' + ' ' * ([Math]::Max(0, $innerW - $label.Length - 1))
            $catFG  = $DEPTH_COLORS[$row.Depth % $DEPTH_COLORS.Count]
            [void]$sb.Append($ANSI.DarkGray + '| ' + $ANSI.Reset)
            [void]$sb.Append($catFG + $label + $ANSI.Reset)
            [void]$sb.Append($ANSI.DarkGray + $rest + ' |' + $ANSI.Reset)
            $gridPrinted++
        } else {
            [void]$sb.Append($ANSI.DarkGray + '| ' + $ANSI.Reset)
            for ($c = 0; $c -lt $COLS; $c++) {
                if ($c -gt 0) { [void]$sb.Append($ANSI.DarkGray + ' | ' + $ANSI.Reset) }
                if ($c -lt $row.Items.Count) {
                    $si       = $row.Items[$c]
                    $s        = $allScripts[$si]
                    $lbl      = PadCell (ItemLabel $s) $CELL_WIDTH
                    $isCursor = ($r -eq $curR -and $c -eq $curC)
                    if ($isCursor) {
                        [void]$sb.Append($ANSI.Black + $ANSI.BgCyan + $lbl + $ANSI.Reset)
                    } elseif ($s.Selected) {
                        [void]$sb.Append($ANSI.Green + $lbl + $ANSI.Reset)
                    } elseif ($s.IsDep -or $s.IsInc) {
                        [void]$sb.Append($ANSI.Yellow + $lbl + $ANSI.Reset)
                    } else {
                        [void]$sb.Append($ANSI.Gray + $lbl + $ANSI.Reset)
                    }
                } else {
                    [void]$sb.Append(' ' * $CELL_WIDTH)
                }
            }
            [void]$sb.Append($ANSI.DarkGray + ' |' + $ANSI.Reset)
            $gridPrinted++
        }

        # Auto-SEP between top-level categories
        $ni = $r + 1
        $nextIsTopCat = ($ni -ge $rows.Count -or ($rows[$ni].T -eq 'cat' -and $rows[$ni].Depth -eq 0))
        if ($gridPrinted -lt $gridH -and $nextIsTopCat) {
            $printRow = $gridStartRow + $gridPrinted
            [void]$sb.Append("$ESC[${printRow};1H")
            [void]$sb.Append($ANSI.DarkGray + $SEP + $ANSI.Reset)
            $gridPrinted++
        }
    }

    # Clear leftover grid lines if grid shrank
    while ($gridPrinted -lt $script:lastGridHeight) {
        $printRow = $gridStartRow + $gridPrinted
        [void]$sb.Append("$ESC[${printRow};1H" + ' ' * $w)
        $gridPrinted++
    }
    $script:lastGridHeight = $gridPrinted

    # ---- FOOTER (fixed, rows footerStartRow..) ----
    $fr = $footerStartRow

    [void]$sb.Append("$ESC[${fr};1H")
    [void]$sb.Append($ANSI.DarkGray + $SEP + $ANSI.Reset)
    $fr++
    $curName  = if ($curS) { $curS.Name } else { '' }
    $nameFG   = if ($curS -and $curS.Selected) { $ANSI.Green }
                elseif ($curS -and ($curS.IsDep -or $curS.IsInc)) { $ANSI.Yellow }
                else { $ANSI.Gray }
    $nameLine = PadCell "Name: $curName" $innerW
    [void]$sb.Append("$ESC[${fr};1H")
    [void]$sb.Append($nameFG + "| $nameLine |" + $ANSI.Reset)
    $fr++
    # Description lines
    $firstD = $true
    foreach ($dl in $descLines) {
        $pfx     = if ($firstD) { 'Description: ' } else { ' ' * $descPfxLen }
        $content = PadCell ($pfx + $dl) $innerW
        [void]$sb.Append("$ESC[${fr};1H")
        [void]$sb.Append($ANSI.DarkGray + "| $content |" + $ANSI.Reset)
        $fr++
        $firstD = $false
    }

    [void]$sb.Append("$ESC[${fr};1H")
    [void]$sb.Append($ANSI.DarkGray + $SEP + $ANSI.Reset)
    $fr++

	$selCount = 0
	$affCount = 0
	foreach ($s in $allScripts) {
		if ($s.Selected) { $selCount++ }
		if ($s.IsDep -or $s.IsInc -or $s.Selected)    { $affCount++ }
	}
    $statLine = (PadCell "Selected: $selCount" $CELL_WIDTH) + " | " +
				(PadCell "Total: $affCount" $CELL_WIDTH) + " | " +
                (PadCell "Reload: [R]" $CELL_WIDTH) + " | " +
                (PadCell "Edit: [E]" $CELL_WIDTH) + " | " +
                (PadCell "Quit: [Q/ESC]" $CELL_WIDTH)
    [void]$sb.Append("$ESC[${fr};1H")
    [void]$sb.Append($ANSI.DarkGray + "| $statLine |" + $ANSI.Reset)
    $fr++

    [void]$sb.Append("$ESC[${fr};1H")
    [void]$sb.Append($ANSI.DarkGray + $SEP + $ANSI.Reset)


    [Console]::Write($sb.ToString())
}
#endregion

#region --- Execution ---
function Resolve-ExecutionOrder([string[]]$sel) {
    $order   = [System.Collections.Generic.List[string]]::new()
    $visited = @{}
    function Visit([string]$name) {
        if ($visited[$name]) { return }
        $visited[$name] = 'v'
        $s = $allScripts | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($s -and $s.Depends.Count -gt 0) { foreach ($d in $s.Depends) { Visit $d } }
        $visited[$name] = 'done'
        if (-not $order.Contains($name)) { $order.Add($name) }
    }
    foreach ($n in $sel) { Visit $n }
    return $order
}

function Run-Scripts([string[]]$selectedNames) {
    [Console]::Clear()
    $SEP2 = '=' * $TOTAL_WIDTH
    Write-Host $SEP2 -ForegroundColor DarkGray
    Write-Host "  Executing Scripts" -ForegroundColor Cyan
    Write-Host $SEP2 -ForegroundColor DarkGray

    $execOrder = Resolve-ExecutionOrder $selectedNames
    $results   = [ordered]@{}

    foreach ($name in $execOrder) {
        $s = $allScripts | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if (-not $s) { continue }
        $isDep    = $selectedNames -notcontains $name
        $tag      = if ($isDep) { '[DEP]' } else { '[RUN]' }
        $tagColor = if ($isDep) { 'Yellow' } else { 'Cyan' }
        Write-Host "  $tag $name" -ForegroundColor $tagColor

        $depFailed = $false
        foreach ($dep in $s.Depends) {
            if ($results.Contains($dep) -and -not $results[$dep].Success) {
                Write-Host "        ! Dependency '$dep' failed - skipping." -ForegroundColor Red
                $depFailed = $true; break
            }
        }
        if ($depFailed) {
            $results[$name] = @{ Success=$false; Error='Dependency failed'; Name=$name }
            continue
        }

        $tmpBat = $null
        try {
            $base   = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName())
            $tmpBat = $base + ".bat"

            $batLines = [System.Collections.Generic.List[string]]::new()
            $batLines.Add('@echo off')
			$batLines.Add('where refreshenv >nul 2>nul && call refreshenv >nul 2>nul')
            foreach ($scriptLine in ($s.Script -split "`r?`n")) {
                $batLines.Add($scriptLine)
            }
            $batLines.Add('exit /b %errorlevel%')
            [System.IO.File]::WriteAllLines($tmpBat, $batLines, [System.Text.Encoding]::Default)

            Write-Host ""
            Write-Host "  -- Output: $name --" -ForegroundColor DarkGray
			
			if (Get-Command refreshenv -ErrorAction SilentlyContinue) {
				refreshenv 2>&1 | Out-Null
			}
						
			$env:SCRIPT_SOURCE = $s.FilePath

            # Run the .bat via Start-Process — output is shown live in current console window
            $proc = Start-Process cmd -ArgumentList "/c `"$tmpBat`"" -Wait -NoNewWindow -PassThru
            $code = $proc.ExitCode

            Write-Host "  -- End: $name (exit $code) --" -ForegroundColor DarkGray
            Write-Host ""

            if ($code -ne 0 -and $code -ne -1978335189) { throw "Exit code: $code" }
            Write-Host "  [OK] $name" -ForegroundColor Green
            $results[$name] = @{ Success=$true; Name=$name }
        } catch {
            $err = $_.Exception.Message
            Write-Host "  [FAIL] $name : $err" -ForegroundColor Red
            $results[$name] = @{ Success=$false; Error=$err; Name=$name }
        } finally {
            if ($tmpBat -and (Test-Path $tmpBat)) {
                Remove-Item $tmpBat -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Write-Host ""
    Write-Host $SEP2 -ForegroundColor DarkGray
    Write-Host "  Summary" -ForegroundColor Cyan
    Write-Host $SEP2 -ForegroundColor DarkGray
    foreach ($r in $results.Values) {
        if ($r.Success) { Write-Host "  OK    $($r.Name)" -ForegroundColor Green }
        else            { Write-Host "  FAIL  $($r.Name): $($r.Error)" -ForegroundColor Red }
    }
    Write-Host $SEP2 -ForegroundColor DarkGray
    Read-Host "`nPress Enter to return to menu"
}
#endregion

#region --- Main Loop ---
[Console]::CursorVisible = $false
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$host.UI.RawUI.WindowTitle = "WindowsBatchBox"
[Console]::Clear()

try {
    while ($true) {
        RenderTUI
        $key = $host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        $vk  = $key.VirtualKeyCode

        if ($vk -eq 27 -or $vk -eq 81) { break }

        switch ($vk) {
            38 { MoveCursor 'Up'    }
            40 { MoveCursor 'Down'  }
            37 { MoveCursor 'Left'  }
            39 { MoveCursor 'Right' }
            32 {
                $s = CurScript
                $s.Selected = -not $s.Selected
                Update-DepMarkers
            }
            13 {
                $selNames = [string[]]@($allScripts | Where-Object { $_.Selected } | ForEach-Object { $_.Name })
                if ($selNames.Count -eq 0) { $selNames = [string[]]@((CurScript).Name) }
                Run-Scripts $selNames
                [Console]::Clear()
                $script:lastGridHeight = 0
            }
            69 {
                # E key — open current script YAML in editor
                Edit-CurrentScript (CurScript)
            }
            82 {
                # R key (VirtualKeyCode 82) — reload YAML files and rebuild grid
                [PSCustomObject[]]$script:allScripts = @(Load-YamlScripts -rootPath $scriptRoot | Sort-Object { [string[]]$_.CategoryPath -join '/' }, Name)

                $script:scriptIndexMap = @{}
                for ($i = 0; $i -lt $script:allScripts.Count; $i++) {
                    $script:scriptIndexMap[$script:allScripts[$i].Name] = $i
                }

                $script:rows = Build-Rows -scripts $script:allScripts -idxMap $script:scriptIndexMap -cols $COLS

                $script:navMap = [System.Collections.Generic.List[hashtable]]::new()
                for ($r2 = 0; $r2 -lt $script:rows.Count; $r2++) {
                    if ($script:rows[$r2].T -eq 'items') {
                        for ($c2 = 0; $c2 -lt $script:rows[$r2].Items.Count; $c2++) {
                            $script:navMap.Add(@{ R=$r2; C=$c2 })
                        }
                    }
                }

                $script:navIdx         = 0
                $script:scrollOffset   = 0
                $script:lastGridHeight = 0
                [Console]::Clear()
            }
        }
    }
} finally {
    [Console]::CursorVisible = $true
    [Console]::Clear()
}
#endregion