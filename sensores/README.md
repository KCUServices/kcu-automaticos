# Sensores

De 5 em 5 minutos lê as **temperaturas do CPU e da GPU** (com o [LibreHardwareMonitor](https://github.com/LibreHardwareMonitor/LibreHardwareMonitor)) e a **saúde dos discos** (com o `smartctl` do [smartmontools](https://www.smartmontools.org/)). Escreve tudo em `sensores.json` e avisa no Discord **quando um alerta abre e quando fecha**, nunca a cada volta.

| Alerta | Quando |
|---|---|
| CPU, GPU, hot spot da GPU ou disco muito quentes | passa o limite `alerta` do `limites.json` (perto do limite, `aviso`, só aparece na página de estado) |
| SMART falhado | o disco diz que está a falhar |
| Setores realocados, pendentes, incorrigíveis, erros de media do NVMe | qualquer valor acima de 0 |
| NVMe gasto | `% gasto` igual ou acima de `nvme_gasto_pct` |
| Não consegui ler os sensores | falta o LibreHardwareMonitor ou o smartctl |

O texto dos avisos segue o formato de [`alertas`](../alertas): problema, evidência, impacto, causa provável, solução e quantas vezes abriu nos últimos 7 dias.

## Instalar

1. Descarrega o LibreHardwareMonitor da página oficial de *releases*, na versão **.NET Framework** (o zip `-net472`: o PowerShell 5.1 não carrega a de .NET 8), e copia os `.dll` (o `LibreHardwareMonitorLib.dll` e os que vêm ao lado dele) para `sensores\lhm\`. Depois tira-lhes a marca de "veio da internet", senão o Windows recusa carregá-los:

   ```powershell
   Get-ChildItem sensores\lhm | Unblock-File
   ```

   As versões recentes do LibreHardwareMonitor leem o CPU e a placa-mãe pelo driver **PawnIO**, que se instala à parte (no site oficial do PawnIO). Sem ele, faltam essas temperaturas.
2. Instala o smartmontools (fica em `C:\Program Files\smartmontools\bin\smartctl.exe`; se estiver noutro sítio, muda `smartctl` no `limites.json`).
3. Opcional: copia `limites.exemplo.json` para `limites.json` e muda os limites ou o `equipamento` (o nome que aparece nos avisos).
4. Testa e instala, no **PowerShell como administrador**:

   ```powershell
   powershell -ExecutionPolicy Bypass -File sensores\sensores.ps1 -Ensaio   # mostra o que leu e o que avisaria
   powershell -ExecutionPolicy Bypass -File sensores\instalar.ps1
   ```

   Para desfazer:

   ```powershell
   powershell -ExecutionPolicy Bypass -File sensores\instalar.ps1 -Remover   # tira a tarefa; depois podes apagar sensores.json, sensores.historico.json, hc.url e a pasta lhm
   ```

Os avisos vão para o webhook da variável `KCU_DISCORD_WEBHOOK` (ver o [README principal](../README.md#avisos-no-discord-opcional)).

### Vigia de fora (opcional)

Se o PC morrer de vez, ninguém avisa. Para isso cria um vigia no [Healthchecks](https://healthchecks.io/) (período 5 min) e guarda o endereço de ping num ficheiro `hc.url` ao lado do script. Sem alertas, o script manda o sinal normal; com alertas, manda `/fail` com o texto deles. Se o sinal deixar de chegar, é o Healthchecks que te avisa. O `hc.url` nunca vai para o Git.

## Cuidados

- Corre como administrador (o LibreHardwareMonitor precisa disso para o CPU). Guarda a pasta onde só tu escreves: um `.dll` trocado em `lhm\` corria com os teus direitos.
- Os limites do exemplo são altos de propósito: só avisam quando é mesmo um problema. Cada CPU e GPU tem o seu limite; vê o do teu modelo.
- Não instala nem muda nada no PC: só lê.
