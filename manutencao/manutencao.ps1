# Manutencao automatica do Windows.
#   manutencao.ps1 -Diaria    leve (segundos): limpeza completa do %TEMP%, registos grandes, espaco livre
#   manutencao.ps1 -Semanal   completa (minutos): temporarios do Windows, cache de atualizacoes, relatorios de erro
#                             antigos, Docker (se existir), saude dos discos; 1.a semana do mes: limpeza do WinSxS
#   -Ensaio                   so mostra o que faria, nao apaga nada
# Regras: so apaga dentro das pastas listadas, nunca segue ligacoes, nunca toca em Transferencias, Documentos ou
# projetos. Corre com prioridade minima. Avisa no Discord so se um disco ficar com menos de 10 % livre ou deixar
# de estar saudavel. Registo: manutencao.log ao lado deste script.
param([switch]$Diaria, [switch]$Semanal, [switch]$Ensaio)

# >>> Pastas extra a limpar (ex.: a pasta temp do teu ComfyUI). Formato: @{ Pasta = '...'; Dias = 2; Nome = '...' }
$PastasExtra = @(
    # @{ Pasta = 'D:\ComfyUI\temp'; Dias = 2; Nome = 'ComfyUI temp' }
)
# >>> Registos de outros programas a encurtar quando passam de 2 MB
$RegistosExtra = @(
    # 'D:\ComfyUI\logs\comfyui.log'
)

