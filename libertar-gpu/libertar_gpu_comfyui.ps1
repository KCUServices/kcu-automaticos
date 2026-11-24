# Liberta a placa grafica quando o ComfyUI esta parado com modelos carregados (para os jogos terem a placa toda).
# Pensado para correr a cada volta do vigia de servicos (ver ..\vigia-servicos\extras.exemplo.txt).
# Se o ComfyUI estiver parado (sem trabalhos) com mais de 1 GB na placa em 2 verificacoes seguidas, pede-lhe para
# descarregar os modelos. Nunca interrompe um trabalho; o proximo pedido volta a carregar o modelo.
# Desligar: criar "nao_libertar_gpu.txt" ao lado deste script.
param([string]$Url = 'http://127.0.0.1:8188')
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$estadoPath = Join-Path $dir 'libertar_gpu.estado.json'
$log = Join-Path $dir 'libertar_gpu.log'
if (Test-Path (Join-Path $dir 'nao_libertar_gpu.txt')) { return }
function Log($m) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File $log -Append -Encoding utf8 }
$parado = 0
if (Test-Path $estadoPath) { try { $parado = [int](Get-Content $estadoPath -Raw | ConvertFrom-Json).parado } catch { } }
try {
    $s = Invoke-RestMethod "$Url/system_stats" -TimeoutSec 10
    $q = Invoke-RestMethod "$Url/queue" -TimeoutSec 10
    $gb = [double]($s.devices | Select-Object -First 1).torch_vram_total / 1GB
    $ocupado = (@($q.queue_running).Count + @($q.queue_pending).Count) -gt 0
    if ($ocupado -or $gb -lt 1) { $parado = 0 }
    else {
        $parado++
        if ($parado -ge 2) {
            Invoke-RestMethod "$Url/free" -Method Post -ContentType 'application/json' -Body '{"unload_models": true, "free_memory": true}' -TimeoutSec 20 | Out-Null
            Log ("ComfyUI parado com {0:N1} GB na placa grafica: pedi para descarregar" -f $gb)
            $parado = 0
        }
    }
} catch { $parado = 0 }
@{ parado = $parado } | ConvertTo-Json | Out-File $estadoPath -Encoding ascii
