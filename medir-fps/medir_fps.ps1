# Mede FPS e frametimes de um jogo com o PresentMon oficial da Intel.
# Mede N segundos, ignora os primeiros (voltar ao jogo a partir da consola da engasgos falsos) e calcula:
# FPS medio, FPS 1% baixo, frametime medio e p99, pior frame e quem limita (CPU ou GPU).
# Grava o CSV da captura e um resumo ultima-medicao.json na pasta de capturas.
#
# Uso (PowerShell como ADMINISTRADOR, com o jogo aberto e em primeiro plano):
#   powershell -ExecutionPolicy Bypass -File medir-fps\medir_fps.ps1                         # lista quem esta a desenhar no ecra
#   powershell -ExecutionPolicy Bypass -File medir-fps\medir_fps.ps1 -Jogo jogo.exe -Segundos 60
#   powershell -ExecutionPolicy Bypass -File medir-fps\medir_fps.ps1 -Csv capturas\jogo-20260101-120000.csv   # volta a analisar uma captura
#   -Ignorar 5        segundos iniciais a deitar fora
#   -Pasta <pasta>    onde ficam as capturas (por defeito, capturas\ ao lado deste script)
#   -PresentMon <exe> o PresentMon (por defeito, o PresentMon*.exe mais recente ao lado deste script)
param([string]$Jogo, [int]$Segundos = 60, [int]$Ignorar = 5, [string]$Pasta, [string]$PresentMon, [string]$Csv)
$ErrorActionPreference = 'Stop'
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Pasta) { $Pasta = Join-Path $dir 'capturas' }
New-Item -ItemType Directory -Force $Pasta | Out-Null

