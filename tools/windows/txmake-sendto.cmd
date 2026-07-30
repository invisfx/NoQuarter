@echo off
rem ============================================================================
rem  txmake-sendto.cmd
rem
rem  Converts image files to RenderMan .tx textures, writing each .tx into the
rem  same folder as its source image.
rem
rem  Install:
rem    1. Put this file somewhere stable, e.g. C:\Scripts\
rem    2. Win+R -> shell:sendto
rem    3. Right-drag this file into that folder -> "Create shortcuts here"
rem    4. Rename the shortcut to "Convert to .tx"
rem
rem  Usage:
rem    Select one or more images -> right-click -> Send to -> Convert to .tx
rem    (Windows 11: right-click -> Show more options -> Send to)
rem
rem  Also works from a command prompt:
rem    txmake-sendto.cmd "C:\tex\brick_diff.tif" "C:\tex\brick_spec.tif"
rem ============================================================================

setlocal enabledelayedexpansion

rem ---------------------------------------------------------------- config --
rem Flags handed to txmake. Edit to taste.
rem   -resize none    leave resolution alone (RenderMan does not need pow2)
rem   -mode periodic  tiling texture; use "clamp" for non-tiling maps
rem   -format openexr tiled mipmapped OpenEXR; "pixar" for the legacy format
rem   -compression    none | rle | zip | pxr24 | dwaa | dwab | lossless | lossy
set "TXOPTS=-resize none -mode periodic -format openexr -compression lossless"

rem Extensions this script is willing to hand to txmake.
set "IMAGE_EXTS=.tif .tiff .exr .png .jpg .jpeg .tga .bmp .hdr .dpx .cin .sgi .rgb .pic .gif"

rem 1 = skip a file when its .tx already exists and is newer than the source.
set "SKIP_EXISTING=1"

rem 1 = keep the console window open when everything succeeded.
set "ALWAYS_PAUSE=0"
rem ---------------------------------------------------------------------------

call :find_txmake
if not defined TXMAKE (
    echo.
    echo   ERROR: could not locate txmake.exe
    echo.
    echo   Fix this by doing one of:
    echo     * set RMANTREE to your RenderManProServer folder, or
    echo     * set TXMAKE_EXE to the full path of txmake.exe, or
    echo     * edit the fallback path in the :find_txmake section below.
    echo.
    pause
    exit /b 1
)

if "%~1"=="" (
    echo.
    echo   No files were passed to this script.
    echo   Select images in Explorer, then Send to ^> Convert to .tx
    echo.
    pause
    exit /b 1
)

echo Using: %TXMAKE%
echo Flags: %TXOPTS%
echo.

set /a COUNT_OK=0
set /a COUNT_FAIL=0
set /a COUNT_SKIP=0

:arg_loop
if "%~1"=="" goto :summary
call :convert_one "%~1"
shift
goto :arg_loop

rem ===========================================================================
:convert_one
set "SRC=%~1"
set "EXT=%~x1"
set "DST=%~dpn1.tx"

if exist "%SRC%\" (
    echo   [skip] %~nx1 - is a folder, not an image
    set /a COUNT_SKIP+=1
    goto :eof
)

if not exist "%SRC%" (
    echo   [skip] %~nx1 - not found
    set /a COUNT_SKIP+=1
    goto :eof
)

if /i "%EXT%"==".tx" (
    echo   [skip] %~nx1 - already a .tx
    set /a COUNT_SKIP+=1
    goto :eof
)

set "MATCH="
for %%E in (%IMAGE_EXTS%) do if /i "%%E"=="%EXT%" set "MATCH=1"
if not defined MATCH (
    echo   [skip] %~nx1 - %EXT% is not in IMAGE_EXTS
    set /a COUNT_SKIP+=1
    goto :eof
)

if "%SKIP_EXISTING%"=="1" if exist "%DST%" (
    rem Source and destination share a folder, so a date-sorted listing of the
    rem two tells us which one is newer. If dir ever declines to sort them
    rem together the worst case is a redundant reconvert, never a stale .tx.
    set "NEWEST="
    for /f "delims=" %%A in ('dir /b /o-d "%SRC%" "%DST%" 2^>nul') do (
        if not defined NEWEST set "NEWEST=%%A"
    )
    if /i "!NEWEST!"=="%~n1.tx" (
        echo   [skip] %~nx1 - .tx is already up to date
        set /a COUNT_SKIP+=1
        goto :eof
    )
)

echo   [conv] %~nx1  -^>  %~n1.tx
"%TXMAKE%" %TXOPTS% "%SRC%" "%DST%"
if errorlevel 1 (
    echo          FAILED: txmake returned an error for %~nx1
    set /a COUNT_FAIL+=1
) else (
    set /a COUNT_OK+=1
)
goto :eof

rem ===========================================================================
:find_txmake
rem 1. explicit override
if defined TXMAKE_EXE if exist "%TXMAKE_EXE%" (
    set "TXMAKE=%TXMAKE_EXE%"
    goto :eof
)

rem 2. standard RenderMan environment variable
if defined RMANTREE if exist "%RMANTREE%\bin\txmake.exe" (
    set "TXMAKE=%RMANTREE%\bin\txmake.exe"
    goto :eof
)

rem 3. newest RenderManProServer install under Program Files
for %%R in ("%ProgramFiles%\Pixar" "C:\Pixar") do (
    if exist "%%~R" (
        for /f "delims=" %%D in ('dir /b /ad /o-n "%%~R\RenderManProServer-*" 2^>nul') do (
            if not defined TXMAKE if exist "%%~R\%%D\bin\txmake.exe" (
                set "TXMAKE=%%~R\%%D\bin\txmake.exe"
            )
        )
    )
)
if defined TXMAKE goto :eof

rem 4. anything already on PATH
for /f "delims=" %%P in ('where txmake.exe 2^>nul') do (
    if not defined TXMAKE set "TXMAKE=%%P"
)
goto :eof

rem ===========================================================================
:summary
echo.
echo   converted: %COUNT_OK%   skipped: %COUNT_SKIP%   failed: %COUNT_FAIL%
echo.

if %COUNT_FAIL% GTR 0 (
    pause
    exit /b 1
)
if "%ALWAYS_PAUSE%"=="1" pause
exit /b 0
