# Sensores do PC (de 5 em 5 min, escondido): temperaturas do CPU e da GPU (LibreHardwareMonitor) e saude dos
# discos (smartctl, do smartmontools). Escreve sensores.json ao lado deste script.
# Limites em limites.json (copia limites.exemplo.json e edita). Sem limites.json usa os do exemplo.
# Avisa no Discord quando um alerta abre e quando fecha (nunca repete o mesmo enquanto continua aberto), no formato
# completo de ..\alertas (problema, evidencia, impacto, causa, solucao, historico de 7 dias).
# Opcional: um ficheiro hc.url ao lado deste script com o teu endereco de ping do Healthchecks. Sem alertas manda o
# sinal normal; com alertas marca o vigia como falhado e manda o texto dos alertas.
# Uso: sensores.ps1 [-Ensaio]
#   -Ensaio  le tudo e mostra o resultado e o que avisaria, mas nao escreve ficheiros nem avisa ninguem.
# Corre como administrador: sem isso o LibreHardwareMonitor nao le a temperatura do CPU.
param([switch]$Ensaio)
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $dir '..\comum\discord.ps1')
$log = Join-Path $dir 'sensores.log'
$saida = Join-Path $dir 'sensores.json'
$histF = Join-Path $dir 'sensores.historico.json'
function Log($m) { $l = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $(if ($Ensaio) { '[ensaio] ' })$m"; if ($Ensaio) { Write-Host $l } else { $l | Out-File $log -Append -Encoding utf8 } }

$cfgF = Join-Path $dir 'limites.json'
if (-not (Test-Path $cfgF)) { $cfgF = Join-Path $dir 'limites.exemplo.json' }
$L = [IO.File]::ReadAllText($cfgF, [Text.Encoding]::UTF8) | ConvertFrom-Json
$equip = if ($L.equipamento) { [string]$L.equipamento } else { $env:COMPUTERNAME }
function Caminho([string]$c) { if ([IO.Path]::IsPathRooted($c)) { $c } else { Join-Path $dir $c } }

$r = [ordered]@{ maquina = $equip; quando = (Get-Date).ToUniversalTime().ToString('o'); sensores = @(); discos = @(); erros = @() }

# ---- temperaturas, carga e ventoinhas (LibreHardwareMonitor)
try {
    if (-not (Test-Path (Caminho $L.lhm))) { throw "falta $($L.lhm) (ver o README)" }
    Add-Type -Path (Caminho $L.lhm)
    $c = New-Object LibreHardwareMonitor.Hardware.Computer
    $c.IsCpuEnabled = $true; $c.IsGpuEnabled = $true; $c.IsMotherboardEnabled = $true; $c.IsStorageEnabled = $true
    $c.Open()
    try {
        $tipos = 'Temperature', 'Load', 'Fan', 'Power'
        foreach ($h in $c.Hardware) {
            $h.Update(); foreach ($s in $h.SubHardware) { $s.Update() }
            foreach ($hw in @($h) + @($h.SubHardware)) {
                foreach ($s in $hw.Sensors) {
                    if ($null -ne $s.Value -and "$($s.SensorType)" -in $tipos) {
                        $r.sensores += [ordered]@{ peca = $hw.Name; tipo = "$($hw.HardwareType)"; sensor = $s.Name; medida = "$($s.SensorType)"; valor = [math]::Round([double]$s.Value, 1) }
                    }
                }
            }
        }
    } finally { $c.Close() }
} catch { $r.erros += "sensores: $($_.Exception.Message)" }

# ---- saude dos discos (smartctl)
$smart = Caminho $L.smartctl
if (Test-Path $smart) {
    try {
        foreach ($d in ((& $smart --scan -j | Out-String | ConvertFrom-Json).devices)) {
            $j = & $smart -j -H -A -i $d.name | Out-String | ConvertFrom-Json
            $attr = @{}; foreach ($a in $j.ata_smart_attributes.table) { $attr[[string]$a.id] = $a.raw.value }
            $r.discos += [ordered]@{
                disco = $d.name; modelo = $j.model_name; serie = $j.serial_number; saude = $(if ($j.smart_status) { if ($j.smart_status.passed) { 'PASSED' } else { 'FAILED' } } else { '?' })
                temperatura = $j.temperature.current; horas = $j.power_on_time.hours
                realocados = $attr['5']; pendentes = $attr['197']; incorrigiveis = $attr['198']
                nvme_gasto_pct = $j.nvme_smart_health_information_log.percentage_used; nvme_erros_media = $j.nvme_smart_health_information_log.media_errors
            }
        }
    } catch { $r.erros += "discos: $($_.Exception.Message)" }
} else { $r.erros += 'discos: smartctl nao encontrado (instala o smartmontools)' }

# ---- resumo: alertas (passou o limite "alerta") e avisos (passou o "aviso", so aparece na pagina de estado)
$maxT = { param($f) ($r.sensores | Where-Object { $_.medida -eq 'Temperature' -and (& $f $_) } | ForEach-Object { $_.valor } | Measure-Object -Maximum).Maximum }
$cpu = & $maxT { param($s) $s.tipo -eq 'Cpu' -and $s.sensor -match 'Tctl|Package|Tdie' }
$gpu = & $maxT { param($s) $s.tipo -match '^Gpu' -and $s.sensor -eq 'GPU Core' }
$hot = & $maxT { param($s) $s.tipo -match '^Gpu' -and $s.sensor -match 'Hot Spot' }
$cpuCarga = ($r.sensores | Where-Object { $_.tipo -eq 'Cpu' -and $_.medida -eq 'Load' -and $_.sensor -eq 'CPU Total' } | Select-Object -First 1).valor
$alertas = @(); $chaves = @(); $avisos = @(); $lista = @(); $falhou = $false
function Add-Alerta([string]$Chave, [string]$Texto) { $script:alertas += $Texto; $script:chaves += $Chave }  # chave = tipo no ..\alertas\catalogo.json
function Testar($Valor, $Limite, [string]$Chave, [string]$Nome) {
    if ($null -eq $Valor -or -not $Limite) { return }
    if ($Valor -ge $Limite.alerta) { Add-Alerta $Chave "$Nome muito quente: $Valor C (limite $($Limite.alerta) C)" }
    elseif ($Valor -ge $Limite.aviso) { $script:avisos += "$Nome a $Valor C (perto do limite de $($Limite.alerta) C)" }
}
if ($cpu) { $lista += "CPU $cpu C (carga $cpuCarga %)"; Testar $cpu $L.cpu 'hw-cpu-quente' 'CPU' }
if ($gpu) { $lista += "GPU $gpu C" + $(if ($hot) { " (hot spot $hot C)" } else { '' }); Testar $gpu $L.gpu 'hw-gpu-quente' 'GPU'; Testar $hot $L.gpu_hotspot 'hw-gpu-hotspot' 'GPU hot spot' }
foreach ($d in $r.discos) {
    $id = "$($d.modelo):$(if ($d.serie) { $d.serie } else { $d.disco })"  # chave por disco: dois discos iguais nao se misturam
    $nvme = $null -ne $d.nvme_gasto_pct
    $lista += "$($d.modelo): $($d.saude), $($d.temperatura) C" + $(if ($nvme) { ", $($d.nvme_gasto_pct) % gasto" } else { ", $($d.horas) h" })
    if ($d.saude -eq 'FAILED') { $falhou = $true; Add-Alerta "hw-disco-smart:$id" "Disco $($d.modelo): SMART FALHOU" }
    foreach ($k in 'realocados', 'pendentes', 'incorrigiveis', 'nvme_erros_media') { if ([int64]$d.$k -gt 0) { Add-Alerta "hw-disco-${k}:$id" "Disco $($d.modelo): $k = $($d.$k)" } }
    if ($nvme -and $L.nvme_gasto_pct -and $d.nvme_gasto_pct -ge $L.nvme_gasto_pct) { Add-Alerta "hw-disco-gasto:$id" "Disco $($d.modelo): $($d.nvme_gasto_pct) % gasto" }
    Testar $d.temperatura $(if ($nvme) { $L.nvme } else { $L.hdd }) "hw-disco-quente:$id" "Disco $($d.modelo)"
}
foreach ($e in $r.erros) { Add-Alerta ('hw-erro-' + ($e -split ':')[0]) $e }
$r.resumo = [ordered]@{ ok = ($alertas.Count -eq 0); falhou = $falhou; alertas = @($alertas); avisos = @($avisos); lista = @($lista) }

if ($Ensaio) { foreach ($x in $lista) { Log $x }; foreach ($x in $avisos) { Log "aviso: $x" }; foreach ($x in $alertas) { Log "ALERTA: $x" } }

# ---- avisos: so quando um alerta abre ou fecha (o historico guarda os abertos e as aberturas dos ultimos 7 dias)
$novos = @(); $texto = @($alertas)
try {
    . (Join-Path $dir '..\alertas\alerta.ps1')
    $h = Read-KcuHistorico $histF; $agora = [DateTimeOffset]::UtcNow
    $abertos = @{}; $texto = @()
    for ($i = 0; $i -lt $alertas.Count; $i++) {
        $k = $chaves[$i]
        if ($abertos.ContainsKey($k)) { continue }
        if ($h.abertos.ContainsKey($k)) {
            $abertos[$k] = $h.abertos[$k]; $n = Get-KcuContagem $h $k $agora
            $est = 'continua desde ' + (ConvertTo-KcuInstante $h.abertos[$k]).ToLocalTime().ToString('dd/MM HH:mm', [Globalization.CultureInfo]::InvariantCulture)
            $a = New-KcuAlerta -Chave $k -Evidencia $alertas[$i] -Equipamento $equip -Historico $n -Estado $est
        } else {
            $abertos[$k] = $agora.ToString('o'); $n = Add-KcuHistorico $h $k $agora $agora
            $a = New-KcuAlerta -Chave $k -Evidencia $alertas[$i] -Equipamento $equip -Historico $n -Estado 'novo'
            $novos += Format-KcuAlertaDiscord $a
        }
        $texto += Format-KcuAlertaTexto $a
    }
    foreach ($k in @($h.abertos.Keys)) {
        if (-not $abertos.ContainsKey($k)) {
            $a = New-KcuAlerta -Chave $k -Evidencia 'voltou ao normal' -Equipamento $equip -Historico (Get-KcuContagem $h $k $agora) -Estado 'resolvido' -Resolvido
            $novos += Format-KcuAlertaDiscord $a
        }
    }
    $h.abertos = $abertos
    if (-not $Ensaio) { Save-KcuHistorico $histF $h }
} catch { Log "historico ou formato dos alertas falhou ($($_.Exception.Message)): sem aviso no Discord nesta volta"; $novos = @() }

if ($Ensaio) {
    Log "faria sensores.json com $(@($r.sensores).Count) sensores e $(@($r.discos).Count) discos"
    foreach ($m in $novos) { Log "avisaria no Discord:`n$m" }
    return
}
$utf8 = New-Object Text.UTF8Encoding $false
[IO.File]::WriteAllText("$saida.tmp", ($r | ConvertTo-Json -Depth 5), $utf8); Move-Item "$saida.tmp" $saida -Force

# shortcut: um aviso que falhe a enviar nao se repete (o alerta ja ficou aberto); se precisares, ve o sensores.log
if ($novos.Count) { Log "$($novos.Count) alerta(s) abriram ou fecharam"; foreach ($m in @(Split-KcuAlertas "Sensores ($equip)" $novos)) { if (-not (Enviar-Discord $m "Sensores ($equip)")) { Log 'aviso no Discord nao saiu (sem KCU_DISCORD_WEBHOOK ou sem rede)' } } }

$hc = Join-Path $dir 'hc.url'
if (Test-Path $hc) {
    $u = (Get-Content $hc -Raw).Trim().TrimEnd('/')
    try {
        if ($alertas.Count) { Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Method Post -Uri "$u/fail" -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes(($texto -join "`n`n"))) | Out-Null }
        else { Invoke-WebRequest -UseBasicParsing -TimeoutSec 10 -Uri $u | Out-Null }
    } catch { Log "Healthchecks nao respondeu: $($_.Exception.Message)" }
}
if ((Test-Path $log) -and (Get-Item $log).Length -gt 200KB) { Get-Content $log -Tail 500 | Set-Content $log -Encoding utf8 }
