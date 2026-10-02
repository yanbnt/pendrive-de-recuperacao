@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Coleta OFFLINE de itens de inicializacao (WinRE)

rem ============================================================
rem  Para usar no CMD do Ambiente de Recuperacao do Windows
rem  (Solucionar problemas > Opcoes avancadas > Prompt de Comando).
rem
rem  Le o registro do Windows "desligado" (reg load), copia pastas
rem  Inicializar, tarefas agendadas e lista servicos/drivers.
rem  Tudo e gravado no pendrive de onde o script foi executado.
rem
rem  Uso:  E:\ColetarInicializacao.bat        (detecta o Windows)
rem        E:\ColetarInicializacao.bat D:     (forca a unidade)
rem ============================================================

set "USB=%~d0"

rem ---------- Localizar a unidade do Windows ----------
set "WIN=%~1"
if defined WIN goto :temwin
for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if not defined WIN if /i not "%%L:"=="%USB%" if exist "%%L:\Windows\System32\config\SOFTWARE" set "WIN=%%L:"
)
:temwin
if not defined WIN (
    echo [ERRO] Nao encontrei a pasta Windows em nenhuma unidade.
    echo        Se o disco tiver BitLocker, desbloqueie antes com:
    echo          manage-bde -unlock C: -RecoveryPassword SUA-CHAVE
    echo        Ou informe a unidade do Windows:  %~nx0 D:
    pause
    exit /b 1
)
if not exist "%WIN%\Windows\System32\config\SOFTWARE" (
    echo [ERRO] %WIN% nao contem uma instalacao do Windows.
    pause
    exit /b 1
)

echo.
echo   Windows encontrado em : %WIN%
echo   Destino (pendrive)    : %USB%
echo.
set "OK="
set /p "OK=Confirma? (S/N): "
if /i not "%OK%"=="S" exit /b

rem ---------- Montar o registro offline ----------
call :descarregar
reg load HKLM\OFF_SOFT "%WIN%\Windows\System32\config\SOFTWARE" >nul
if errorlevel 1 goto :falha_hive
reg load HKLM\OFF_SYS "%WIN%\Windows\System32\config\SYSTEM" >nul
if errorlevel 1 goto :falha_hive

set "CS=1"
for /f "tokens=3" %%a in ('reg query HKLM\OFF_SYS\Select /v Current 2^>nul ^| find "REG_DWORD"') do set /a CS=%%a
set "CSET=HKLM\OFF_SYS\ControlSet00%CS%"

set "PC=SEM_NOME"
for /f "tokens=3" %%a in ('reg query "%CSET%\Control\ComputerName\ComputerName" /v ComputerName 2^>nul ^| find "REG_SZ"') do set "PC=%%a"

rem ---------- Pasta de destino (nao sobrescreve coletas anteriores) ----------
set "BASE=%USB%\Inicializacao_%PC%"
set "DEST=%BASE%"
set "N=1"
:prox
if not exist "%DEST%" goto :criar
set /a N+=1
set "DEST=%BASE%_%N%"
goto :prox
:criar
mkdir "%DEST%\registro" "%DEST%\pastas_inicializar" "%DEST%\offline\Windows\System32\config" 2>nul

> "%DEST%\info.txt" echo Computador : %PC%
>> "%DEST%\info.txt" echo Coletado em: %date% %time%
>> "%DEST%\info.txt" echo Windows em : %WIN%   (ControlSet00%CS%)

echo.
echo Salvando em: %DEST%
echo.

rem ---------- 1. Registro da maquina ----------
echo [1/6] Chaves de inicializacao da maquina...
set "LISTA=%DEST%\registro\chaves_inicializacao.txt"
> "%LISTA%" echo Chaves de inicializacao - %PC%
call :exp "HKLM\OFF_SOFT\Microsoft\Windows\CurrentVersion\Run"                       MAQ_Run
call :exp "HKLM\OFF_SOFT\Microsoft\Windows\CurrentVersion\RunOnce"                   MAQ_RunOnce
call :exp "HKLM\OFF_SOFT\WOW6432Node\Microsoft\Windows\CurrentVersion\Run"           MAQ_Run_32bits
call :exp "HKLM\OFF_SOFT\WOW6432Node\Microsoft\Windows\CurrentVersion\RunOnce"       MAQ_RunOnce_32bits
call :exp "HKLM\OFF_SOFT\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"     MAQ_Policies_Run
call :exp "HKLM\OFF_SOFT\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"  MAQ_StartupApproved
call :exp "HKLM\OFF_SOFT\Microsoft\Windows NT\CurrentVersion\Winlogon"               MAQ_Winlogon
call :exp "HKLM\OFF_SOFT\Microsoft\Windows NT\CurrentVersion\Windows"                MAQ_AppInit

rem ---------- 2. Registro e pasta Inicializar de cada usuario ----------
echo [2/6] Perfis de usuario...
set "U=0"
for /d %%P in ("%WIN%\Users\*") do if exist "%%P\NTUSER.DAT" call :usuario "%%P" "%%~nxP"

set "SP=%WIN%\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"
if exist "%SP%" xcopy "%SP%" "%DEST%\pastas_inicializar\_TODOS_USUARIOS\" /E /I /H /Y /C >nul 2>&1

