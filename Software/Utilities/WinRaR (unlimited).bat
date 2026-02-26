@echo off
set "____args="C:\Program Files\WinRAR\rarreg.key""
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
choco install winrar -y
echo empty > %____args%
del %____args%
echo RAR registration data>> %____args%
echo RAR development>> %____args%
echo Unlimited Company License>> %____args%
echo UID=69e66974c9e2d75162db>> %____args%
echo 641221225062db7601b9664e394012cc2e159149d57abd7a72b8bb>> %____args%
echo b0a5e2b7a697a823c98460fce6cb5ffde62890079861be57638717>> %____args%
echo 7131ced835ed65cc743d9777f2ea71a8e32c7e593cf66794343565>> %____args%
echo b41bcf56929486b8bcdac33d50ecf7739960675633a2e8b4777d6a>> %____args%
echo 0f49adde295e20f21003df02fd0f453cb340823f5f89476e4d4c00>> %____args%
echo e663688c47f1d6e22de0f7c20992313d45f64f3dad1eb3f260d623>> %____args%
echo 735ef3307bab8b5d8e2363334b9b5c19aacf7c2114e03040771384>> %____args%