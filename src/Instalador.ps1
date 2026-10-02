# ============================================================
#  Instalador do "Pendrive de Recuperação"
#   - Copia as ferramentas para uma pasta (padrão não exige admin)
#   - Cria atalhos na Área de Trabalho e/ou Menu Iniciar
#   - Registra em "Aplicativos instalados" para desinstalar
#  Abrir pelo Instalar.bat.  Desinstalar: Instalador.ps1 -Desinstalar
# ============================================================
param([switch]$Desinstalar)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing

$App = @{
    Nome     = 'Pendrive de Recuperação'
    Id       = 'PendriveRecuperacao'
    Versao   = '1.0'
    Exe      = 'Pendrive de Recuperação.exe'
    Arquivos = @('Pendrive de Recuperação.exe', 'Instalador.ps1')
    # Arquivos da versao 1.0 (scripts soltos), removidos ao atualizar/desinstalar
    Antigos  = @('PrepararPendrive.bat', 'PrepararPendrive.ps1', 'ColetarInicializacao.bat', 'RepararInicializacao.bat')
    Icone    = "$env:SystemRoot\System32\shell32.dll,7"
    Autor    = 'Criado por Yan Bento Monteiro'
}
$ChaveRegistro = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\$($App.Id)"
$PastaPadrao   = Join-Path $env:LOCALAPPDATA "Programs\$($App.Id)"

# ---------------- Instalação / desinstalação ----------------

function Get-Instalacao {
    $p = Get-ItemProperty $ChaveRegistro -ErrorAction SilentlyContinue
    if ($p) { $p.InstallLocation }
}

function Get-Atalhos {
    [pscustomobject]@{
        Desktop = Join-Path ([Environment]::GetFolderPath('Desktop'))  "$($App.Nome).lnk"
        Menu    = Join-Path ([Environment]::GetFolderPath('Programs')) "$($App.Nome).lnk"
    }
}

function New-Atalho([string]$Caminho, [string]$Pasta) {
    $exe = Join-Path $Pasta $App.Exe
    $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut($Caminho)
    $lnk.TargetPath       = $exe
    $lnk.WorkingDirectory = $Pasta
    $lnk.IconLocation     = "$exe,0"
    $lnk.Description      = 'Prepara pendrive de coleta ou bootável para recuperação do Windows'
    $lnk.Save()
}

function Set-Progresso([int]$Pct, [string]$Msg) {
    if ($script:barra) {
        $script:barra.Value = $Pct
        $script:status.Text = $Msg
        [System.Windows.Forms.Application]::DoEvents()
    }
}

