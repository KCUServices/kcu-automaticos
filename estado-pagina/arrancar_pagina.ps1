# Arranca a pagina de estado (estado_pagina.py) se ainda nao estiver a correr. Usado pela tarefa do instalar.ps1.
# Precisa do Python 3.8+ instalado (python.org ou "winget install Python.Python.3.12").
# Uso: arrancar_pagina.ps1 [-Ensaio]     -Ensaio faz as verificacoes uma vez e mostra-as, sem abrir a pagina.
param([switch]$Ensaio)
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $dir 'estado_pagina.log'
$py = Join-Path $dir 'estado_pagina.py'
function Log($m) { $l = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $(if ($Ensaio) { '[ensaio] ' })$m"; $l; if (-not $Ensaio) { $l | Out-File $log -Append -Encoding utf8 } }

# o "py" (lancador do python.org) primeiro; senao o python que estiver no PATH
$exe = $null; $args0 = @()
if (Get-Command py -ErrorAction SilentlyContinue) { $exe = 'py'; $args0 = @('-3') }
elseif (Get-Command python -ErrorAction SilentlyContinue) { $exe = 'python' }
if (-not $exe) { Log 'nao encontrei o Python (instala-o e volta a tentar)'; exit 1 }

if ($Ensaio) { & $exe @args0 -I $py --ensaio; return }

$cfg = Join-Path $dir 'verificacoes.json'
if (-not (Test-Path $cfg)) { $cfg = Join-Path $dir 'verificacoes.exemplo.json' }
$porta = 8765
try { $c = Get-Content $cfg -Raw | ConvertFrom-Json; if ($c.porta) { $porta = [int]$c.porta } } catch { }
if (Get-NetTCPConnection -LocalPort $porta -State Listen -ErrorAction SilentlyContinue) { Log "porta $porta ja esta a ouvir: nada a fazer"; exit 0 }
Log "a arrancar a pagina em http://127.0.0.1:$porta"
& $exe @args0 -I $py   # fica aqui enquanto a pagina estiver aberta
