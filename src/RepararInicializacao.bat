@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Reparar inicializacao do Windows (WinRE)

rem ============================================================
rem  Para o erro "O Reparo Automatico nao pode reparar o computador"
rem  (SrtTrail.txt). Usar no CMD do Ambiente de Recuperacao.
rem   1) Mostra a causa registrada no SrtTrail.txt
rem   2) Menu de reparo: disco, atualizacao pendente,
rem      arquivos do sistema e arquivos de boot
rem  Logs e copia de seguranca do boot vao para o pendrive.
rem
rem  Uso:  E:\RepararInicializacao.bat      (detecta o Windows)
rem        E:\RepararInicializacao.bat D:   (forca a unidade)
rem ============================================================

set "USB=%~d0"

rem ---------- Localizar a unidade do Windows ----------
set "WIN=%~1"
if defined WIN goto :temwin
for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do (
    if not defined WIN if /i not "%%L:"=="%USB%" if exist "%%L:\Windows\System32\config\SOFTWARE" set "WIN=%%L:"
)
:temwin
if not defined WIN goto :semwin
if not exist "%WIN%\Windows\System32\config\SOFTWARE" goto :semwin

rem ---------- Pasta de logs no pendrive ----------
set "BASE=%USB%\Reparo"
set "DEST=%BASE%"
set "N=1"
:prox
if not exist "%DEST%" goto :criar
set /a N+=1
set "DEST=%BASE%_%N%"
goto :prox
:criar
mkdir "%DEST%" 2>nul
set "LOG=%DEST%\reparo_log.txt"
> "%LOG%" echo Reparo iniciado em %date% %time% - Windows em %WIN%

rem ---------- Telas azuis registradas (minidumps) ----------
rem Copia para o pendrive: da para analisar depois em outro PC
set "DUMPS=0"
if not exist "%WIN%\Windows\Minidump\*.dmp" goto :sem_dumps
for /f %%c in ('dir /b /a-d "%WIN%\Windows\Minidump\*.dmp" ^| find /c /v ""') do set "DUMPS=%%c"
xcopy "%WIN%\Windows\Minidump\*.dmp" "%DEST%\Minidump\" /Y /I /C /Q >nul 2>&1
>> "%LOG%" echo Telas azuis registradas: %DUMPS% (copiadas para a pasta Minidump)
:sem_dumps

rem ---------- Causa registrada no SrtTrail.txt ----------
set "SRT=%WIN%\Windows\System32\Logfiles\Srt\SrtTrail.txt"
set "CAUSA="
set "DICA=1"
if not exist "%SRT%" goto :menu
type "%SRT%" > "%DEST%\SrtTrail.txt" 2>nul
set "ULT="
for /f "delims=:" %%n in ('findstr /n /i /c:"raiz encontrada" /c:"root cause found" "%DEST%\SrtTrail.txt"') do set "ULT=%%n"
if not defined ULT goto :menu
set /a ALVO=ULT+2
for /f "tokens=1,* delims=:" %%a in ('findstr /n "^" "%DEST%\SrtTrail.txt"') do if "%%a"=="%ALVO%" set "CAUSA=%%b"
if not defined CAUSA goto :menu
> "%DEST%\causa.txt" echo %CAUSA%
>> "%LOG%" echo Causa (SrtTrail): %CAUSA%
findstr /i /c:"patch" /c:"atualiza" /c:"update" "%DEST%\causa.txt" >nul && set "DICA=3"
findstr /i /c:"gerenciador de inicializa" /c:"boot manager" /c:"bcd" /c:"configuracao de inicializa" "%DEST%\causa.txt" >nul && set "DICA=2"

