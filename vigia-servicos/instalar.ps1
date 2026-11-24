# Corre UMA vez como ADMINISTRADOR. Cria a tarefa "\KCU\Vigia servicos" (de 5 em 5 min, escondida).
# Antes: copia servicos.exemplo.json para servicos.json e poe la os teus servicos.
#   powershell -ExecutionPolicy Bypass -File instalar.ps1
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -Remover
param([switch]$Remover)
. (Join-Path $PSScriptRoot '..\comum\tarefa.ps1')
if (-not (Test-Admin)) { 'Corre isto como administrador.'; exit 1 }
if ($Remover) { Remover-Tarefa 'Vigia servicos'; exit 0 }
if (-not (Test-Path (Join-Path $PSScriptRoot 'servicos.json'))) { 'Falta servicos.json: copia servicos.exemplo.json e edita-o.'; exit 1 }
$g = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(2)) -RepetitionInterval (New-TimeSpan -Minutes 5)
Registar-Tarefa -Nome 'Vigia servicos' -Script (Join-Path $PSScriptRoot 'vigia_servicos.ps1') -Gatilho $g -LimiteMin 4 `
    -Descricao 'Reinicia sozinho os servicos que deixam de responder.'
