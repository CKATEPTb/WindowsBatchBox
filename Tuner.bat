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

chcp 65001 >nul

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$files = Get-ChildItem -Recurse -Filter *.bat | Where-Object { $_.FullName -ne '%~f0' }; " ^
    "$items = $files | Sort-Object @{Expression={$_.DirectoryName}}, @{Expression={$_.Name.ToLower()}} | " ^
    "foreach { [PSCustomObject]@{ Name=$_.Name; Path=$_.FullName; Folder=$_.DirectoryName; Selected=$false } }; " ^
    "if (-not $items) { Write-Host 'No .bat files found!' -Fore Red; exit }; " ^
    "$cols = 3; $current = 0; " ^
    "while($true) { " ^
    "    Clear-Host; " ^
    "    Write-Host ' NAVIGATION: ' -NoNewline; Write-Host '[↑][↓][←][→]' -Fore Cyan -NoNewline; " ^
    "    Write-Host ' | SELECT: ' -NoNewline; Write-Host '[SPACE]' -Fore Cyan -NoNewline; " ^
    "    Write-Host ' | RUN QUEUE: ' -NoNewline; Write-Host '[ENTER]' -Fore Cyan; " ^
    "    $lastFolder = ''; $colIdx = 0; " ^
    "    for ($i=0; $i -lt $items.Count; $i++) { " ^
    "        if ($items[$i].Folder -ne $lastFolder) { " ^
    "            $lastFolder = $items[$i].Folder; " ^
    "            $displayFolder = $lastFolder.Replace($PWD.Path, '.'); " ^
    "            if ($colIdx -ne 0) { Write-Host ''; $colIdx = 0 }; " ^
    "            Write-Host \"`n── $displayFolder \" -Fore Yellow; " ^
    "        } " ^
    "        $ptr = if ($i -eq $current) { '>' } else { ' ' }; " ^
    "        $chk = if ($items[$i].Selected) { '[x]' } else { '[ ]' }; " ^
    "        $name = if ($items[$i].Name.Length -gt 20) { $items[$i].Name.Substring(0,17)+'...' } else { $items[$i].Name }; " ^
    "        $text = ('{0}{1} {2}' -f $ptr, $chk, $name).PadRight(26); " ^
    "        if ($i -eq $current) { Write-Host $text -Back White -Fore Black -NoNewline } else { Write-Host $text -NoNewline }; " ^
    "        $colIdx++; if ($colIdx %% $cols -eq 0) { Write-Host ''; $colIdx = 0 }; " ^
    "    } " ^
    "    Write-Host \"`n`n[PATH]: $($items[$current].Path)\" -Fore DarkGray; " ^
    "    $key = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); " ^
    "    $code = $key.VirtualKeyCode; " ^
    "    if ($code -eq 37) { $current = [Math]::Max(0, $current - 1) } " ^
    "    elseif ($code -eq 39) { $current = [Math]::Min($items.Count - 1, $current + 1) } " ^
    "    elseif ($code -eq 38) { $current = [Math]::Max(0, $current - $cols) } " ^
    "    elseif ($code -eq 40) { $current = [Math]::Min($items.Count - 1, $current + $cols) } " ^
    "    elseif ($code -eq 32) { $items[$current].Selected = !$items[$current].Selected } " ^
    "    elseif ($code -eq 13) { " ^
    "        $toRun = $items | Where-Object { $_.Selected }; " ^
    "        if (-not $toRun) { $toRun = $items[$current] }; " ^
    "        foreach($f in $toRun) { " ^
    "            Clear-Host; " ^
    "            Write-Host \"Executing: $($f.Name)...\" -Fore Cyan; " ^
    "            $process = Start-Process cmd -ArgumentList \"/c `\"`\"$($f.Path)`\"`\"\" -Wait -NoNewWindow -PassThru; " ^
    "            if ($process.ExitCode -ne 0) { " ^
    "                Write-Host \"`n[!] Error in $($f.Name) (Exit Code: $($process.ExitCode))\" -Fore Red; " ^
    "                Write-Host 'Press any key to continue...' -Fore Gray; " ^
    "                $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); " ^
    "            } " ^
    "        } " ^
    "        Write-Host \"`nAll tasks finished. Press any key to return to menu...\" -Fore Green; " ^
    "        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown'); " ^
    "    } " ^
    "    elseif ($code -eq 27) { break }; " ^
    "}"

pause