rem ---------- Menu ----------
:menu
cls
echo ============================================================
echo   REPARAR INICIALIZACAO DO WINDOWS
echo ============================================================
echo   Windows em : %WIN%
echo   Logs em    : %DEST%
echo.
if not defined CAUSA goto :menu_semcausa
echo   Causa do erro (segundo o SrtTrail.txt):
echo     %CAUSA%
goto :menu_opcoes
:menu_semcausa
echo   Nao encontrei a causa no SrtTrail.txt.
:menu_opcoes
if "%DUMPS%"=="0" goto :menu_lista
echo   Telas azuis registradas: %DUMPS%   (copias salvas no pendrive)
if %DUMPS% geq 3 echo   ATENCAO: muitas telas azuis. Se o reparo nao resolver, use a opcao [6].
:menu_lista
echo.
echo   [1] Reparo completo - disco, atualizacao, arquivos do sistema e boot
echo   [2] So o boot       - recria os arquivos de inicializacao
echo   [3] So atualizacao  - desfaz atualizacao que ficou pela metade
echo   [4] Modo Seguro     - para tela azul em loop (driver com defeito)
echo   [5] Modo normal     - desfaz a opcao 4 depois de resolver
echo   [6] Diagnostico     - descobrir se e defeito de hardware (memoria)
echo   [0] Sair
echo.
echo   Recomendado para este erro: [%DICA%]
echo.
set "OP="
set /p "OP=Digite o numero e aperte Enter: "
if "%OP%"=="1" goto :completo
if "%OP%"=="2" goto :so_boot
if "%OP%"=="3" goto :so_update
if "%OP%"=="4" goto :seguro
if "%OP%"=="5" goto :normal
if "%OP%"=="6" goto :diagnostico
if "%OP%"=="0" goto :fim
goto :menu

:diagnostico
cls
echo ============================================================
echo  DIAGNOSTICO: E SOFTWARE OU HARDWARE?
echo ============================================================
echo.
echo  Telas azuis registradas no Windows: %DUMPS%
if not "%DUMPS%"=="0" dir /o-d "%WIN%\Windows\Minidump\*.dmp" | find /i ".dmp"
echo.
echo  Saude dos discos (OK = bom):
wmic diskdrive get model,status 2>nul
echo.
echo  PROVAVELMENTE E HARDWARE se:
echo   - cada tela azul mostra um erro diferente, ou
echo   - o PC tambem da tela azul ligando pelo pendrive, ou
echo   - o reparo completo [1] rodou e o problema continuou.
echo.
echo  PROXIMO PASSO: TESTE DE MEMORIA
echo   Pendrive bootavel: ligue pelo pendrive, no menu de boot aperte TAB,
echo   escolha "Teste de memoria (RAM)" e Enter.
echo   Ou agende agora o teste do proprio Windows (pergunta abaixo).
echo.
echo   Durante o teste, olhe a linha "Status":
echo     "Nenhum problema detectado" / "No problems have been detected" = memoria OK
echo     "Problemas de hardware" / "Hardware problems were detected" = troque a memoria
echo.
echo  Memoria OK? Teste outra fonte e veja se a placa-mae tem capacitores
echo  estufados. Disco com status diferente de OK acima? Troque o disco.
echo.
>> "%LOG%" echo diagnostico: %DUMPS% telas azuis registradas
set "MT="
set /p "MT=Agendar o teste de memoria para o proximo boot? (S/N): "
if /i not "%MT%"=="S" goto :menu
bcdedit /bootsequence {memdiag}
if errorlevel 1 goto :diag_falha
>> "%LOG%" echo teste de memoria agendado
echo.
echo  Agendado. Tire o pendrive, digite  exit  e escolha "Continuar".
echo  O teste de memoria comeca sozinho ao ligar.
pause
goto :fim
:diag_falha
echo  Nao foi possivel agendar. Use o menu de boot do pendrive (TAB).
pause
goto :menu

:completo
echo.
echo Reparo completo: pode levar de 1 a 3 horas. Deixe o notebook na tomada e nao desligue.
call :disco
call :pendente
call :sistema
call :boot
goto :concluido

:so_boot
call :boot
goto :concluido

:so_update
call :pendente
goto :concluido

:seguro
echo.
echo ===== Ativando o Modo de Seguranca =====
bcdedit /set {default} safeboot minimal
if errorlevel 1 goto :seguro_falha
>> "%LOG%" echo Modo de Seguranca: ATIVADO
cls
echo ============================================================
echo  MODO DE SEGURANCA ATIVADO
echo ============================================================
echo.
echo  1. Digite  exit  e escolha "Continuar". O Windows vai ligar
echo     em Modo de Seguranca (tela preta escrita nos cantos).
echo  2. Entre com a senha do usuario.
echo  3. Clique com o botao direito no Iniciar ^> Gerenciador de Dispositivos
echo     ^> Adaptadores de video ^> botao direito na placa ^> Desinstalar
echo     (marque "Tentar remover o driver", se aparecer).
echo  4. Se instalou algum programa ou driver antes do problema,
echo     desinstale tambem (Configuracoes ^> Aplicativos).
echo  5. Para voltar ao normal, no Modo de Seguranca abra o CMD como
echo     administrador e digite:
echo        bcdedit /deletevalue {default} safeboot
echo     e reinicie. (Ou rode este script de novo e use a opcao 5.)
echo.
pause
goto :fim
:seguro_falha
echo Nao foi possivel ativar o Modo de Seguranca.
>> "%LOG%" echo Modo de Seguranca: FALHOU
pause
goto :menu

