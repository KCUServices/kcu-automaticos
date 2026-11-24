# Otimizar o Windows 10/11 SO com definicoes documentadas e que se desfazem.
# Cada mudanca guarda o valor de antes em otimizar_windows.antes.json (ao lado deste script) e -Desfazer repoe-o.
# A lista completa, com o que cada uma faz e como se desfaz a mao, esta no README.md desta pasta.
#
# Uso (PowerShell COMO ADMINISTRADOR, na TUA conta: as definicoes "HKCU" sao da conta que corre o script):
#   otimizar_windows.ps1 -Ensaio                mostra o que mudaria (valor atual -> valor novo), sem mudar nada
#   otimizar_windows.ps1                        pergunta grupo a grupo (grupos 1 a 5)
#   otimizar_windows.ps1 -Tudo                  faz os grupos 1 a 5 sem perguntar
#   otimizar_windows.ps1 -Desfazer [-Ensaio]    repoe tudo o que este script mudou
# Grupos opcionais (so correm se pedires o interruptor):
#   -ServicosExtra       desliga servicos que quase ninguem usa (mapas offline, modo de loja, fax, partilha do WMP)
#   -Jogos               Modo de Jogo, agendamento de GPU por hardware, otimizacao de jogos em janela, sem gravacao da Game Bar
#   -LimitarWSL [-WslGB 8]  limita a memoria do WSL/Docker (cria .wslconfig se ainda nao existir)
#   -SemIndexacao        desliga a indexacao da pesquisa do Windows (poupa o disco; a pesquisa fica mais lenta)
#   -RemoverApps         desinstala aplicacoes da Loja que vem de origem (pede SEMPRE confirmacao; NAO se desfaz
#                        com -Desfazer: reinstalam-se pela Microsoft Store)
# NUNCA toca em: Defender, firewall, UAC, Windows Update, drivers, plano de energia, ficheiros do sistema.
param([switch]$Ensaio, [switch]$Desfazer, [switch]$Tudo, [switch]$ServicosExtra, [switch]$Jogos,
      [switch]$LimitarWSL, [ValidateRange(2, 512)][int]$WslGB = 8, [switch]$SemIndexacao, [switch]$RemoverApps)
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$antesF = Join-Path $dir 'otimizar_windows.antes.json'
$log = Join-Path $dir 'otimizar_windows.log'
function Log($m) { $l = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $(if ($Ensaio) { '[ensaio] ' })$m"; Write-Host $l; if (-not $Ensaio) { $l | Out-File $log -Append -Encoding utf8 } }
function Sim($p) { if ($Ensaio -or $Tudo) { Log "--- $p"; return $true }; return ((Read-Host "`n$p [s/N]") -match '^[sS]') }
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin -and -not $Ensaio) { 'Corre isto como administrador (ou usa -Ensaio para so ver).'; exit 1 }

# ---------------- o que cada grupo muda ----------------
$ADV = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
$CDM = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
$SS = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\StorageSense\Parameters\StoragePolicy'
# 1. Telemetria: so o minimo obrigatorio de dados de diagnostico
$svcTelemetria = @('DiagTrack')
$tarTelemetria = @('\Microsoft\Windows\Customer Experience Improvement Program\|Consolidator',
    '\Microsoft\Windows\Customer Experience Improvement Program\|UsbCeip',
    '\Microsoft\Windows\DiskDiagnostic\|Microsoft-Windows-DiskDiagnosticDataCollector')