# O primeiro nome de coluna que existir (o PresentMon 1.x e 2.x usam nomes diferentes).
function Coluna($linha, [string[]]$nomes) {
  foreach ($n in $nomes) { if ($linha.PSObject.Properties.Name -contains $n) { return $n } }
  return $null
}
# Numero do CSV, ou nada se a celula nao for numero (ex.: NA).
function Num($s) {
  $v = 0.0
  if ([double]::TryParse([string]$s, [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) { return $v }
}

if (-not $Csv) {
  if (-not $PresentMon) {
    $pm = Get-ChildItem -Path $dir -Filter 'PresentMon*.exe' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $pm) { "Nao encontrei o PresentMon*.exe ao lado deste script. Descarrega-o (ver README) ou usa -PresentMon <caminho>."; return }
    $PresentMon = $pm.FullName
  }
  $admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  if (-not $admin) { "Aviso: nao estas como administrador. O PresentMon pode nao conseguir ver os jogos." }

  if (-not $Jogo) {
    $lista = Join-Path $Pasta 'lista.csv'
    $ErrorActionPreference = 'Continue'  # no PS 5.1, o stderr do .exe com 2>$null e EAP=Stop terminava o script
    & $PresentMon --timed 5 --terminate_after_timed --output_file $lista --no_console_stats 2>$null | Out-Null
    $ErrorActionPreference = 'Stop'
    if (-not (Test-Path $lista)) { "O PresentMon nao gravou nada em 5 s. Ha algum jogo aberto e em primeiro plano?"; return }
    "Quem desenhou no ecra nos ultimos 5 s:"
    Import-Csv $lista | Group-Object Application | Sort-Object Count -Descending | Select-Object -First 10 | ForEach-Object { "  {0}  ({1} frames)" -f $_.Name, $_.Count }
    Remove-Item $lista; return
  }
  if ($Jogo -notmatch '\.exe$') { $Jogo = "$Jogo.exe" }  # o --process_name do PresentMon precisa do .exe
  if (-not (Get-Process -Name ($Jogo -replace '\.exe$', '') -ErrorAction SilentlyContinue)) {
    "O $Jogo nao esta aberto. Abre o jogo, entra numa partida ou mapa e corre outra vez (sem -Jogo ves os nomes certos)."; return
  }
  $Csv = Join-Path $Pasta ("{0}-{1}.csv" -f ($Jogo -replace '\.exe$', ''), (Get-Date -Format 'yyyyMMdd-HHmmss'))
  "A medir $Jogo durante $Segundos s..."
  $ErrorActionPreference = 'Continue'
  & $PresentMon --process_name $Jogo --timed $Segundos --terminate_after_timed --output_file $Csv --no_console_stats 2>$null | Out-Null
  $ErrorActionPreference = 'Stop'
  if (-not (Test-Path $Csv)) { "O PresentMon nao gravou nada: o jogo desenhou algum frame nesses $Segundos s? (tem de estar em primeiro plano)"; return }
} elseif (-not (Test-Path $Csv)) { "Nao encontrei $Csv."; return }

$c = @(Import-Csv $Csv)
if ($c.Count -lt 10) { "Poucos frames ($($c.Count)). O jogo estava em primeiro plano?"; return }
if (-not $Jogo) { $Jogo = $c[0].Application }
$colFt = Coluna $c[0] @('FrameTime', 'MsBetweenPresents')
$colCpu = Coluna $c[0] @('CPUBusy', 'MsCPUBusy')
$colGpu = Coluna $c[0] @('GPUBusy', 'MsGPUBusy', 'MsGPUActive')
if (-not $colFt) { "O CSV nao tem coluna de frametime (FrameTime ou MsBetweenPresents)."; return }

# Ignorar os primeiros segundos, somando os frametimes (em ms em todas as versoes do PresentMon).
$soma = 0.0
$c = @($c | Where-Object { $v = Num $_.$colFt; if ($null -ne $v) { $soma += $v }; $soma -ge $Ignorar * 1000 })

$ft = @($c | ForEach-Object { Num $_.$colFt } | Where-Object { $_ -gt 0 } | Sort-Object)
if ($ft.Count -lt 10) { "Poucos frames depois de ignorar $Ignorar s ($($ft.Count)). Mede durante mais tempo."; return }
$cpu = if ($colCpu) { ($c | ForEach-Object { Num $_.$colCpu } | Measure-Object -Average).Average } else { 0 }
$gpu = if ($colGpu) { ($c | ForEach-Object { Num $_.$colGpu } | Measure-Object -Average).Average } else { 0 }
$media = ($ft | Measure-Object -Average).Average
$p99 = $ft[[math]::Max(0, [int][math]::Ceiling($ft.Count * 0.99) - 1)]
# 1% baixo: FPS medio do 1% de frames mais lentos.
$piores = $ft | Select-Object -Last ([math]::Max(1, [int][math]::Floor($ft.Count * 0.01)))
$umBaixo = 1000 / ($piores | Measure-Object -Average).Average
$limita = if (-not ($colCpu -and $colGpu)) { 'desconhecido' } elseif ($cpu -gt $gpu * 1.5) { 'CPU' } elseif ($gpu -gt $cpu * 1.5) { 'GPU' } else { 'equilibrado' }

$res = [ordered]@{
  quando = (Get-Date).ToUniversalTime().ToString('o'); jogo = $Jogo; frames = $ft.Count; ignorados_s = $Ignorar
  fps_medio = [math]::Round(1000 / $media, 1); fps_1pct_baixo = [math]::Round($umBaixo, 1)
  frametime_medio_ms = [math]::Round($media, 2); frametime_p99_ms = [math]::Round($p99, 2); pior_frame_ms = [math]::Round($ft[-1], 1)
  cpu_ms_por_frame = [math]::Round($cpu, 2); gpu_ms_por_frame = [math]::Round($gpu, 2); quem_limita = $limita
  ficheiro = (Split-Path -Leaf $Csv)
}
try {
  [IO.File]::WriteAllText((Join-Path $Pasta 'ultima-medicao.json'), ($res | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
} catch { "Aviso: nao consegui gravar ultima-medicao.json ($($_.Exception.Message))." }
New-Object PSObject -Property $res | Format-List
