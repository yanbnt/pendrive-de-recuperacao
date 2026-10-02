# ============================================================
#  Preparar Pendrive (janela)
#   - Pendrive de coleta: formata em NTFS e copia o
#     ColetarInicializacao.bat (usar no CMD da recuperacao do PC).
#   - Pendrive bootavel do Windows (a partir de uma ISO) + script,
#     para quando o PC nem abre as opcoes de recuperacao.
#  Pede administrador sozinho.
# ============================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$Script = Join-Path $PSScriptRoot 'ColetarInicializacao.bat'

function GB($bytes) { '{0:N1} GB' -f ($bytes / 1GB) }

function Show-Msg([string]$Texto, [string]$Icone = 'Information', [string]$Botoes = 'OK', [string]$Padrao = 'Button1') {
    [System.Windows.Forms.MessageBox]::Show($Texto, 'Preparar Pendrive', $Botoes, $Icone, $Padrao)
}

function Add-Ctl($Pai, [string]$Tipo, [int]$X, [int]$Y, [int]$W, [int]$H, $Texto) {
    $c = New-Object "System.Windows.Forms.$Tipo"
    $c.SetBounds($X, $Y, $W, $H)
    if ($null -ne $Texto) { $c.Text = $Texto }
    $Pai.Controls.Add($c)
    $c
}

function Get-IconeApp {
    if (-not ('Win32.ShellIcon' -as [type])) {
        Add-Type -Namespace Win32 -Name ShellIcon -MemberDefinition @'
[DllImport("shell32.dll", CharSet = CharSet.Unicode)]
public static extern int ExtractIconEx(string file, int index, IntPtr[] large, IntPtr[] small, int count);
'@
    }
    $grande = New-Object IntPtr[] 1
    $pequeno = New-Object IntPtr[] 1
    [void][Win32.ShellIcon]::ExtractIconEx("$env:SystemRoot\System32\shell32.dll", 7, $grande, $pequeno, 1)
    if ($grande[0] -ne [IntPtr]::Zero) { [System.Drawing.Icon]::FromHandle($grande[0]) }
}

# ---------------- Trabalho pesado (roda em segundo plano) ----------------

