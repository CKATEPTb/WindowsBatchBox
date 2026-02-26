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
powershell -NoProfile -ExecutionPolicy Bypass -Command "New-Item -ItemType Directory -Path (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerToys\Backup') -Force | Out-Null; Copy-Item '%~dp0PowerToys.ptb' (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerToys\Backup\settings_134166177889566293.ptb') -Force -ErrorAction Stop"
choco install powertoys -y