:normal
echo.
bcdedit /deletevalue {default} safeboot
>> "%LOG%" echo Modo de Seguranca: desativado (codigo %errorlevel%)
echo Pronto: o Windows vai ligar no modo normal.
pause
goto :fim

rem ---------- Etapas ----------

:disco
echo.
echo ===== Verificando o disco %WIN% (com /r pode levar mais de 1 hora) =====
chkdsk %WIN% /f /r /x
>> "%LOG%" echo chkdsk: codigo %errorlevel% (0 = sem erros, 1 = erros corrigidos)
exit /b

:pendente
echo.
echo ===== Atualizacao pendente =====
if exist "%WIN%\Windows\WinSxS\pending.xml" goto :pendente_sim
echo Nenhuma atualizacao pela metade encontrada.
>> "%LOG%" echo atualizacao pendente: nenhuma
exit /b
:pendente_sim
dism /Image:%WIN%\ /ScratchDir:%WIN%\Windows\Temp /Cleanup-Image /RevertPendingActions
>> "%LOG%" echo dism revert: codigo %errorlevel% (0 = ok)
exit /b

:sistema
echo.
echo ===== Verificando arquivos do sistema =====
sfc /scannow /offbootdir=%WIN%\ /offwindir=%WIN%\Windows
>> "%LOG%" echo sfc: codigo %errorlevel% (0 = ok)
copy /y "%SystemRoot%\Logs\CBS\CBS.log" "%DEST%\CBS.log" >nul 2>&1
exit /b

:boot
echo.
echo ===== Recriando arquivos de boot =====
bcdedit /export "%DEST%\BCD_backup" >nul 2>&1
bootrec /fixmbr
>> "%LOG%" echo bootrec /fixmbr: codigo %errorlevel%
rem /fixboot costuma dar "Acesso negado" em UEFI; o bcdboot abaixo cobre esse caso
bootrec /fixboot
>> "%LOG%" echo bootrec /fixboot: codigo %errorlevel% (Acesso negado e normal em UEFI)
bcdboot %WIN%\Windows /f ALL
if not errorlevel 1 goto :boot_ok
echo Tentando pela particao EFI...
mountvol S: /s >nul 2>&1
bcdboot %WIN%\Windows /s S: /f UEFI
set "R=%errorlevel%"
mountvol S: /d >nul 2>&1
>> "%LOG%" echo bcdboot (EFI): codigo %R% (0 = ok)
if "%R%"=="0" exit /b
echo.
echo Ultima tentativa: bootrec /rebuildbcd
echo Se perguntar "Adicionar instalacao a lista de inicializacao?", digite S e Enter.
bootrec /rebuildbcd
>> "%LOG%" echo bootrec /rebuildbcd: codigo %errorlevel%
exit /b
:boot_ok
>> "%LOG%" echo bcdboot: ok
exit /b

rem ---------- Final ----------

:concluido
echo.
echo ============================================================
echo  Reparo terminado. Resumo:
echo.
type "%LOG%"
echo.
echo  Agora: digite  exit  e escolha "Continuar" para iniciar o Windows.
echo  Se o erro voltar, rode de novo e use a opcao [6] Diagnostico.
if "%DICA%"=="3" echo  Se nao resolver: Opcoes avancadas ^> Desinstalar Atualizacoes.
echo ============================================================
pause
goto :fim

:semwin
echo [ERRO] Nao encontrei a pasta Windows em nenhuma unidade.
echo        Se o disco tiver BitLocker, desbloqueie antes com:
echo          manage-bde -unlock C: -RecoveryPassword SUA-CHAVE
echo        Ou informe a unidade do Windows:  %~nx0 D:
pause
exit /b 1

:fim
endlocal
exit /b 0
