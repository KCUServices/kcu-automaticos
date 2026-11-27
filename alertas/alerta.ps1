# Alertas completos em PowerShell: o mesmo catalogo (catalogo.json) e o mesmo formato do alerta.py.
# Cada alerta leva equipamento, servico, hora, problema, evidencia, impacto, historico, causa provavel,
# solucao sugerida e estado; niveis CRITICAL, HIGH, MEDIUM e LOW.
# Usar com:  . (Join-Path $PSScriptRoot '..\alertas\alerta.ps1')
#   $a = New-KcuAlerta -Chave 'disco:C' -Evidencia 'disco C: com 4 % livre' -Equipamento 'Este PC' -Nivel WARNING
#   Enviar-Discord (Format-KcuAlertaDiscord $a)
# So formata e conta o historico; nao avisar duas vezes o mesmo (novo / resolvido / ja avisado) fica com quem avisa.
# Este ficheiro so tem ASCII (o PowerShell 5.1 le mal os acentos): as letras acentuadas vem de [char] e do catalogo.
$script:KcuAlertaCatalogoF = Join-Path $PSScriptRoot 'catalogo.json'
$script:KcuAlertaCat = $null
$script:KcuNiveis = 'CRITICAL', 'HIGH', 'MEDIUM', 'LOW'
$script:KcuDoEmissor = @{ CRITICAL = 'CRITICAL'; WARNING = 'MEDIUM'; INFO = 'LOW'; HIGH = 'HIGH'; MEDIUM = 'MEDIUM'; LOW = 'LOW' }
$script:KcuIcone = @{ CRITICAL = [char]::ConvertFromUtf32(0x1F534); HIGH = [char]::ConvertFromUtf32(0x1F7E0)
                      MEDIUM = [char]::ConvertFromUtf32(0x1F7E1); LOW = [char]::ConvertFromUtf32(0x1F535) }
$script:KcuDias = 7
$script:KcuEvidenciaMax = 350
$script:KcuMaxMensagens = 4  # alertas a mais vao em varias mensagens; acima disto ficam contados na ultima
# palavras com acento, iguais as do alerta.py
$script:KcuP = @{
  ponto = [string][char]0xB7; ret = [string][char]0x2026; ok = [char]::ConvertFromUtf32(0x2705)
  ev = "Evid$([char]0xEA)ncia"; hist = "Hist$([char]0xF3)rico"; causa = "Causa prov$([char]0xE1)vel"; sol = "Solu$([char]0xE7)$([char]0xE3)o"
  ultimos = "$([char]0xFA)ltimos"; vez = ".$([char]0xAA) vez"; cont = "continua$([char]0xE7)$([char]0xE3)o"; esp = "espa$([char]0xE7)o"
  servico = "servi$([char]0xE7)o"
}

function Get-KcuCatalogo {
  if ($null -eq $script:KcuAlertaCat) {
    try {
      $c = [IO.File]::ReadAllText($script:KcuAlertaCatalogoF, [Text.Encoding]::UTF8) | ConvertFrom-Json
      if (-not $c.tipos) { throw 'sem lista de tipos' }
      $script:KcuAlertaCat = $c
    } catch { $script:KcuAlertaCat = [pscustomobject]@{ generico = $null; tipos = @() } }  # sem catalogo o alerta sai na mesma
  }
  $script:KcuAlertaCat
}

function Get-KcuTipoAlerta([string]$Chave) {
  # junta os tipos que casam com a chave, do menos para o mais especifico (no empate, o que vem depois no ficheiro)
  $t = [ordered]@{ servico = 'Geral'; titulo = 'Problema detetado'; impacto = "Pode afetar o $($script:KcuP.servico) indicado."
                   causa = "Sem cat$([char]0xE1)logo de alertas."; solucao = "Ler a $($script:KcuP.ev.ToLower()) e o registo de quem avisou."
                   nivel = $null; equipamento = $null; casou = $false }
  $cat = Get-KcuCatalogo
  if ($cat.generico) { foreach ($p in $cat.generico.PSObject.Properties) { $t[$p.Name] = $p.Value } }
  $i = 0
  $casam = @(foreach ($e in @($cat.tipos)) { $i++; if ($e.chave -and $Chave -like $e.chave) { [pscustomobject]@{ peso = ($e.chave -replace '\*', '').Length; ordem = $i; e = $e } } })
  foreach ($c in @($casam | Sort-Object peso, ordem)) {
    foreach ($p in $c.e.PSObject.Properties) { if ($null -ne $p.Value -and '' -ne $p.Value) { $t[$p.Name] = $p.Value } }
    $t.casou = $true
  }
  $t
}

