# Corre UMA vez como ADMINISTRADOR. Cria a tarefa "\KCU\Estado das maquinas" (de 10 em 10 min, escondida).
# Antes: copia maquinas.exemplo.json para maquinas.json e poe la as tuas maquinas.
#   powershell -ExecutionPolicy Bypass -File instalar.ps1            instala
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -Remover   remove
# Testar sem escrever nada:  powershell -File estado_maquinas.ps1 -Ensaio -Completo
param([switch]$Remover)
. (Join-Path $PSScriptRoot '..\comum\tarefa.ps1')
if (-not (Test-Admin)) { 'Corre isto como administrador.'; exit 1 }
if ($Remover) { Remover-Tarefa 'Estado das maquinas'; exit 0 }
if (-not (Test-Path (Join-Path $PSScriptRoot 'maquinas.json'))) { 'Falta maquinas.json: copia maquinas.exemplo.json e edita-o.'; exit 1 }
$g = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes 10)
Registar-Tarefa -Nome 'Estado das maquinas' -Script (Join-Path $PSScriptRoot 'estado_maquinas.ps1') -Gatilho $g -LimiteMin 15 `
    -Descricao 'Ve se as maquinas da lista estao ligadas e (de 6 em 6 h) se tem atualizacoes pendentes.'