$regTelemetria = @(, @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'AllowTelemetry', 1, 'DWord'))
# 2. Publicidade, sugestoes, widgets e botao do Copilot (definicoes da tua conta)
$regAnuncios = @(
    @($ADV, 'TaskbarDa', 0, 'DWord'), @($ADV, 'ShowCopilotButton', 0, 'DWord'), @($ADV, 'Start_IrisRecommendations', 0, 'DWord'),
    @($ADV, 'ShowSyncProviderNotifications', 0, 'DWord'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings', 'IsDynamicSearchBoxEnabled', 0, 'DWord'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo', 'Enabled', 0, 'DWord'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy', 'TailoredExperiencesWithDiagnosticDataEnabled', 0, 'DWord'),
    @('HKCU:\Software\Microsoft\Siuf\Rules', 'NumberOfSIUFInPeriod', 0, 'DWord'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement', 'ScoobeSystemSettingEnabled', 0, 'DWord'),
    @($CDM, 'SilentInstalledAppsEnabled', 0, 'DWord'), @($CDM, 'SystemPaneSuggestionsEnabled', 0, 'DWord'), @($CDM, 'SoftLandingEnabled', 0, 'DWord'),
    @($CDM, 'SubscribedContent-310093Enabled', 0, 'DWord'), @($CDM, 'SubscribedContent-338388Enabled', 0, 'DWord'),
    @($CDM, 'SubscribedContent-338389Enabled', 0, 'DWord'), @($CDM, 'SubscribedContent-338393Enabled', 0, 'DWord'),
    @($CDM, 'SubscribedContent-353694Enabled', 0, 'DWord'), @($CDM, 'SubscribedContent-353696Enabled', 0, 'DWord'),
    @($CDM, 'RotatingLockScreenOverlayEnabled', 0, 'DWord'))
# 3. Atualizacoes: descarregar so da Microsoft, sem enviar pedacos a outros PCs
$regP2P = @(, @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization', 'DODownloadMode', 0, 'DWord'))
# 4. Edge: nao ficar a correr depois de fechado nem pre-carregar no arranque
$regEdge = @(@('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'StartupBoostEnabled', 0, 'DWord'), @('HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'BackgroundModeEnabled', 0, 'DWord'))
# 5. Sensor de Armazenamento semanal: temporarios + reciclagem com mais de 30 dias; Transferencias NUNCA
$regSensor = @(@($SS, '01', 1, 'DWord'), @($SS, '2048', 7, 'DWord'), @($SS, '04', 1, 'DWord'), @($SS, '08', 1, 'DWord'),
    @($SS, '256', 30, 'DWord'), @($SS, '32', 0, 'DWord'))
# Opcionais
$svcExtra = @('MapsBroker', 'RetailDemo', 'Fax', 'WMPNetworkSvc')
$tarExtra = @('\Microsoft\Windows\Maps\|MapsToastTask', '\Microsoft\Windows\Maps\|MapsUpdateTask')
$regJogos = @(
    @('HKCU:\Software\Microsoft\GameBar', 'AutoGameModeEnabled', 1, 'DWord'),
    @('HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers', 'HwSchMode', 2, 'DWord'),
    @('HKCU:\System\GameConfigStore', 'GameDVR_Enabled', 0, 'DWord'),
    @('HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR', 'AppCaptureEnabled', 0, 'DWord'))
$apps = 'Clipchamp.Clipchamp', 'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.BingSearch', 'Microsoft.MicrosoftSolitaireCollection',
    'Microsoft.WindowsFeedbackHub', 'Microsoft.Windows.DevHome', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.549981C3F5F10', 'Microsoft.People',
    'Microsoft.WindowsMaps', 'Microsoft.MixedReality.Portal', 'Microsoft.Microsoft3DViewer', 'Microsoft.SkypeApp'
$wsl = Join-Path $env:USERPROFILE '.wslconfig'

# ---------------- estado de antes ----------------
$antes = @{ servicos = @{}; tarefas = @{}; reg = @{}; chaves = @(); wsl = $false }
if (Test-Path $antesF) {
    $j = Get-Content $antesF -Raw | ConvertFrom-Json
    foreach ($s in 'servicos', 'tarefas', 'reg') { if ($j.$s) { $j.$s.PSObject.Properties | ForEach-Object { $antes[$s][$_.Name] = $_.Value } } }
    if ($j.chaves) { $antes.chaves = @($j.chaves) }
    $antes.wsl = [bool]$j.wsl
}
function Guardar { if (-not $Ensaio) { $antes | ConvertTo-Json -Depth 4 | Out-File $antesF -Encoding utf8 } }
function Ler($k, $n) { try { return (Get-ItemProperty -Path $k -Name $n -ErrorAction Stop).$n } catch { return $null } }
function RegPor($lista) {
    foreach ($r in $lista) {
        $k, $n, $v, $t = $r; $id = "$k|$n|$t"; $atual = Ler $k $n
        if ("$atual" -eq "$v") { Log "  $k\$n ja esta em $v"; continue }
        if ($Ensaio) { Log "  $k\$n : $(if ($null -eq $atual) { '(nao existe)' } else { $atual }) -> $v"; continue }
        if (-not $antes.reg.ContainsKey($id)) { $antes.reg[$id] = $atual }
        try {
            if (-not (Test-Path $k)) {
                # guarda a chave e cada chave-mae que ainda nao existia, para o -Desfazer as apagar se ficarem vazias
                $c = $k; while ($c -and -not (Test-Path $c)) { $antes.chaves += $c; $c = Split-Path $c -Parent }
                New-Item -Path $k -Force | Out-Null
            }
            Set-ItemProperty -Path $k -Name $n -Value $v -Type $t -ErrorAction Stop; Log "  $k\$n -> $v"
        } catch { Log "  aviso: $k\$n - $($_.Exception.Message)" }
    }
    Guardar
}
function SvcDesativar($nomes) {
    foreach ($n in $nomes) {
        $s = Get-Service $n -ErrorAction SilentlyContinue; if (-not $s) { Log "  servico $n nao existe neste Windows"; continue }
        if ("$($s.StartType)" -eq 'Disabled') { Log "  servico $n ja esta desativado"; continue }
        if ($Ensaio) { Log "  servico $n ($($s.StartType), $($s.Status)) -> Disabled"; continue }
        if (-not $antes.servicos.ContainsKey($n)) { $antes.servicos[$n] = "$($s.StartType)" }
        try { if ($s.Status -eq 'Running') { Stop-Service $n -Force -ErrorAction Stop }; Set-Service $n -StartupType Disabled -ErrorAction Stop; Log "  servico $n desativado (era $($antes.servicos[$n]))" }
        catch { Log "  aviso: $n - $($_.Exception.Message)" }
    }
    Guardar
}
function TarDesativar($lista) {
    foreach ($x in $lista) {
        $p, $n = $x -split '\|'; $t = Get-ScheduledTask -TaskPath $p -TaskName $n -ErrorAction SilentlyContinue
        if (-not $t) { Log "  tarefa $n nao existe neste Windows"; continue }
        if ($t.State -eq 'Disabled') { Log "  tarefa $n ja esta desativada"; continue }
        if ($Ensaio) { Log "  tarefa $n ($($t.State)) -> desativada"; continue }
        if (-not $antes.tarefas.ContainsKey($x)) { $antes.tarefas[$x] = $true }
        try { Disable-ScheduledTask -TaskPath $p -TaskName $n -ErrorAction Stop | Out-Null; Log "  tarefa $n desativada" } catch { Log "  aviso: tarefa $n - $($_.Exception.Message)" }
    }
    Guardar
}
# Jogos em janela: junta "SwapEffectUpgradeEnable=1" ao que ja la esta, sem apagar as outras opcoes (ex.: HDR automatico)
function DirectXJanela {
    $k = 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences'; $n = 'DirectXUserGlobalSettings'
    $d = [ordered]@{}
    foreach ($par in ("$(Ler $k $n)" -split ';')) { if ($par -match '^(.+?)=(.*)$') { $d[$Matches[1]] = $Matches[2] } }
    $d['SwapEffectUpgradeEnable'] = '1'
    RegPor @(, @($k, $n, ((($d.Keys | ForEach-Object { "$_=$($d[$_])" }) -join ';') + ';'), 'String'))
}

# ---------------- desfazer ----------------
if ($Desfazer) {
    if (-not (Test-Path $antesF)) { Log 'nada para desfazer (nao ha otimizar_windows.antes.json)'; exit 0 }
    Log '=== DESFAZER ==='
    foreach ($n in @($antes.servicos.Keys)) {
        if ($Ensaio) { Log "  servico $n -> $($antes.servicos[$n])"; continue }
        try { Set-Service $n -StartupType $antes.servicos[$n] -ErrorAction Stop; Log "  servico $n -> $($antes.servicos[$n])" } catch { Log "  aviso: $n - $($_.Exception.Message)" }
    }
    foreach ($x in @($antes.tarefas.Keys)) {
        $p, $n = $x -split '\|'
        if ($Ensaio) { Log "  tarefa $n -> reativada"; continue }
        Enable-ScheduledTask -TaskPath $p -TaskName $n -ErrorAction SilentlyContinue | Out-Null; Log "  tarefa $n reativada"
    }
    foreach ($id in @($antes.reg.Keys)) {
        $k, $n, $t = $id -split '\|'; $v = $antes.reg[$id]
        if ($Ensaio) { Log "  $k\$n -> $(if ($null -eq $v) { '(apagado)' } else { $v })"; continue }
        if ($null -eq $v) { Remove-ItemProperty -Path $k -Name $n -ErrorAction SilentlyContinue } else { Set-ItemProperty -Path $k -Name $n -Value $v -Type $t -ErrorAction SilentlyContinue }
    }
    # chaves que o script criou e que ficaram vazias
    foreach ($k in @($antes.chaves | Select-Object -Unique | Sort-Object Length -Descending)) {   # as mais fundas primeiro
        if ($Ensaio) { Log "  apagaria a chave $k se ficar vazia"; continue }
        $c = Get-Item $k -ErrorAction SilentlyContinue
        if ($c -and $c.ValueCount -eq 0 -and $c.SubKeyCount -eq 0) { Remove-Item $k -ErrorAction SilentlyContinue; Log "  chave vazia $k apagada" }
    }
    if ($antes.wsl -and (Test-Path $wsl)) { if ($Ensaio) { Log "  apagaria $wsl" } else { Remove-Item $wsl; Log "  $wsl apagado" } }
    if (-not $Ensaio) {
        Move-Item $antesF (Join-Path $dir ("otimizar_windows.antes.{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss')))
        Log '=== DESFEITO. Reinicia o PC. (Aplicacoes desinstaladas com -RemoverApps reinstalam-se pela Microsoft Store.) ==='
    }
    exit 0
}

# ---------------- aplicar ----------------
Log "=== OTIMIZAR O WINDOWS ($env:COMPUTERNAME) ==="
if (Sim '1. Telemetria: enviar so os dados de diagnostico obrigatorios e desligar o servico e as tarefas de recolha?') {
    RegPor $regTelemetria; SvcDesativar $svcTelemetria; TarDesativar $tarTelemetria; Log 'grupo 1 feito' }
if (Sim '2. Desligar publicidade, sugestoes, widgets e o botao do Copilot?') { RegPor $regAnuncios; Log 'grupo 2 feito (vale depois de terminar sessao)' }
if (Sim '3. Atualizacoes: deixar de enviar e receber pedacos de atualizacoes de outros PCs?') { RegPor $regP2P; Log 'grupo 3 feito' }
if (Sim '4. Edge: nao ficar a correr em segundo plano nem pre-carregar no arranque?') { RegPor $regEdge; Log 'grupo 4 feito' }
if (Sim '5. Ligar a limpeza automatica semanal (temporarios e reciclagem com mais de 30 dias; Transferencias nunca)?') { RegPor $regSensor; Log 'grupo 5 feito' }

if ($ServicosExtra -and (Sim 'Extra: desligar mapas offline, modo de demonstracao de loja, fax e partilha do Windows Media Player?')) {
    SvcDesativar $svcExtra; TarDesativar $tarExtra; Log 'servicos extra feito' }
if ($Jogos -and (Sim 'Jogos: Modo de Jogo, agendamento de GPU por hardware, otimizacao de jogos em janela, sem gravacao da Game Bar?')) {
    RegPor $regJogos; DirectXJanela; Log 'jogos feito (o agendamento de GPU so vale depois de reiniciar)' }
if ($LimitarWSL -and (Sim "WSL: limitar a memoria do WSL/Docker a $WslGB GB?")) {
    if (Test-Path $wsl) { Log "  $wsl ja existe: nao lhe mexo (edita-o a mao: [wsl2] memory=${WslGB}GB)" }
    elseif ($Ensaio) { Log "  criaria $wsl com memory=${WslGB}GB" }
    else { "[wsl2]`r`nmemory=${WslGB}GB`r`n" | Out-File $wsl -Encoding ascii -NoNewline; $antes.wsl = $true; Guardar; Log "  $wsl criado (vale depois de 'wsl --shutdown' ou de reiniciar)" }
}
if ($SemIndexacao -and (Sim 'Desligar a indexacao da pesquisa? Poupa o disco, mas a pesquisa no Explorador, no Iniciar e no Outlook fica mais lenta.')) {
    SvcDesativar @('WSearch'); Log 'indexacao feito' }
if ($RemoverApps) {
    $tem = @(Get-AppxPackage | Where-Object { $apps -contains $_.Name })
    if (-not $tem.Count) { Log 'nenhuma das aplicacoes da lista esta instalada' }
    elseif ($Ensaio) { Log "desinstalaria (para esta conta): $(($tem | ForEach-Object Name | Sort-Object) -join ', ')" }
    elseif ((Read-Host "`nDesinstalar estas aplicacoes? NAO se desfaz com -Desfazer (reinstalam-se pela Microsoft Store):`n   $(($tem | ForEach-Object Name | Sort-Object) -join ', ')`n   [s/N]") -match '^[sS]') {
        foreach ($a in $tem) { try { Remove-AppxPackage -Package $a.PackageFullName -ErrorAction Stop; Log "  desinstalada: $($a.Name)" } catch { Log "  aviso: $($a.Name) - $($_.Exception.Message)" } }
    }
}
if ($Ensaio) { Log '=== ENSAIO: nada foi mudado ===' } else { Log '=== FEITO. Reinicia o PC. Para voltar atras: -Desfazer ===' }