function Get-KcuNivel($Tipo, [string]$Emissor) {
  $n = $Tipo.nivel
  if ($n -is [pscustomobject]) { $n = if ($Emissor) { $n.$Emissor } else { $null } }
  if ($script:KcuNiveis -contains $n) { return [string]$n }
  if ($Emissor -and $script:KcuDoEmissor.ContainsKey($Emissor)) { return $script:KcuDoEmissor[$Emissor] }
  'MEDIUM'
}

function New-KcuAlerta {
  param([string]$Chave, [string]$Evidencia, [string]$Equipamento, [string]$Nivel, [int]$Historico = 0, [string]$Estado = 'novo',
        [string]$Servico, [switch]$Resolvido, $Quando = [DateTimeOffset]::Now)
  # a chave nunca vai para o texto (pode ter nomes de maquinas ou enderecos)
  $t = Get-KcuTipoAlerta $Chave
  $ev = (($Evidencia -split '\s+') | Where-Object { $_ }) -join ' '
  [ordered]@{ chave = $Chave; nivel = (Get-KcuNivel $t $Nivel); equipamento = $(if ($t.equipamento) { $t.equipamento } else { $Equipamento })
              servico = $(if ($Servico) { $Servico } else { $t.servico }); hora = [DateTimeOffset]$Quando; problema = $t.titulo
              evidencia = $(if ($ev) { $ev } else { "(sem $($script:KcuP.ev.ToLower()))" }); impacto = $t.impacto; historico = $Historico
              causa = $t.causa; solucao = $t.solucao; estado = $Estado; resolvido = [bool]$Resolvido }
}

function Limit-KcuTexto([string]$Texto, [int]$Limite) {
  if ($Texto.Length -le $Limite) { return $Texto }
  $Texto.Substring(0, [Math]::Max(0, $Limite - 1)).TrimEnd() + $script:KcuP.ret
}

function Format-KcuHistorico([int]$N) {
  if ($N -gt 0) { "$N$($script:KcuP.vez) nos $($script:KcuP.ultimos) $script:KcuDias dias" } else { "sem aberturas registadas nos $($script:KcuP.ultimos) $script:KcuDias dias" }
}
function Format-KcuHora($A) { $A.hora.ToLocalTime().ToString('dd/MM HH:mm', [Globalization.CultureInfo]::InvariantCulture) }

function Format-KcuAlertaDiscord($A) {
  # 1.a linha comeca por "- " (um alerta por item da lista), as outras por dois espacos
  $P = $script:KcuP; $ev = Limit-KcuTexto $A.evidencia $script:KcuEvidenciaMax
  if ($A.resolvido) {
    return (@("- $($P.ok) **RESOLVIDO $($P.ponto) $($A.equipamento)** $($P.ponto) $($A.servico) $($P.ponto) $(Format-KcuHora $A)", "  Problema: $($A.problema)",
              "  $($P.ev): $ev", "  $($P.hist): $(Format-KcuHistorico $A.historico)", "  Estado: $($A.estado)") -join "`n")
  }
  @("- $($script:KcuIcone[$A.nivel]) **$($A.nivel) $($P.ponto) $($A.equipamento)** $($P.ponto) $($A.servico) $($P.ponto) $(Format-KcuHora $A)",
    "  Problema: $($A.problema)", "  $($P.ev): $ev", "  Impacto: $($A.impacto)", "  $($P.causa): $($A.causa)",
    "  $($P.sol): $($A.solucao)", "  $($P.hist): $(Format-KcuHistorico $A.historico)", "  Estado: $($A.estado)") -join "`n"
}

function Format-KcuAlertaTexto($A) {
  # texto simples (Healthchecks e e-mail), com a evidencia inteira
  $P = $script:KcuP; $cabeca = if ($A.resolvido) { 'RESOLVIDO' } else { $A.nivel }
  @("$cabeca $($P.ponto) $($A.equipamento) $($P.ponto) $($A.servico) $($P.ponto) $(Format-KcuHora $A)", "Problema: $($A.problema)", "$($P.ev): $($A.evidencia)",
    "Impacto: $($A.impacto)", "$($P.causa): $($A.causa)", "$($P.sol): $($A.solucao)",
    "$($P.hist): $(Format-KcuHistorico $A.historico)", "Estado: $($A.estado)") -join "`n"
}

