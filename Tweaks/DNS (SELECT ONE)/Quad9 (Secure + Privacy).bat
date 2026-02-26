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
powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command \"$adapter = Get-NetAdapter | Where-Object Status -eq ''Up'' | Select-Object -First 1; Set-DnsClientServerAddress -InterfaceAlias $adapter.InterfaceAlias -ServerAddresses (''9.9.9.9'',''149.112.112.112'',''2620:fe::fe'',''2620:fe::9''); ipconfig /flushdns\"' -Verb RunAs"