function Install-App([string]$Pasta, [bool]$Desktop, [bool]$Menu) {
    $faltando = @($App.Arquivos | Where-Object { -not (Test-Path (Join-Path $PSScriptRoot $_)) })
    if ($faltando) { throw "Arquivos não encontrados ao lado do instalador:`n$($faltando -join "`n")" }

    $Pasta = [IO.Path]::GetFullPath($Pasta)
    Set-Progresso 10 'Criando pasta...'
    New-Item -ItemType Directory -Force -Path $Pasta | Out-Null

    $i = 0
    foreach ($a in $App.Arquivos) {
        $i++
        Set-Progresso (10 + 50 * $i / $App.Arquivos.Count) "Copiando $a..."
        $orig = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $a))
        $dest = Join-Path $Pasta $a
        if ($orig -ne $dest) { Copy-Item $orig $dest -Force }
    }
    foreach ($a in $App.Antigos) { Remove-Item (Join-Path $Pasta $a) -Force -ErrorAction SilentlyContinue }

    Set-Progresso 70 'Criando atalhos...'
    $at = Get-Atalhos
    Remove-Item $at.Desktop, $at.Menu -Force -ErrorAction SilentlyContinue
    if ($Desktop) { New-Atalho $at.Desktop $Pasta }
    if ($Menu)    { New-Atalho $at.Menu $Pasta }

    Set-Progresso 90 'Registrando desinstalador...'
    $ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $kb = [int]((Get-ChildItem $Pasta -File | Measure-Object Length -Sum).Sum / 1KB)
    New-Item $ChaveRegistro -Force | Out-Null
    $textos = [ordered]@{
        DisplayName     = $App.Nome
        DisplayVersion  = $App.Versao
        DisplayIcon     = "$(Join-Path $Pasta $App.Exe),0"
        Publisher       = 'Yan Bento Monteiro'
        InstallLocation = $Pasta
        UninstallString = "`"$ps`" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$Pasta\Instalador.ps1`" -Desinstalar"
    }
    foreach ($k in $textos.Keys) {
        New-ItemProperty $ChaveRegistro -Name $k -Value $textos[$k] -PropertyType String -Force | Out-Null
    }
    $numeros = @{ NoModify = 1; NoRepair = 1; EstimatedSize = $kb }
    foreach ($k in $numeros.Keys) {
        New-ItemProperty $ChaveRegistro -Name $k -Value $numeros[$k] -PropertyType DWord -Force | Out-Null
    }

    Set-Progresso 100 'Instalação concluída.'
}

function Uninstall-App {
    $pasta = Get-Instalacao
    $at = Get-Atalhos
    Remove-Item $at.Desktop, $at.Menu -Force -ErrorAction SilentlyContinue
    Remove-Item $ChaveRegistro -Recurse -Force -ErrorAction SilentlyContinue
    if ($pasta -and (Test-Path $pasta)) {
        Set-Location $env:TEMP
        # Apaga só os arquivos instalados; a pasta só sai se ficar vazia
        foreach ($a in ($App.Arquivos + $App.Antigos)) { Remove-Item (Join-Path $pasta $a) -Force -ErrorAction SilentlyContinue }
        if (-not (Get-ChildItem $pasta -Force)) { Remove-Item $pasta -Force }
    }
}

# ---------------- Interface ----------------

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

function Add-Ctl($Pai, [string]$Tipo, [int]$X, [int]$Y, [int]$W, [int]$H, $Texto) {
    $c = New-Object "System.Windows.Forms.$Tipo"
    $c.SetBounds($X, $Y, $W, $H)
    if ($null -ne $Texto) { $c.Text = $Texto }
    $Pai.Controls.Add($c)
    $c
}

function Show-Msg([string]$Texto, [string]$Icone = 'Information', [string]$Botoes = 'OK') {
    [System.Windows.Forms.MessageBox]::Show($Texto, $App.Nome, $Botoes, $Icone)
}

function New-Janela {
    $instalado = Get-Instalacao
    $at = Get-Atalhos
    $icone = Get-IconeApp

    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Instalar - $($App.Nome)"
    $f.Font = New-Object System.Drawing.Font('Segoe UI', 9)
    $f.ClientSize = New-Object System.Drawing.Size(520, 394)
    $f.FormBorderStyle = 'FixedDialog'
    $f.MaximizeBox = $false
    $f.MinimizeBox = $false
    $f.StartPosition = 'CenterScreen'
    if ($icone) { $f.Icon = $icone }
    $script:form = $f

    # Cabeçalho
    $topo = Add-Ctl $f Panel 0 0 520 70 $null
    $topo.BackColor = 'White'
    $pic = Add-Ctl $topo PictureBox 16 15 40 40 $null
    $pic.SizeMode = 'CenterImage'
    if ($icone) { $pic.Image = $icone.ToBitmap() }
    $titulo = Add-Ctl $topo Label 66 12 440 28 $App.Nome
    $titulo.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
    $sub = Add-Ctl $topo Label 68 42 440 20 "Assistente de instalação - versão $($App.Versao)"
    $sub.ForeColor = 'DimGray'
    (Add-Ctl $f Label 0 70 520 2 $null).BorderStyle = 'Fixed3D'

    # Corpo
    [void](Add-Ctl $f Label 16 84 488 36 'Instala o Pendrive de Recuperação neste computador e cria os atalhos escolhidos. Com ele você prepara pendrives que consertam a inicialização do Windows.')
    [void](Add-Ctl $f Label 16 128 488 18 'Pasta de instalação:')
    $script:txtPasta = Add-Ctl $f TextBox 16 148 392 24 $(if ($instalado) { $instalado } else { $PastaPadrao })
    $btnProcurar = Add-Ctl $f Button 416 147 88 26 'Procurar...'

    $grupo = Add-Ctl $f GroupBox 16 184 488 78 'Criar atalhos'
    $script:chkDesktop = Add-Ctl $grupo CheckBox 14 22 300 22 'Área de Trabalho'
    $script:chkMenu    = Add-Ctl $grupo CheckBox 14 46 300 22 'Menu Iniciar'
    $script:chkDesktop.Checked = (-not $instalado) -or (Test-Path $at.Desktop)
    $script:chkMenu.Checked    = (-not $instalado) -or (Test-Path $at.Menu)

    $script:chkAbrir = Add-Ctl $f CheckBox 16 270 488 22 'Abrir o programa ao concluir'

    $script:barra  = Add-Ctl $f ProgressBar 16 300 488 18 $null
    $script:status = Add-Ctl $f Label 16 322 488 18 $(if ($instalado) { "Já instalado em: $instalado" } else { 'Pronto para instalar.' })
    $script:status.ForeColor = 'DimGray'

    # Rodapé
    (Add-Ctl $f Label 0 348 520 2 $null).BorderStyle = 'Fixed3D'
    $script:btnDesinstalar = Add-Ctl $f Button 16 358 96 28 'Desinstalar'
    $script:btnDesinstalar.Visible = [bool]$instalado
    $xAutor = if ($instalado) { 122 } else { 16 }
    $script:autor = Add-Ctl $f Label $xAutor 365 190 18 $App.Autor
    $script:autor.ForeColor = 'Gray'
    $script:btnInstalar = Add-Ctl $f Button 316 358 92 28 $(if ($instalado) { 'Reinstalar' } else { 'Instalar' })
    $script:btnCancelar = Add-Ctl $f Button 416 358 88 28 'Cancelar'
    $script:btnCancelar.DialogResult = 'Cancel'
    $f.AcceptButton = $script:btnInstalar
    $f.CancelButton = $script:btnCancelar

    $script:editaveis = @($script:txtPasta, $btnProcurar, $script:chkDesktop, $script:chkMenu, $script:chkAbrir,
                          $script:btnInstalar, $script:btnCancelar, $script:btnDesinstalar)
    $script:concluido = $false

    $btnProcurar.Add_Click({
        $d = New-Object System.Windows.Forms.FolderBrowserDialog
        $d.Description = 'Escolha onde instalar'
        if ($d.ShowDialog() -eq 'OK') {
            $p = $d.SelectedPath
            if ((Split-Path $p -Leaf) -ne $App.Id) { $p = Join-Path $p $App.Id }
            $script:txtPasta.Text = $p
        }
    })

    $script:btnInstalar.Add_Click({
        if ($script:concluido) {
            if ($script:chkAbrir.Checked) { Start-Process (Join-Path $script:txtPasta.Text $App.Exe) }
            $script:form.Close()
            return
        }
        $pasta = $script:txtPasta.Text.Trim()
        if (-not $pasta) { [void](Show-Msg 'Informe a pasta de instalação.' 'Warning'); return }

        foreach ($c in $script:editaveis) { $c.Enabled = $false }
        try {
            Install-App $pasta $script:chkDesktop.Checked $script:chkMenu.Checked
            $script:concluido = $true
            $script:btnInstalar.Text = 'Concluir'
            $script:btnInstalar.Enabled = $true
            $script:chkAbrir.Enabled = $true
            $script:btnCancelar.Visible = $false
            $script:btnDesinstalar.Visible = $false
            $script:autor.Left = 16
        } catch {
            Set-Progresso 0 'Falha na instalação.'
            $msg = $_.Exception.Message
            if ($_.Exception -is [UnauthorizedAccessException] -or $_.CategoryInfo.Category -eq 'PermissionDenied') {
                $msg += "`n`nSem permissão para gravar nessa pasta. Escolha outra ou execute como administrador."
            }
            [void](Show-Msg $msg 'Error')
            foreach ($c in $script:editaveis) { $c.Enabled = $true }
        }
    })

    $script:btnDesinstalar.Add_Click({
        if ((Show-Msg "Remover o $($App.Nome) e seus atalhos?" 'Question' 'YesNo') -ne 'Yes') { return }
        try {
            Uninstall-App
            [void](Show-Msg 'Programa removido.')
            $script:form.Close()
        } catch {
            [void](Show-Msg $_.Exception.Message 'Error')
        }
    })

    $f
}

# ---------------- Início ----------------
if ($MyInvocation.InvocationName -eq '.') { return }   # carregado só para testes

[System.Windows.Forms.Application]::EnableVisualStyles()

if ($Desinstalar) {
    if ((Show-Msg "Deseja remover o $($App.Nome) e seus atalhos?" 'Question' 'YesNo') -eq 'Yes') {
        try { Uninstall-App; [void](Show-Msg 'Programa removido.') }
        catch { [void](Show-Msg $_.Exception.Message 'Error') }
    }
    return
}

[void](New-Janela).ShowDialog()
