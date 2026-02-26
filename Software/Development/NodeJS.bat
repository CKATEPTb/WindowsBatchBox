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
where node >nul 2>nul
if %ERRORLEVEL% neq 0 (
    choco install nodejs-lts -y
    goto :start_main
    exit /b
)
where pnpm >nul 2>nul
if %ERRORLEVEL% neq 0 (
	corepack install -g pnpm
	corepack enable pnpm
	pnpm setup
)
pause