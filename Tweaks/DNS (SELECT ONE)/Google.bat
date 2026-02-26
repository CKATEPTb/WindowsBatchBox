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
powershell -Command "Start-Process powershell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -Command \"$adapter = Get-NetAdapter | Where-Object Status -eq ''Up'' | Select-Object -First 1; Set-DnsClientServerAddress -InterfaceAlias $adapter.InterfaceAlias -ServerAddresses (''8.8.8.8'',''8.8.4.4'',''2001:4860:4860::8888'',''2001:4860:4860::8844''); ipconfig /flushdns\"' -Verb RunAs"