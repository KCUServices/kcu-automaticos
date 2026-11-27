# Vigia de servicos que se cura sozinho (de 5 em 5 min, escondido).
# Le a lista de servicos em servicos.json (copia servicos.exemplo.json e edita).
# Um servico que falha 2 verificacoes seguidas (~10 min) e reiniciado, com tentativas limitadas e cada vez mais
# espacadas: no maximo 3 em 24 h (a 1.a logo, a 2.a 30 min depois, a 3.a 60 min depois da 2.a). Esgotadas as
# tentativas, deixa de mexer no servico e pede ajuda UMA vez no Discord (e avisa quando ele voltar).
# Tambem avisa no Discord quando o PC volta depois de se desligar DE REPENTE (falta de luz: evento 6008).
# Registo: vigia_servicos.log ao lado deste script. Estado: vigia_servicos.estado.json (a pagina de estado le-o)
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir '..\comum\discord.ps1')
try { . (Join-Path $dir '..\alertas\alerta.ps1') } catch { }   # opcional: aviso no formato completo
$log = Join-Path $dir 'vigia_servicos.log'
$estadoPath = Join-Path $dir 'vigia_servicos.estado.json'
$configPath = Join-Path $dir 'servicos.json'
$MaxTentativas = 3          # em 24 h; igual a TENTATIVAS_MAX do estado-pagina\estados.py
$Esperas = 0, 30, 60        # minutos depois da tentativa anterior, antes da 1.a, 2.a e 3.a
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File $log -Append -Encoding utf8 }
if (-not (Test-Path $configPath)) { Log 'falta servicos.json (copia servicos.exemplo.json)'; exit 1 }
$servicos = Get-Content $configPath -Raw | ConvertFrom-Json
$temWebhook = [bool][Environment]::GetEnvironmentVariable('KCU_DISCORD_WEBHOOK', 'User')

$estado = @{}
if (Test-Path $estadoPath) { try { (Get-Content $estadoPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $estado[$_.Name] = @{ falhas = [int]$_.Value.falhas; tentativas = @($_.Value.tentativas | Where-Object { $_ }); avisado = [bool]$_.Value.avisado } } } catch { } }
function Avisar([string]$Nome, [string]$Chave, [string]$Evidencia, [string]$Simples, [switch]$Resolvido) {
    # true = avisado (ou sem webhook: nao ha a quem avisar); false = falhou, tenta outra vez na proxima volta
    if (-not $temWebhook) { return $true }
    $txt = $Simples
    if (Get-Command New-KcuAlerta -ErrorAction SilentlyContinue) {
        $txt = Format-KcuAlertaDiscord (New-KcuAlerta -Chave $Chave -Evidencia $Evidencia -Equipamento $env:COMPUTERNAME -Servico $Nome -Resolvido:$Resolvido `
            -Estado $(if ($Resolvido) { 'resolvido: ja responde' } else { 'precisa de ti: ja nao tento mais' }))
    }
    Enviar-Discord $txt "Vigia ($env:COMPUTERNAME)"
}

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
    if (-not $estado.ContainsKey($nome)) { $estado[$nome] = @{ falhas = 0; tentativas = @(); avisado = $false } }
    $e = $estado[$nome]
    $e.tentativas = @($e.tentativas | Where-Object { ($agora - [datetime]$_).TotalHours -lt 24 })
    if (Responde $s) {
        if ($e.falhas -ge 2) { Log "$nome voltou a responder" }
        if ($e.avisado -and -not (Avisar $nome "servico:${nome}:voltou" "$nome voltou a responder." "$nome voltou a responder.")) { Log 'aviso de volta falhou' }
        $e.falhas = 0; $e.avisado = $false; continue
    }
    $e.falhas++
    if ($e.falhas -lt 2) { continue }   # a 1.a falha so se confirma na volta seguinte
    $n = $e.tentativas.Count
    if ($n -ge $MaxTentativas) {
        if (-not $e.avisado) {
            Log "$nome continua em baixo depois de $n tentativas em 24 h: ja nao tento mais, a pedir ajuda"
            $e.avisado = [bool](Avisar $nome "servico:${nome}:esgotado" "$nome continua sem resposta depois de $n tentativas em 24 h." `
                ([char]::ConvertFromUtf32(0x1F6D1) + " O servico **$nome** no $env:COMPUTERNAME continua em baixo depois de $n tentativas em 24 h. Ja nao tento mais: precisa de ti."))
        }
        continue
    }
    $ultimo = if ($n) { [datetime]$e.tentativas[-1] } else { [datetime]::MinValue }
    $falta = $Esperas[$n] - ($agora - $ultimo).TotalMinutes
    if ($falta -gt 0) { Log "$nome continua sem resposta (tentativa $($n + 1)/$MaxTentativas daqui a $([math]::Ceiling($falta)) min)"; continue }
    Log "$nome sem resposta em $($e.falhas) verificacoes: a reiniciar (tentativa $($n + 1)/$MaxTentativas)"
    # um reinicio que falha tambem conta: senao um servico mal configurado era tentado de 5 em 5 min para sempre
    $e.tentativas += $agora.ToString('o')
    try { Reiniciar $s } catch { Log "${nome}: reinicio falhou ($($_.Exception.Message))" }
}
$estado | ConvertTo-Json -Depth 4 | Out-File $estadoPath -Encoding utf8
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
