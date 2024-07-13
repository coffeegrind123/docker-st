@echo off

REM Check if Git is installed using winget
winget list -e | findstr /i /C:"Git" >nul
if %errorlevel% neq 0 (
    echo Git is not installed. Installing Git...
    winget install --id Git.Git -e
)

set "directory=.\SillyTavern"

if exist "%directory%" (
    echo Directory exists. Pulling from the repository.
    cd "%directory%"
    git pull
) else (
    echo Directory does not exist. Cloning from the repository.
    git clone https://github.com/SillyTavern/SillyTavern -b staging "%directory%"
    cd "%directory%"
)

xcopy /s /e /y "..\replace\SillyTavern" ".\"

REM Check if it's the first run
cd docker
docker compose up -d

REM Close the command prompt after the script finishes
pause
exit
