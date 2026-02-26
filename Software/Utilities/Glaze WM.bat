@echo off
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
where cargo >nul 2>nul
if %ERRORLEVEL% neq 0 (
    winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--passive --wait --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    winget install --id Rustlang.Rustup --source winget --accept-package-agreements --accept-source-agreements
    goto :start_main
    exit /b
)
choco install glazewm -y
cargo install --git https://github.com/Dutch-Raptor/GAT-GWM.git --features=no_console

cd /d "%~dp0"
if not exist "%USERPROFILE%\.glzr\glazewm" mkdir "%USERPROFILE%\.glzr\glazewm"
copy /Y "Glaze WM.yaml" "%USERPROFILE%\.glzr\glazewm\config.yaml"