function Split-KcuAlertas([string]$Cabecalho, [string[]]$Blocos, [int]$Limite = 1900, [int]$Maximo = $script:KcuMaxMensagens) {
  # mensagens de ate $Limite carateres sem partir um alerta ao meio; o que nao cabe vai na seguinte (ate $Maximo)
  $nota = "`n(+{0} alerta(s) sem $($script:KcuP.esp): ver o registo)"
  $seguinte = "$Cabecalho ($($script:KcuP.cont))"
  $caber = $Limite - ($nota.Length - 1) - 4  # as mesmas contas do alerta.py ({0} conta 3 em vez de {})
  $msgs = New-Object Collections.Generic.List[string]; $msgs.Add($Cabecalho)
  $Blocos = @($Blocos)
  for ($i = 0; $i -lt $Blocos.Count; $i++) {
    $b = Limit-KcuTexto $Blocos[$i] ($caber - $seguinte.Length - 1)
    if ($msgs[$msgs.Count - 1].Length + 1 + $b.Length -gt $caber) {
      if ($msgs.Count -ge $Maximo) { $msgs[$msgs.Count - 1] += $nota -f ($Blocos.Count - $i); break }
      $msgs.Add($seguinte)
    }
    $msgs[$msgs.Count - 1] += "`n" + $b
  }
  $msgs.ToArray()  # quem chama embrulha em @(): uma so mensagem continua a ser uma lista
}

function ConvertTo-KcuInstante($X) {
  if ($X -is [datetime]) { return [DateTimeOffset]$X }  # o PowerShell 7 ja converte as datas do JSON
  try { [DateTimeOffset]::Parse([string]$X, [Globalization.CultureInfo]::InvariantCulture) } catch { $null }
}

function Read-KcuHistorico([string]$Caminho) {
  # { historico: {chave: [instantes]}, abertos: {chave: desde} }; ficheiro em falta ou estragado = vazio
  $h = @{ historico = @{}; abertos = @{} }
  try {
    $j = [IO.File]::ReadAllText($Caminho, [Text.Encoding]::UTF8) | ConvertFrom-Json
    foreach ($p in @($j.historico.PSObject.Properties)) { $h.historico[$p.Name] = [Collections.ArrayList]@(@($p.Value) | ForEach-Object { (ConvertTo-KcuInstante $_) } | Where-Object { $_ } | ForEach-Object { $_.ToUniversalTime().ToString('o') }) }
    foreach ($p in @($j.abertos.PSObject.Properties)) { $d = ConvertTo-KcuInstante $p.Value; if ($d) { $h.abertos[$p.Name] = $d.ToUniversalTime().ToString('o') } }
  } catch { }
  $h
}

function Get-KcuContagem($H, [string]$Chave, $Agora = [DateTimeOffset]::UtcNow) {
  $limite = ([DateTimeOffset]$Agora).AddDays(-$script:KcuDias)
  @(@($H.historico[$Chave]) | Where-Object { $d = ConvertTo-KcuInstante $_; $d -and $d -ge $limite }).Count
}

function Add-KcuHistorico($H, [string]$Chave, $Ocorreu, $Agora = [DateTimeOffset]::UtcNow) {
  # a mesma hora nao conta duas vezes (um aviso que falhou e se repete nao soma); o que tem mais de 7 dias sai
  $limite = ([DateTimeOffset]$Agora).AddDays(-$script:KcuDias)
  foreach ($k in @($H.historico.Keys)) {
    $H.historico[$k] = [Collections.ArrayList]@(@($H.historico[$k]) | Where-Object { $d = ConvertTo-KcuInstante $_; $d -and $d -ge $limite })
    if (-not $H.historico[$k].Count) { $H.historico.Remove($k) }
  }
  $iso = ([DateTimeOffset]$Ocorreu).ToUniversalTime().ToString('o')
  if (-not $H.historico.ContainsKey($Chave)) { $H.historico[$Chave] = New-Object Collections.ArrayList }
  if ($H.historico[$Chave] -notcontains $iso) { [void]$H.historico[$Chave].Add($iso) }
  Get-KcuContagem $H $Chave $Agora
}

function Save-KcuHistorico([string]$Caminho, $H) {
  $tmp = "$Caminho.tmp"
  [IO.File]::WriteAllText($tmp, ($H | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
  Move-Item $tmp $Caminho -Force
}
