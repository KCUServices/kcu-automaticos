# Arranque: ao entrar no Windows, abre os programas e servicos da lista arranque.json, SO se ainda nao estiverem
# a correr (pode correr as vezes que quiseres sem abrir nada duas vezes).
# "Esta a correr" = a porta local esta a ouvir ("porta") OU o processo existe ("processo").
# Registo: arranque.log ao lado deste script.  Testar sem abrir nada:  arranque.ps1 -Ensaio
param([switch]$Ensaio)
$dir = Split-Path -Parent $MyInvocation.MyCommand.Path
$log = Join-Path $dir 'arranque.log'
$cfg = Join-Path $dir 'arranque.json'
function Log($m) { $l = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $(if ($Ensaio) { '[ensaio] ' })$m"; $l; if (-not $Ensaio) { $l | Out-File $log -Append -Encoding utf8 } }
if (-not (Test-Path $cfg)) { Log 'falta arranque.json (copia arranque.exemplo.json)'; exit 1 }
function Ouve($p) { [bool](Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue) }

foreach ($a in (Get-Content $cfg -Raw | ConvertFrom-Json)) {
    $corre = ($a.porta -and (Ouve $a.porta)) -or ($a.processo -and (Get-Process $a.processo -ErrorAction SilentlyContinue))
    if ($corre) { Log "$($a.nome): ja esta a correr"; continue }
    if ($Ensaio) { Log "$($a.nome): abria $($a.programa) $($a.argumentos)"; continue }
    $p = @{ FilePath = $a.programa }
    if ($a.argumentos) { $p.ArgumentList = $a.argumentos }
    if ($a.pasta) { $p.WorkingDirectory = $a.pasta }
    if ($a.escondido) { $p.WindowStyle = 'Hidden' }
    try { Start-Process @p; Log "$($a.nome): aberto" } catch { Log "$($a.nome): falhou ($($_.Exception.Message))" }
    if ($a.esperaSeg) { Start-Sleep $a.esperaSeg }
}
if ((Test-Path $log) -and (Get-Item $log).Length -gt 100KB) { Get-Content $log -Tail 300 | Set-Content $log -Encoding utf8 }
