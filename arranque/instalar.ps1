# Corre UMA vez (como administrador). Cria a tarefa "\KCU\Arranque": corre o arranque.ps1 1 minuto depois de
# entrares no Windows, DENTRO da tua sessao (as apps abrem com janela, como se as abrisses tu).
# Antes: copia arranque.exemplo.json para arranque.json e poe la os teus programas.
#   powershell -ExecutionPolicy Bypass -File instalar.ps1
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -Remover
param([switch]$Remover)
. (Join-Path $PSScriptRoot '..\comum\tarefa.ps1')
if (-not (Test-Admin)) { 'Corre isto como administrador.'; exit 1 }
if ($Remover) { Remover-Tarefa 'Arranque'; exit 0 }
if (-not (Test-Path (Join-Path $PSScriptRoot 'arranque.json'))) { 'Falta arranque.json: copia arranque.exemplo.json e edita-o.'; exit 1 }
$g = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$g.Delay = 'PT1M'
Registar-Tarefa -Nome 'Arranque' -Script (Join-Path $PSScriptRoot 'arranque.ps1') -Gatilho $g -LimiteMin 15 `
    -Descricao 'Abre os programas da lista ao entrar no Windows, se ainda nao estiverem abertos.'
