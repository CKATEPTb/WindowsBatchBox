@echo off
set "___args="%~f0" %*"
fltmc > nul 2>&1 || (
	echo Administrator privileges are required.
	powershell -c "Start-Process -Verb RunAs -FilePath 'cmd' -ArgumentList """/c $env:___args"""" 2> nul || (
		echo You must run this script as admin.
		if "%*"=="" pause
		exit /b 1
	)
	exit /b
)
cd /d "%~dp0"
set "PRESET_PATH=%~dp0preset.json"

powershell -NoProfile -ExecutionPolicy Bypass -Command "irm "https://christitus.com/win" | iex"