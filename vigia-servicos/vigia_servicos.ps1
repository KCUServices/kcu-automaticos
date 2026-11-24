# Vigia de servicos que se cura sozinho (de 5 em 5 min, escondido).
# Le a lista de servicos em servicos.json (copia servicos.exemplo.json e edita).
# Um servico que falha 2 verificacoes seguidas (~10 min) e reiniciado. No maximo 1 reinicio por servico a cada 30 min.
# Tambem avisa no Discord quando o PC volta depois de se desligar DE REPENTE (falta de luz: evento 6008).
# Registo: vigia_servicos.log ao lado deste script. Estado: vigia_servicos.estado.json
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir '..\comum\discord.ps1')
$log = Join-Path $dir 'vigia_servicos.log'
$estadoPath = Join-Path $dir 'vigia_servicos.estado.json'
$configPath = Join-Path $dir 'servicos.json'
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File $log -Append -Encoding utf8 }
if (-not (Test-Path $configPath)) { Log 'falta servicos.json (copia servicos.exemplo.json)'; exit 1 }
$servicos = Get-Content $configPath -Raw | ConvertFrom-Json

$estado = @{}
if (Test-Path $estadoPath) { try { (Get-Content $estadoPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $estado[$_.Name] = @{ falhas = [int]$_.Value.falhas; reinicio = [string]$_.Value.reinicio } } } catch { } }

function Responde($s) {
    if ($s.url) { try { Invoke-WebRequest -UseBasicParsing $s.url -TimeoutSec 15 | Out-Null; return $true } catch { return $false } }
    if ($s.processo) { return [bool](Get-Process $s.processo -ErrorAction SilentlyContinue) }
    return $true
}
function Reiniciar($s) {
    # 1) mata os processos cujo comando contem "matar" (opcional)  2) arranca a tarefa agendada OU o programa
    if ($s.matar) {
        Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -match $s.matar -and $_.ProcessId -ne $PID } |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Start-Sleep 3
    }
    if ($s.tarefa) {
        $t = Get-ScheduledTask | Where-Object { $_.TaskName -eq $s.tarefa } | Select-Object -First 1
        if (-not $t) { throw "tarefa '$($s.tarefa)' nao existe" }
        Stop-ScheduledTask -InputObject $t -ErrorAction SilentlyContinue; Start-ScheduledTask -InputObject $t
    } elseif ($s.programa) { Start-Process $s.programa }
    else { throw 'sem "tarefa" nem "programa" para arrancar' }
}

$agora = Get-Date
foreach ($s in $servicos) {
    $nome = $s.nome
    if (-not $estado.ContainsKey($nome)) { $estado[$nome] = @{ falhas = 0; reinicio = '' } }
    $e = $estado[$nome]
    if (Responde $s) {
        if ($e.falhas -ge 2) { Log "$nome voltou a responder" }
        $e.falhas = 0; continue
    }
    $e.falhas++
    $ultimo = if ($e.reinicio) { [datetime]$e.reinicio } else { [datetime]::MinValue }
    if ($e.falhas -ge 2 -and ($agora - $ultimo).TotalMinutes -ge 30) {
        Log "$nome sem resposta em $($e.falhas) verificacoes: a reiniciar"
        try { Reiniciar $s; $e.reinicio = $agora.ToString('o') } catch { Log "${nome}: reinicio falhou ($($_.Exception.Message))" }
    } elseif ($e.falhas -ge 2) { Log "$nome continua sem resposta (ja reiniciado ha menos de 30 min)" }
}
$estado | ConvertTo-Json | Out-File $estadoPath -Encoding utf8
if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Get-Content $log -Tail 500 | Set-Content $log -Encoding utf8 }

# Falta de luz: sem "batimento" ha mais de 15 min E o Windows registou um desligar inesperado (evento 6008)
$batPath = Join-Path $dir 'vigia_batimento.txt'
$bat = if (Test-Path $batPath) { try { [datetime](Get-Content $batPath -Raw).Trim() } catch { $null } } else { $null }
$avisoFalhou = $false
$corte = $bat -and ($agora - $bat).TotalMinutes -gt 15 -and [bool](Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 6008; StartTime = $bat } -MaxEvents 1 -ErrorAction SilentlyContinue)
if ($corte) {
    $lista = ($servicos | ForEach-Object { if ($estado[$_.nome].falhas -eq 0) { "$($_.nome) ok" } else { "$($_.nome) a reiniciar" } }) -join ', '
    Log "parado de $($bat.ToString('dd/MM HH:mm')) a $($agora.ToString('dd/MM HH:mm'))"
    $txt = [char]::ConvertFromUtf32(0x26A1) + " O $env:COMPUTERNAME desligou-se de repente (falta de luz?) de $($bat.ToString('dd/MM HH:mm')) a $($agora.ToString('dd/MM HH:mm')). Servicos: $lista."
    if ([Environment]::GetEnvironmentVariable('KCU_DISCORD_WEBHOOK', 'User') -and -not (Enviar-Discord $txt "Vigia ($env:COMPUTERNAME)")) { $avisoFalhou = $true; Log 'aviso de queda falhou (tenta outra vez daqui a 5 min)' }
}
if (-not $avisoFalhou) { $agora.ToString('o') | Out-File $batPath -Encoding ascii }

# Opcional: scripts extra a correr a cada volta (ex.: ..\libertar-gpu\libertar_gpu_comfyui.ps1). Lista em extras.txt
$extras = Join-Path $dir 'extras.txt'
if (Test-Path $extras) { foreach ($x in Get-Content $extras | Where-Object { $_ -and $_ -notmatch '^\s*#' }) { try { & (Join-Path $dir $x.Trim()) | Out-Null } catch { Log "extra $x falhou: $($_.Exception.Message)" } } }