$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir '..\comum\discord.ps1')
$log = Join-Path $dir 'manutencao.log'
$modo = if ($Semanal) { 'semanal' } else { 'diaria' }
try { (Get-Process -Id $PID).PriorityClass = 'Idle' } catch { }
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$modo$(if ($Ensaio) { ' ENSAIO' })] $m" | Out-File $log -Append -Encoding utf8 }
$total = 0L
function Limpar($pasta, $dias, $nome, $excluir = @()) {
    # apaga ficheiros com mais de $dias dias debaixo de $pasta (sem seguir ligacoes) e depois as pastas que ficaram vazias
    if (-not $pasta -or -not (Test-Path -LiteralPath $pasta)) { return }
    $limite = (Get-Date).AddDays(-$dias); $n = 0; $b = 0L; $t0 = Get-Date
    $pilha = New-Object System.Collections.Generic.Stack[string]; $pilha.Push($pasta); $pastas = New-Object System.Collections.Generic.List[string]
    while ($pilha.Count -and ((Get-Date) - $t0).TotalMinutes -lt 20) {
        $d = $pilha.Pop()
        try { $itens = [IO.Directory]::EnumerateFileSystemEntries($d) } catch { continue }
        try {
            foreach ($x in $itens) {
                try {
                    $a = [IO.File]::GetAttributes($x)
                    if ($a -band [IO.FileAttributes]::ReparsePoint) { continue }
                    if ($d -eq $pasta -and $excluir -contains (Split-Path $x -Leaf)) { continue }
                    if ($a -band [IO.FileAttributes]::Directory) { $pilha.Push($x); $pastas.Add($x); continue }
                    $fi = New-Object IO.FileInfo $x
                    if ($fi.LastWriteTime -lt $limite -and $fi.CreationTime -lt $limite) { $tam = $fi.Length; if (-not $Ensaio) { $fi.Delete() }; $n++; $b += $tam }
                } catch { }
            }
        } catch { }
    }
    if (-not $Ensaio) { for ($i = $pastas.Count - 1; $i -ge 0; $i--) { try { if ((New-Object IO.DirectoryInfo $pastas[$i]).LastWriteTime -lt $limite) { [IO.Directory]::Delete($pastas[$i], $false) } } catch { } } }
    $script:total += $b
    if ($n) { Log ("{0}: {1} ficheiros, {2:N0} MB ({3})" -f $nome, $n, ($b / 1MB), $(if ($dias -lt 1) { 'tudo o que nao estava em uso' } else { "mais de $dias dias" })) }
}
function Encurtar($ficheiro, $linhas) { if ((Test-Path $ficheiro) -and (Get-Item $ficheiro).Length -gt 2MB -and -not $Ensaio) { $c = Get-Content $ficheiro -Tail $linhas; $c | Set-Content $ficheiro -Encoding utf8; Log "registo encurtado: $(Split-Path $ficheiro -Leaf)" } }
function Avisar($txt) { if (-not $Ensaio) { if (-not (Enviar-Discord $txt "Manutencao ($env:COMPUTERNAME)")) { Log 'aviso no Discord nao enviado' } } }
function Livre { (Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' } | Sort-Object DriveLetter | ForEach-Object { "{0}: {1:N0} GB" -f $_.DriveLetter, ($_.SizeRemaining / 1GB) }) -join ' | ' }

Log "inicio | livre: $(Livre)"
# ---------------------------------------------------------------- todos os dias
# Limpeza COMPLETA do %TEMP%: fica so o que esta aberto por um programa, o que foi escrito nos ultimos 10 minutos
# (para nao partir uma instalacao a meio) e a pasta "claude" (sessoes abertas do Claude Code).
$recente = 10 / 1440
Limpar ([Environment]::GetEnvironmentVariable('TEMP', 'User')) $recente 'temporarios do utilizador' @('claude')
$velha = "$env:LOCALAPPDATA\Temp"; if ($velha -ne [Environment]::GetEnvironmentVariable('TEMP', 'User')) { Limpar $velha $recente 'Temp do perfil' @('claude') }
foreach ($e in $PastasExtra) { Limpar $e.Pasta $e.Dias $e.Nome }
foreach ($f in $RegistosExtra) { Encurtar $f 2000 }
Encurtar $log 3000

# ---------------------------------------------------------------- uma vez por semana
if ($Semanal) {
    Limpar "$env:SystemRoot\Temp" 7 'temporarios do Windows'
    Limpar "$env:ProgramData\Microsoft\Windows\WER\ReportArchive" 30 'relatorios de erro (arquivo)'
    Limpar "$env:ProgramData\Microsoft\Windows\WER\ReportQueue" 30 'relatorios de erro (fila)'
    Limpar "$env:LOCALAPPDATA\CrashDumps" 30 'despejos de falhas'
    Limpar "$env:SystemRoot\Minidump" 60 'minidumps'
    if (-not $Ensaio) { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop; Log 'cache de entrega de atualizacoes limpa' } catch { } }
    if ((Get-Command docker -ErrorAction SilentlyContinue) -and -not $Ensaio) { try { $o = (& docker system prune -f 2>&1 | Select-Object -Last 1); Log "docker system prune: $o" } catch { } }
    if ((Get-Command uv -ErrorAction SilentlyContinue) -and -not $Ensaio) { try { $o = (& uv cache prune 2>&1 | Select-Object -Last 1); Log "uv cache prune: $o" } catch { } }
    # 1.a semana do mes: limpar versoes antigas de componentes do Windows (pode demorar varios minutos)
    if ((Get-Date).Day -le 7 -and -not $Ensaio) { try { & dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet | Out-Null; Log "limpeza de componentes do Windows (codigo $LASTEXITCODE)" } catch { } }
    foreach ($d in Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        if ($d.HealthStatus -ne 'Healthy') { Log "DISCO COM PROBLEMA: $($d.FriendlyName) = $($d.HealthStatus)"; Avisar ([char]::ConvertFromUtf32(0x26A0) + " O disco $($d.FriendlyName) deixou de estar saudavel ($($d.HealthStatus)). Faz uma copia dos dados.") }
    }
}

# ---------------------------------------------------------------- espaco livre
foreach ($v in Get-Volume | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Fixed' -and $_.Size -gt 20GB }) {
    $pct = 100 * $v.SizeRemaining / $v.Size
    if ($pct -lt 10) {
        $marca = Join-Path $dir "manutencao.aviso-$($v.DriveLetter).txt"
        if (-not (Test-Path $marca) -or (Get-Item $marca).LastWriteTime -lt (Get-Date).AddDays(-3)) { Avisar ([char]::ConvertFromUtf32(0x26A0) + (" O disco {0}: esta com {1:N0} GB livres ({2:N0} %)." -f $v.DriveLetter, ($v.SizeRemaining / 1GB), $pct)); if (-not $Ensaio) { 'x' | Out-File $marca -Encoding ascii } }
        Log ("pouco espaco em {0}: {1:N0} GB ({2:N0} %)" -f $v.DriveLetter, ($v.SizeRemaining / 1GB), $pct)
    }
}
Log ("fim | {0:N0} MB libertados | livre: {1}" -f ($total / 1MB), (Livre))
