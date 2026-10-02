# ============================================================
#  Gera os executaveis em dist\ a partir de src\
#    dist\Pendrive de Recuperação.exe           (portatil)
#    dist\Instalar Pendrive de Recuperação.exe  (instalador)
#  Uso:  powershell -ExecutionPolicy Bypass -File build.ps1
# ============================================================
$ErrorActionPreference = 'Stop'
$src  = Join-Path $PSScriptRoot 'src'
$lan  = Join-Path $src 'launcher'
$dist = Join-Path $PSScriptRoot 'dist'
New-Item -ItemType Directory -Force $dist | Out-Null

# 1. Normaliza codificacao: .ps1 em UTF-8 com BOM (acentos no PowerShell 5.1),
#    .bat em CRLF (com LF o cmd se perde nos rotulos e entra em loop)
foreach ($f in Get-ChildItem $src -Filter *.ps1) {
    $t = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText($f.FullName, $t, (New-Object Text.UTF8Encoding $true))
    $erros = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$erros)
    if ($erros) { throw "Erro de sintaxe em $($f.Name): $($erros[0])" }
}
foreach ($f in Get-ChildItem $src -Filter *.bat) {
    $b = [IO.File]::ReadAllBytes($f.FullName)
    if ($b | Where-Object { $_ -gt 127 }) { throw "$($f.Name) tem caracteres fora do ASCII (acentos nao funcionam no cmd)." }
    $t = [IO.File]::ReadAllText($f.FullName) -replace "`r`n", "`n" -replace "`n", "`r`n"
    [IO.File]::WriteAllText($f.FullName, $t, (New-Object Text.UTF8Encoding $false))
}
Write-Host 'Fontes verificados.'

# 2. Compila
$csc = "$env:SystemRoot\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:SystemRoot\Microsoft.NET\Framework\v4.0.30319\csc.exe" }

function Compilar([string]$Saida, [string]$Principal, [string[]]$Recursos, [string]$Manifesto) {
    $sma = [PSObject].Assembly.Location   # System.Management.Automation.dll (PowerShell embutido)
    # anycpu: roda como 64 bits no Windows 64 e como 32 bits no Windows 32
    # (nunca 32 bits num Windows 64, o que quebraria dism/bcdedit por redirecionamento)
    $a = @('/nologo', '/target:winexe', '/platform:anycpu', '/codepage:65001', '/optimize+',
           "/win32icon:$lan\icone.ico", "/out:$Saida", '/r:System.Windows.Forms.dll', "/r:$sma")
    if ($Manifesto) { $a += "/win32manifest:$Manifesto" }
    $a += $Recursos | ForEach-Object { "/resource:$_" }
    $a += "$lan\Comum.cs", "$lan\$Principal"
    & $csc @a
    if ($LASTEXITCODE -ne 0) { throw "Falha ao compilar $Principal" }
    Write-Host ("  {0}  ({1:N0} KB)" -f (Split-Path $Saida -Leaf), ((Get-Item $Saida).Length / 1KB))
}

$portatil = Join-Path $dist 'Pendrive de Recuperação.exe'
Compilar $portatil 'Portatil.cs' @(
    "$src\PrepararPendrive.ps1,PrepararPendrive.ps1",
    "$src\ColetarInicializacao.bat,ColetarInicializacao.bat",
    "$src\RepararInicializacao.bat,RepararInicializacao.bat"
) "$lan\admin.manifest"

Compilar (Join-Path $dist 'Instalar Pendrive de Recuperação.exe') 'Instalar.cs' @(
    "$src\Instalador.ps1,Instalador.ps1",
    "$portatil,PendriveRecuperacao.exe"
) $null

Write-Host 'Pronto: executaveis em dist\'
