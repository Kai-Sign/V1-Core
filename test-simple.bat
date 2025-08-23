@echo off
REM Simple testing script

echo Running KaiSign tests...

if "%1"=="fork" (
    echo Testing with Sepolia fork...
    if "%SEPOLIA_RPC_URL%"=="" (
        echo ERROR: Set SEPOLIA_RPC_URL in .env file first
        exit /b 1
    )
    forge test --fork-url %SEPOLIA_RPC_URL% -vv
) else (
    echo Running local tests...
    forge test -vv
)

echo Done!