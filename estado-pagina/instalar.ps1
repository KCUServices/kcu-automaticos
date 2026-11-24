# Corre UMA vez como ADMINISTRADOR. Cria a tarefa "\KCU\Pagina de estado": arranca a pagina 1 minuto depois de
# entrares no Windows e deixa-a a correr (escondida) ate desligares o PC.
# Antes: copia verificacoes.exemplo.json para verificacoes.json e poe la os teus servicos.
#   powershell -ExecutionPolicy Bypass -File instalar.ps1            instala
#   powershell -ExecutionPolicy Bypass -File instalar.ps1 -Remover   remove
# Testar sem abrir nada:  powershell -File arrancar_pagina.ps1 -Ensaio
param([switch]$Remover)
. (Join-Path $PSScriptRoot '..\comum\tarefa.ps1')
if (-not (Test-Admin)) { 'Corre isto como administrador.'; exit 1 }
if ($Remover) { Remover-Tarefa 'Pagina de estado'; exit 0 }
if (-not (Test-Path (Join-Path $PSScriptRoot 'verificacoes.json'))) { 'Falta verificacoes.json: copia verificacoes.exemplo.json e edita-o.'; exit 1 }
$g = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$g.Delay = 'PT1M'
# LimiteMin 0 = sem limite de tempo (a pagina fica sempre a correr)
Registar-Tarefa -Nome 'Pagina de estado' -Script (Join-Path $PSScriptRoot 'arrancar_pagina.ps1') -Gatilho $g -LimiteMin 0 `
    -Descricao 'Pagina de estado em http://127.0.0.1:8765 (so neste PC).'