rem ---------- 3. Tarefas agendadas ----------
echo [3/6] Tarefas agendadas...
xcopy "%WIN%\Windows\System32\Tasks" "%DEST%\tarefas_agendadas\" /E /I /H /Y /C >nul 2>&1
set "RES=%DEST%\tarefas_agendadas_resumo.txt"
> "%RES%" echo Comandos executados por cada tarefa agendada
for /r "%DEST%\tarefas_agendadas" %%F in (*) do call :tarefa "%%F"

rem ---------- 4. Servicos e drivers que iniciam sozinhos ----------
echo [4/6] Servicos e drivers (pode levar 1-2 minutos)...
set "SVC=%DEST%\servicos_e_drivers.txt"
> "%SVC%" echo TIPO  -  NOME  -  EXECUTAVEL   (BOOT/SISTEMA = drivers carregados no boot)
reg export "%CSET%\Services" "%DEST%\registro\MAQ_Services.reg" /y >nul 2>&1
for /f "delims=" %%k in ('reg query "%CSET%\Services" 2^>nul ^| find /i "\Services\"') do call :servico "%%k"

rem ---------- 5. Desmontar registro ----------
echo [5/6] Desmontando registro...
call :descarregar

rem ---------- 6. Copia bruta das hives (para analise em outro PC) ----------
echo [6/6] Copiando arquivos de registro...
xcopy "%WIN%\Windows\System32\config\SOFTWARE*" "%DEST%\offline\Windows\System32\config\" /H /Y /C >nul 2>&1
xcopy "%WIN%\Windows\System32\config\SYSTEM*"   "%DEST%\offline\Windows\System32\config\" /H /Y /C >nul 2>&1

echo.
echo ============================================================
echo  Concluido! Arquivos salvos em:
echo    %DEST%
echo ============================================================
pause
exit /b 0


rem ============================================================
rem  Sub-rotinas
rem ============================================================

:falha_hive
echo [ERRO] Nao foi possivel montar o registro de %WIN%.
echo        Verifique se o CMD e do Ambiente de Recuperacao e se o
echo        disco nao esta bloqueado pelo BitLocker.
call :descarregar
pause
exit /b 1

:descarregar
reg unload HKLM\OFF_SOFT >nul 2>&1
reg unload HKLM\OFF_SYS  >nul 2>&1
for /l %%i in (1,1,30) do reg unload HKLM\OFF_U%%i >nul 2>&1
exit /b

rem  :exp <chave> <nome>  -> gera .reg e anexa conteudo legivel na LISTA
:exp
reg query "%~1" >nul 2>&1 || exit /b
reg export "%~1" "%DEST%\registro\%~2.reg" /y >nul 2>&1
>> "%LISTA%" echo.
>> "%LISTA%" echo ==== %~2 ====
reg query "%~1" /s >> "%LISTA%" 2>nul
exit /b

rem  :usuario <pasta_perfil> <nome_usuario>
:usuario
set /a U+=1
set "UK=HKLM\OFF_U%U%"
set "UN=%~2"
echo       - %UN%
reg load %UK% "%~1\NTUSER.DAT" >nul 2>&1
if errorlevel 1 goto :usr_falha
call :exp "%UK%\Software\Microsoft\Windows\CurrentVersion\Run"                       "USR_%UN%_Run"
call :exp "%UK%\Software\Microsoft\Windows\CurrentVersion\RunOnce"                   "USR_%UN%_RunOnce"
call :exp "%UK%\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run"     "USR_%UN%_Policies_Run"
call :exp "%UK%\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"  "USR_%UN%_StartupApproved"
call :exp "%UK%\Software\Microsoft\Windows NT\CurrentVersion\Winlogon"               "USR_%UN%_Winlogon"
reg unload %UK% >nul 2>&1
goto :usr_arquivos
:usr_falha
>> "%LISTA%" echo.
>> "%LISTA%" echo ==== [nao foi possivel carregar o registro do usuario %UN%] ====
:usr_arquivos
mkdir "%DEST%\offline\Users\%UN%" 2>nul
xcopy "%~1\NTUSER.DAT*" "%DEST%\offline\Users\%UN%\" /H /Y /C >nul 2>&1
set "SU=%~1\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
if exist "%SU%" xcopy "%SU%" "%DEST%\pastas_inicializar\%UN%\" /E /I /H /Y /C >nul 2>&1
exit /b

rem  :tarefa <arquivo_xml>  (XML em UTF-16; "type" converte para leitura)
:tarefa
>> "%RES%" echo.
>> "%RES%" echo ==== %~nx1 ====
type "%~1" 2>nul | find /i "<Command>"   >> "%RES%"
type "%~1" 2>nul | find /i "<Arguments>" >> "%RES%"
exit /b

rem  :servico <chave>  -> registra so os que iniciam sozinhos (Start 0, 1 ou 2)
:servico
set "ST="
for /f "tokens=3" %%s in ('reg query "%~1" /v Start 2^>nul ^| find "REG_DWORD"') do set "ST=%%s"
if not defined ST exit /b
set "TIPO="
if "%ST%"=="0x0" set "TIPO=BOOT      "
if "%ST%"=="0x1" set "TIPO=SISTEMA   "
if "%ST%"=="0x2" set "TIPO=AUTOMATICO"
if not defined TIPO exit /b
set "IMG="
for /f "tokens=2,*" %%x in ('reg query "%~1" /v ImagePath 2^>nul ^| find "REG_"') do set "IMG=%%y"
>> "%SVC%" echo %TIPO%  -  %~nx1  -  %IMG%
exit /b
