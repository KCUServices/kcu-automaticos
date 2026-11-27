# Alertas

Um formato único para os avisos, em **Python** (`alerta.py`) e em **PowerShell** (`alerta.ps1`), com um catálogo partilhado (`catalogo.json`). Em vez de "o disco está quente", cada aviso diz o que se passa, porque importa e o que fazer.

Cada alerta tem 10 campos: **equipamento, serviço, hora, problema, evidência, impacto, histórico, causa provável, solução sugerida e estado**, e um de 4 níveis:

| Nível | Quer dizer |
|---|---|
| 🔴 `CRITICAL` | Perdes dados ou o serviço já parou: trata disto agora. |
| 🟠 `HIGH` | Vai correr mal em breve se ninguém fizer nada. |
| 🟡 `MEDIUM` | Vale a pena ver hoje. |
| 🔵 `LOW` | Só para saberes (por exemplo, algo voltou ao normal). |

## Exemplo de mensagem

Com dados de exemplo, um disco quente chega ao Discord assim:

```text
- 🟡 **MEDIUM · Este PC** · Disco · 15/01 12:00
  Problema: Disco quente
  Evidência: Disco Exemplo 1TB muito quente: 57 C (limite 55 C)
  Impacto: Disco quente envelhece mais depressa e pode abrandar.
  Causa provável: Pouca entrada de ar na caixa, disco encostado à GPU ou NVMe sem dissipador.
  Solução: Melhorar o ar à volta do disco; pôr um dissipador no NVMe.
  Histórico: 2.ª vez nos últimos 7 dias
  Estado: novo
```

E quando passa:

```text
- ✅ **RESOLVIDO · Este PC** · Disco · 15/01 12:35
  Problema: Disco quente
  Evidência: voltou ao normal
  Histórico: 2.ª vez nos últimos 7 dias
  Estado: resolvido
```

## O catálogo

O `catalogo.json` liga a **chave** do alerta (por exemplo `hw-disco-quente:Disco Exemplo 1TB`) a um tipo, por padrão (`*` = qualquer texto). Se casam vários, ganha o mais específico, e herda o que lhe faltar do mais geral: `servico:*:esgotado` só muda o título, a causa e a solução, e fica com o impacto de `servico:*`. Uma chave sem tipo sai na mesma, com o texto genérico. A chave nunca aparece na mensagem.

Tipos que já lá estão: disco quase cheio, memória baixa, tarefa agendada falhou, dados sem atualizar, atualizações críticas, máquina sem sinal (e voltou), serviço em baixo (a recuperar, tentativas esgotadas, voltou), PC desligado de repente ou parado, internet em baixo, temperaturas do CPU e da GPU, SMART e desgaste dos discos. Acrescenta os teus no fim, com os mesmos campos.

## Usar

```python
import sys; sys.path.append(r"..\alertas")
from alerta import montar, discord, partir
a = montar("disco:C", "disco C: com 4 % livre", "Este PC", nivel_emissor="WARNING", historico=1)
for msg in partir("Manutenção", [discord(a)]):
    print(msg)   # ou envia para o webhook
```

```powershell
. (Join-Path $PSScriptRoot '..\comum\discord.ps1')
. (Join-Path $PSScriptRoot '..\alertas\alerta.ps1')
$a = New-KcuAlerta -Chave 'disco:C' -Evidencia 'disco C: com 4 % livre' -Equipamento 'Este PC' -Nivel WARNING -Historico 1
foreach ($m in @(Split-KcuAlertas 'Manutencao' @(Format-KcuAlertaDiscord $a))) { Enviar-Discord $m | Out-Null }
```

- `nivel_emissor` / `-Nivel`: o nível de quem avisa (`CRITICAL`, `WARNING`, `INFO`); o catálogo pode traduzi-lo para outro.
- `partir` / `Split-KcuAlertas`: junta vários alertas em mensagens de até 1900 carateres, sem partir nenhum ao meio.
- `registar` / `Add-KcuHistorico` e `contar` / `Get-KcuContagem`: o histórico de 7 dias ("2.ª vez nos últimos 7 dias").
- **Não avisar duas vezes o mesmo** fica com quem avisa: guarda os alertas abertos e só manda quando um abre ou fecha. O [`sensores`](../sensores) faz assim.

Autoteste (catálogo sem tipos repetidos, formato, mensagens partidas e histórico):

```powershell
python alertas\alerta.py --teste
```