$Trabalho = {
    param($sync, $p)
    $ErrorActionPreference = 'Stop'
    function Etapa([int]$Pct, [string]$Msg) { $sync.Pct = $Pct; $sync.Status = $Msg }

    # Roda um programa e espera SO por ele. Nao usar Start-Process -Wait: no
    # PowerShell 5.1 ele espera tambem os processos filhos, e o DISM deixa o
    # wimserv.exe vivo enquanto a imagem esta montada -> trava para sempre.
    function Invoke-Programa([string]$Exe, [string[]]$Argumentos) {
        $proc = Start-Process $Exe -ArgumentList $Argumentos -WindowStyle Hidden -PassThru
        $null = $proc.Handle
        $proc.WaitForExit()
        $proc.ExitCode
    }

    # Desfaz o que uma tentativa interrompida deixou para tras: boot.wim
    # montado na pasta temporaria e a ISO ainda conectada
    function Clear-TentativaAnterior([string]$Iso) {
        try {
            Get-WindowsImage -Mounted -ErrorAction Stop | Where-Object { $_.Path -like '*\pr_*' } | ForEach-Object {
                Dismount-WindowsImage -Path $_.Path -Discard -ErrorAction SilentlyContinue | Out-Null
                Remove-Item (Split-Path $_.Path) -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {}
        [void](Invoke-Programa dism @('/Cleanup-Wim'))
        Get-ChildItem $env:TEMP -Directory -Filter 'pr_*' -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        Dismount-DiskImage -ImagePath $Iso -ErrorAction SilentlyContinue | Out-Null
    }

    # Menu de boot do pendrive: "Reparo do Windows" (padrao, entra sozinho em
    # 15 s) + ferramenta "Teste de memoria (RAM)" (tecla TAB), nos dois BCDs:
    # \boot\bcd (BIOS antigo) e \efi\microsoft\boot\bcd (UEFI)
    function Set-MenuBoot([string]$Raiz) {
        $lojas = @(
            @{ Bcd = "$Raiz\boot\bcd";               Memtest = '\boot\memtest.exe' },
            @{ Bcd = "$Raiz\efi\microsoft\boot\bcd"; Memtest = '\efi\microsoft\boot\memtest.efi' }
        )
        $falhas = 0
        foreach ($l in $lojas) {
            if (-not (Test-Path $l.Bcd) -or -not (Test-Path ($Raiz + $l.Memtest))) { continue }
            $s = @('/store', $l.Bcd)
            if ((Invoke-Programa bcdedit ($s + '/enum', '{memdiag}')) -ne 0) {
                if ((Invoke-Programa bcdedit ($s + '/create', '{memdiag}', '/d', '"Teste de memoria (RAM)"')) -ne 0) { $falhas++; continue }
            }
            $cmds = @(
                @('/set', '{memdiag}', 'device', 'boot'),
                @('/set', '{memdiag}', 'path', $l.Memtest),
                @('/set', '{memdiag}', 'description', '"Teste de memoria (RAM)"'),
                @('/toolsdisplayorder', '{memdiag}', '/addlast'),
                @('/set', '{default}', 'description', '"Reparo do Windows"'),
                @('/set', '{bootmgr}', 'displaybootmenu', 'yes'),
                @('/timeout', '15')
            )
            foreach ($c in $cmds) { if ((Invoke-Programa bcdedit ($s + $c)) -ne 0) { $falhas++ } }
        }
        $falhas
    }

    # Copia a arvore $Origem -> $Destino em blocos de 4 MB, contando exatamente o
    # que ja foi gravado, com velocidade e tempo restante na barra (o robocopy
    # reserva o espaco do arquivo antes de gravar e a barra parecia parada)
    function Copy-Arquivos([string]$Origem, [string]$Destino, [string[]]$Pular) {
        $Origem = $Origem.TrimEnd('\') + '\'
        $arquivos = @(Get-ChildItem $Origem -Recurse -File | Where-Object { $Pular -notcontains $_.Name })
        $total = [double]($arquivos | Measure-Object Length -Sum).Sum
        Get-ChildItem $Origem -Recurse -Directory | ForEach-Object {
            New-Item -ItemType Directory -Force (Join-Path $Destino $_.FullName.Substring($Origem.Length)) | Out-Null
        }
        $buf = New-Object byte[] (4MB)
        [double]$copiado = 0
        $relogio = [Diagnostics.Stopwatch]::StartNew()
        $ultimo = 0
        foreach ($arq in $arquivos) {
            $entrada = [IO.File]::OpenRead($arq.FullName)
            $saida = [IO.File]::Create((Join-Path $Destino $arq.FullName.Substring($Origem.Length)))
            try {
                while (($n = $entrada.Read($buf, 0, $buf.Length)) -gt 0) {
                    $saida.Write($buf, 0, $n)
                    $copiado += $n
                    if ($relogio.ElapsedMilliseconds - $ultimo -ge 500) {
                        $ultimo = $relogio.ElapsedMilliseconds
                        $mbs = ($copiado / 1MB) / [math]::Max([double]1, $relogio.Elapsed.TotalSeconds)
                        $falta = [math]::Ceiling((($total - $copiado) / 1MB) / [math]::Max([double]0.1, $mbs) / 60)
                        Etapa (30 + [int](55 * $copiado / [math]::Max([double]1, $total))) ("Copiando arquivos do Windows... {0:N1} de {1:N1} GB   ·   {2:N0} MB/s   ·   faltam ~{3} min" -f ($copiado / 1GB), ($total / 1GB), $mbs, $falta)
                    }
                }
            } finally {
                $entrada.Dispose()
                $saida.Dispose()
            }
        }
        [pscustomobject]@{ Arquivos = $arquivos.Count; Bytes = $copiado }
    }

    # Faz o pendrive abrir o reparo sozinho ao dar boot: grava um winpeshl.ini
    # no boot.wim (indice 2 = ambiente da instalacao) que chama o reparo_auto.cmd
    function Set-ReparoAutomatico([string]$Origem, [string]$Destino) {
        $tmp = Join-Path $env:TEMP ('pr_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
        $wim = Join-Path $tmp 'boot.wim'
        $mnt = Join-Path $tmp 'mnt'
        New-Item -ItemType Directory -Force $mnt | Out-Null
        Copy-Item $Origem $wim
        (Get-Item $wim).Attributes = 'Normal'

        $r = Invoke-Programa dism @('/Mount-Image', "/ImageFile:`"$wim`"", '/Index:2', "/MountDir:`"$mnt`"")
        if ($r -ne 0) { throw "Falha ao abrir o boot.wim (DISM código $r)." }
        $ok = $false
        try {
            $sys = Join-Path $mnt 'Windows\System32'
            $ini = "[LaunchApps]`r`n%SYSTEMROOT%\System32\wpeinit.exe`r`n%SYSTEMROOT%\System32\cmd.exe, /k %SYSTEMROOT%\System32\reparo_auto.cmd`r`n"
            [IO.File]::WriteAllText((Join-Path $sys 'winpeshl.ini'), $ini, [Text.Encoding]::ASCII)
            $auto = @'
@echo off
title Pendrive de Recuperacao
cls
echo Procurando o pendrive de reparo...
set "PEN="
set "TENT=0"
:procura
for %%L in (C D E F G H I J K L M N O P Q R S T U V W Y Z) do if not defined PEN if exist "%%L:\RepararInicializacao.bat" set "PEN=%%L:"
if defined PEN goto :achou
set /a TENT+=1
if %TENT% geq 10 goto :nao_achou
ping -n 3 127.0.0.1 >nul
goto :procura
:nao_achou
echo Nao encontrei o RepararInicializacao.bat em nenhuma unidade.
echo Para reiniciar o PC, digite: exit
goto :eof
:achou
call "%PEN%\RepararInicializacao.bat"
echo.
echo Para abrir o reparo de novo:  %PEN%\RepararInicializacao.bat
echo Para instalar o Windows:      X:\sources\setup.exe
echo Para reiniciar o PC:          exit
'@
            [IO.File]::WriteAllText((Join-Path $sys 'reparo_auto.cmd'), ($auto -replace "`r?`n", "`r`n"), [Text.Encoding]::ASCII)
            $ok = $true
        } finally {
            $fecha = if ($ok) { '/Commit' } else { '/Discard' }
            $r = Invoke-Programa dism @('/Unmount-Image', "/MountDir:`"$mnt`"", $fecha)
        }
        if ($r -ne 0) { throw "Falha ao salvar o boot.wim (DISM código $r)." }
        Copy-Item $wim $Destino -Force
        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
    try {
        Etapa 5 'Limpando o pendrive...'
        # Encerra copias que tenham sobrado de uma tentativa anterior neste pendrive
        $letras = @(Get-Partition -DiskNumber $p.Disco -ErrorAction SilentlyContinue | Where-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):\" })
        Get-CimInstance Win32_Process -Filter "Name='Robocopy.exe' OR Name='Dism.exe'" | Where-Object {
            $cmd = $_.CommandLine; $cmd -and ($letras | Where-Object { $cmd -like "*$_*" })
        } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep -Seconds 1
        $d = Get-Disk -Number $p.Disco
        if ($d.PartitionStyle -ne 'RAW') {
            Clear-Disk -Number $p.Disco -RemoveData -RemoveOEM -Confirm:$false
        }
        Initialize-Disk -Number $p.Disco -PartitionStyle MBR -ErrorAction SilentlyContinue
        Set-Disk -Number $p.Disco -PartitionStyle MBR -ErrorAction SilentlyContinue

        Etapa 15 'Criando partição...'
        if ($p.Modo -eq 2) {
            # UEFI so da boot em FAT32, e o Windows so formata FAT32 ate 32 GB
            $fs = 'FAT32'; $label = 'RECUPERACAO'; $max = 31GB   # rotulo FAT32: maximo 11 letras
        } else {
            $fs = 'NTFS'; $label = 'COLETA'; $max = 0
        }
        $d = Get-Disk -Number $p.Disco
        if ($max -gt 0 -and $d.Size -gt $max) {
            $part = New-Partition -DiskNumber $p.Disco -Size $max -IsActive -AssignDriveLetter
        } else {
            $part = New-Partition -DiskNumber $p.Disco -UseMaximumSize -IsActive -AssignDriveLetter
        }
        Start-Sleep -Seconds 2

        Etapa 25 "Formatando em $fs..."
        Format-Volume -Partition $part -FileSystem $fs -NewFileSystemLabel $label -Confirm:$false | Out-Null
        $usb = (Get-Partition -DiskNumber $p.Disco -PartitionNumber $part.PartitionNumber).DriveLetter
        if (-not $usb) { throw 'O Windows não atribuiu uma letra ao pendrive.' }
        $sync.Letra = $usb

        if ($p.Modo -eq 2) {
            Etapa 30 'Abrindo a ISO...'
            Clear-TentativaAnterior $p.Iso
            $img = Mount-DiskImage -ImagePath $p.Iso -PassThru
            try {
                $src = ($img | Get-Volume).DriveLetter
                $wim = "${src}:\sources\install.wim"
                $grande = (Test-Path $wim) -and ((Get-Item $wim).Length -ge 4GB)
                $esd = "${src}:\sources\install.esd"
                if ((Test-Path $esd) -and ((Get-Item $esd).Length -ge 4GB)) {
                    throw 'O install.esd desta ISO tem mais de 4 GB e não cabe em FAT32. Use uma ISO baixada pela Ferramenta de Criação de Mídia da Microsoft.'
                }

                # boot.wim nao entra na copia: ele e gravado uma vez so, ja modificado,
                # pelo Set-ReparoAutomatico (economiza ~500 MB de gravacao no pendrive)
                $pular = @('boot.wim')
                if ($grande) { $pular += 'install.wim' }
                $null = Copy-Arquivos "${src}:\" "${usb}:\" $pular

                if ($grande) {
                    Etapa -1 'Dividindo o install.wim em partes (FAT32 não aceita arquivos acima de 4 GB). Pode levar uns 10 minutos...'
                    $r = Invoke-Programa dism @('/Split-Image', "/ImageFile:$wim", "/SWMFile:${usb}:\sources\install.swm", '/FileSize:3800')
                    if ($r -ne 0) { throw "Falha ao dividir o install.wim (DISM código $r)." }
                }

                Etapa -1 'Configurando o pendrive para abrir o reparo sozinho (uns 3 minutos)...'
                Set-ReparoAutomatico "${src}:\sources\boot.wim" "${usb}:\sources\boot.wim"

                Etapa 90 'Adicionando o teste de memória ao menu de boot...'
                if ((Set-MenuBoot "${usb}:") -gt 0) {
                    $sync.Aviso += "`n- " + 'Não foi possível adicionar o teste de memória ao menu de boot. O reparo funciona normalmente.'
                }

                # Boot em PCs antigos (BIOS/Legacy). Em UEFI nao e necessario.
                # O bootsect.exe de uma ISO 64 bits nao roda num Windows 32 bits:
                # nesse caso o pendrive continua dando boot em UEFI, so nao em BIOS antigo.
                if (Test-Path "${src}:\boot\bootsect.exe") {
                    Etapa 92 'Gravando setor de boot...'
                    try {
                        $rb = Invoke-Programa "${src}:\boot\bootsect.exe" @('/nt60', "${usb}:", '/force', '/mbr')
                        if ($rb -ne 0) {
                            $sync.Aviso += "`n- " + "Não foi possível gravar o boot para BIOS antigo (bootsect código $rb). O pendrive funciona em PCs UEFI, mas pode ser ignorado em PCs antigos. Prepare de novo."
                        }
                    } catch {
                        $sync.Aviso += "`n- " + 'Não foi possível gravar o boot para BIOS antigo (ISO 64 bits num Windows 32 bits). O pendrive funciona normalmente em PCs UEFI.'
                    }
                }
            } finally {
                Dismount-DiskImage -ImagePath $p.Iso | Out-Null
            }
        }

        Etapa 96 'Copiando os scripts de reparo e coleta...'
        Copy-Item $p.Script "${usb}:\" -Force
        Copy-Item (Join-Path (Split-Path $p.Script) 'RepararInicializacao.bat') "${usb}:\" -Force

        Etapa 100 "Pronto! Pendrive ${usb}: preparado."
        $sync.Fim = 'ok'
    } catch {
        $sync.Erro = $_.Exception.Message
        $sync.Fim = 'erro'
    }
}

# ---------------- Janela ----------------

function Update-Discos {
    $script:discos = @(Get-Disk | Where-Object { $_.BusType -eq 'USB' -and -not $_.IsBoot -and -not $_.IsSystem } | Sort-Object Number)
    $script:cmbDisco.Items.Clear()
    foreach ($d in $script:discos) {
        $letras = (Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue |
                   Where-Object DriveLetter | ForEach-Object { "$($_.DriveLetter):" }) -join ' '
        if (-not $letras) { $letras = '(sem letra)' }
        [void]$script:cmbDisco.Items.Add(('{0}   {1}   ({2})' -f $letras, $d.FriendlyName.Trim(), (GB $d.Size)))
    }
    if ($script:discos.Count -gt 0) {
        $script:cmbDisco.SelectedIndex = 0
        $script:cmbDisco.Enabled = $true
        $script:btnPreparar.Enabled = $true
    } else {
        [void]$script:cmbDisco.Items.Add('Nenhum pendrive encontrado - conecte e clique em Atualizar')
        $script:cmbDisco.SelectedIndex = 0
        $script:cmbDisco.Enabled = $false
        $script:btnPreparar.Enabled = $false
    }
}

function Set-Editavel([bool]$Sim) {
    foreach ($c in $script:editaveis) { $c.Enabled = $Sim }
    $script:txtIso.Enabled = $Sim -and $script:rdBoot.Checked
    $script:btnIso.Enabled = $Sim -and $script:rdBoot.Checked
    if ($Sim -and $script:discos.Count -eq 0) { $script:cmbDisco.Enabled = $false; $script:btnPreparar.Enabled = $false }
}

function New-Janela {
    $icone = Get-IconeApp
    $negrito = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)

    $f = New-Object System.Windows.Forms.Form
    $f.Text = 'Pendrive de Recuperação'
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $f.ClientSize = New-Object System.Drawing.Size(560, 476)
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.StartPosition = 'CenterScreen'
    if ($icone) { $f.Icon = $icone }
    $script:form = $f

    # Cabecalho
    $topo = Add-Ctl $f Panel 0 0 560 70 $null
    $topo.BackColor = 'White'
    $pic = Add-Ctl $topo PictureBox 16 15 40 40 $null
    $pic.SizeMode = 'CenterImage'
    if ($icone) { $pic.Image = $icone.ToBitmap() }
    $titulo = Add-Ctl $topo Label 66 12 480 28 'Preparar Pendrive'
    $titulo.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $sub = Add-Ctl $topo Label 68 42 480 20 'Prepara o pendrive para consertar a inicialização de um PC com problema'
    $sub.ForeColor = 'DimGray'
    (Add-Ctl $f Label 0 70 560 2 $null).BorderStyle = 'Fixed3D'

    # 1. Pendrive
    (Add-Ctl $f Label 16 84 528 20 '1. Escolha o pendrive').Font = $negrito
    $script:cmbDisco = Add-Ctl $f ComboBox 16 106 428 24 $null
    $script:cmbDisco.DropDownStyle = 'DropDownList'
    $btnAtualizar = Add-Ctl $f Button 452 105 92 26 'Atualizar'

    # 2. Tipo
    (Add-Ctl $f Label 16 146 528 20 '2. Que tipo de pendrive você quer?').Font = $negrito
    $script:rdColeta = Add-Ctl $f RadioButton 16 168 528 22 'Pendrive simples'
    $script:rdColeta.Checked = $true
    $d1 = Add-Ctl $f Label 34 190 510 32 'O PC abre a tela azul de recuperação? Use este. Você roda o reparo pelo Prompt de Comando.'
    $d1.ForeColor = 'DimGray'
    $script:rdBoot = Add-Ctl $f RadioButton 16 228 528 22 'Pendrive bootável  (plugar e usar - funciona em qualquer caso)'
    $d2 = Add-Ctl $f Label 34 250 510 32 'PC em loop ou sem recuperação? Ligue o PC pelo pendrive e o reparo abre sozinho. Precisa da ISO do Windows.'
    $d2.ForeColor = 'DimGray'
    $script:txtIso = Add-Ctl $f TextBox 34 286 410 24 $null
    $script:txtIso.ReadOnly = $true
    $script:btnIso = Add-Ctl $f Button 452 285 92 26 'Escolher ISO...'
    $txtIso = 'Não tem a ISO? Baixar do site da Microsoft:   Windows 10   |   Windows 11'
    $lnkIso = Add-Ctl $f LinkLabel 34 314 510 18 $txtIso
    $lnkIso.Links.Clear()
    [void]$lnkIso.Links.Add($txtIso.IndexOf('Windows 10'), 10, 'https://www.microsoft.com/pt-br/software-download/windows10')
    [void]$lnkIso.Links.Add($txtIso.IndexOf('Windows 11'), 10, 'https://www.microsoft.com/pt-br/software-download/windows11')
    $lnkIso.Add_LinkClicked({ Start-Process $_.Link.LinkData })

    $aviso = Add-Ctl $f Label 16 340 528 20 'Atenção: tudo o que estiver no pendrive escolhido será apagado.'
    $aviso.ForeColor = 'Firebrick'
    $aviso.Font = $negrito

    $script:barra = Add-Ctl $f ProgressBar 16 364 528 20 $null
    $script:barra.MarqueeAnimationSpeed = 30
    $script:status = Add-Ctl $f Label 16 388 528 34 'Escolha o pendrive e o tipo e clique em "Preparar pendrive".'
    $script:status.ForeColor = 'DimGray'

    # Rodape
    (Add-Ctl $f Label 0 424 560 2 $null).BorderStyle = 'Fixed3D'
    $script:btnPreparar = Add-Ctl $f Button 336 436 128 30 'Preparar pendrive'
    $script:btnPreparar.Font = $negrito
    $autor = Add-Ctl $f Label 16 443 300 18 'Criado por Yan Bento Monteiro'
    $autor.ForeColor = 'Gray'
    $btnFechar = Add-Ctl $f Button 472 436 72 30 'Fechar'
    $btnFechar.Add_Click({ $script:form.Close() })

    $script:editaveis = @($script:cmbDisco, $btnAtualizar, $script:rdColeta, $script:rdBoot, $script:btnPreparar, $btnFechar)
    $script:rodando = $false

    # Eventos
    $btnAtualizar.Add_Click({
        $script:form.Cursor = 'WaitCursor'
        Update-Discos
        $script:form.Cursor = 'Default'
    })
    $script:rdBoot.Add_CheckedChanged({ Set-Editavel $true })

    $script:btnIso.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Title = 'Selecione a ISO do Windows 10/11'
        $dlg.Filter = 'Imagem ISO (*.iso)|*.iso'
        if ($dlg.ShowDialog() -eq 'OK') { $script:txtIso.Text = $dlg.FileName }
    })

    $script:btnPreparar.Add_Click({ Start-Preparo })

    $f.Add_FormClosing({
        if ($script:rodando) {
            $r = Show-Msg "A preparação ainda está em andamento.`n`nFechar agora deixa o pendrive incompleto (dá para preparar de novo depois).`n`nFechar mesmo assim?" 'Warning' 'YesNo' 'Button2'
            if ($r -ne 'Yes') { $_.Cancel = $true }
        }
    })

    $script:timer = New-Object System.Windows.Forms.Timer
    $script:timer.Interval = 300
    $script:timer.Add_Tick({ Update-Andamento })

    Set-Editavel $true
    Update-Discos
    $f
}

function Start-Preparo {
    foreach ($n in 'ColetarInicializacao.bat', 'RepararInicializacao.bat') {
        if (-not (Test-Path (Join-Path $PSScriptRoot $n))) {
            [void](Show-Msg "Não encontrei o $n ao lado deste programa." 'Error'); return
        }
    }
    $disco = $script:discos[$script:cmbDisco.SelectedIndex]
    $modo = if ($script:rdBoot.Checked) { 2 } else { 1 }

    if ($modo -eq 2) {
        $iso = $script:txtIso.Text
        if (-not $iso -or -not (Test-Path $iso)) { [void](Show-Msg 'Clique em "Escolher ISO..." e selecione a ISO do Windows.' 'Warning'); return }
        $espaco = [math]::Min([double]$disco.Size, [double]31GB) * 0.97
        if ((Get-Item $iso).Length -gt $espaco) {
            [void](Show-Msg ("Este pendrive é pequeno demais para essa ISO.`n`nISO: {0}`nPendrive: {1}" -f (GB (Get-Item $iso).Length), (GB $disco.Size)) 'Warning'); return
        }
    }

    $txt = "Todo o conteúdo deste pendrive será APAGADO:`n`n    {0}`n`nDeseja continuar?" -f $script:cmbDisco.SelectedItem
    if ((Show-Msg $txt 'Warning' 'YesNo' 'Button2') -ne 'Yes') { return }

    $script:sync = [hashtable]::Synchronized(@{ Pct = 0; Status = 'Iniciando...'; Fim = $null; Erro = $null; Letra = $null; Aviso = $null })
    $param = @{ Disco = $disco.Number; Modo = $modo; Iso = $script:txtIso.Text; Script = $Script }
    $script:ps = [powershell]::Create()
    [void]$script:ps.AddScript($Trabalho).AddArgument($script:sync).AddArgument($param)
    $script:handle = $script:ps.BeginInvoke()
    $script:modoAtual = $modo

    $script:rodando = $true
    Set-Editavel $false
    $script:status.ForeColor = 'Black'
    $script:timer.Start()
}

function Update-Andamento {
    $s = $script:sync
    if ($s.Pct -lt 0) {
        $script:barra.Style = 'Marquee'
    } else {
        $script:barra.Style = 'Continuous'
        $script:barra.Value = [math]::Min(100, $s.Pct)
    }
    $script:status.Text = $s.Status
    if (-not $s.Fim) { return }

    $script:timer.Stop()
    try { [void]$script:ps.EndInvoke($script:handle) } catch {}
    $script:ps.Dispose()
    $script:rodando = $false
    Set-Editavel $true
    $script:barra.Style = 'Continuous'

    if ($s.Fim -eq 'ok') {
        $script:status.ForeColor = 'ForestGreen'
        $l = $s.Letra
        if ($script:modoAtual -eq 2) {
            $msg = "Pendrive pronto!`n`nComo usar no PC com problema:`n1. Conecte o pendrive.`n2. Ligue o PC apertando várias vezes a tecla do menu de boot`n   (F12, F11, F8 ou Esc, depende da marca) e escolha o pendrive.`n3. Aparece o menu de boot: espere 15 s (ou Enter) e o reparo abre sozinho.`n   Para TESTAR A MEMÓRIA: aperte TAB, escolha `"Teste de memoria (RAM)`" e Enter.`n4. No menu de reparo, digite o número recomendado.`n`nDica: colocando o USB em 1º lugar na ordem de boot da BIOS,`no PC liga direto no reparo sempre que o pendrive estiver plugado."
            if ($s.Aviso) { $msg += "`n`nAvisos:" + $s.Aviso }
            [void](Show-Msg $msg)
            Update-Discos
            return
        }
        $msg = "Pendrive pronto!`n`nComo usar no PC com problema:`n1. Conecte o pendrive.`n2. Na tela azul: Solução de Problemas > Opções avançadas > Prompt de Comando.`n3. Para CONSERTAR, digite:  ${l}:\RepararInicializacao.bat`n   Para só COLETAR informações:  ${l}:\ColetarInicializacao.bat`n   Se aparecer `"não é reconhecido`", a letra lá é outra:`n   tente E:, F:, G:...`n`nOs logs ficam salvos no próprio pendrive."
        [void](Show-Msg $msg)
        Update-Discos
    } else {
        $script:barra.Value = 0
        $script:status.ForeColor = 'Firebrick'
        $script:status.Text = 'Falhou: ' + $s.Erro
        [void](Show-Msg ("Não foi possível preparar o pendrive.`n`n" + $s.Erro) 'Error')
        Update-Discos
    }
}

# ---------------- Inicio ----------------
if ($MyInvocation.InvocationName -eq '.') { return }   # carregado so para testes

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    } catch {
        [void](Show-Msg 'É preciso permitir a execução como administrador para formatar o pendrive.' 'Warning')
    }
    exit
}

[System.Windows.Forms.Application]::EnableVisualStyles()
[void](New-Janela).ShowDialog()
