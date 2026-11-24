# Corre UMA vez como ADMINISTRADOR. Cria a tarefa "\KCU\Limpar RAM" (de 30 em 30 min, escondida).
#   powershell -ExecutionPolicy Bypass -File instalar.ps1            instala
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -Remover   remove
# Testar sem mudar nada:  powershell -File limpar_ram.ps1 -Ensaio
param([switch]$Remover)
. (Join-Path $PSScriptRoot '..\comum\tarefa.ps1')
if (-not (Test-Admin)) { 'Corre isto como administrador.'; exit 1 }
if ($Remover) { Remover-Tarefa 'Limpar RAM'; exit 0 }
$g = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) -RepetitionInterval (New-TimeSpan -Minutes 30)
Registar-Tarefa -Nome 'Limpar RAM' -Script (Join-Path $PSScriptRoot 'limpar_ram.ps1') -Gatilho $g -LimiteMin 5 `
    -Descricao 'Esvazia a lista em espera da RAM quando a memoria livre fica abaixo de 1 GB.'
