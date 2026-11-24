# KCU Automáticos ⚙️

**Os scripts que mantêm os nossos PCs Windows a funcionar sozinhos.** Limpam a RAM quando faz falta, desligam o PC de madrugada sem cortar o trabalho a ninguém, fazem manutenção, voltam a arrancar serviços que caem e avisam no Discord quando algo corre mal.

> São os mesmos scripts que usamos todos os dias, só que limpos de tudo o que é nosso. Pega, lê, adapta ao teu.
>
> *Windows automation scripts we run every day: smart RAM cleaner, safe nightly shutdown, maintenance, self-healing service watchdog, GPU release for ComfyUI, Wake-on-LAN. (In Portuguese.)*

## Como funciona

```mermaid
flowchart LR
    agenda["🗓️ Agendador de Tarefas<br/>pasta \KCU\"] --> vbs["👻 iniciar_oculto.vbs<br/>corre sem janela"]
    vbs --> ram["🧹 Limpar RAM<br/>30 em 30 min"]
    vbs --> noite["🌙 Desligar noite<br/>01:00"]
    vbs --> manut["🧽 Manutenção<br/>diária e semanal"]
    vbs --> vigia["👀 Vigia de serviços<br/>5 em 5 min"]
    vbs --> arr["🚀 Arranque<br/>ao entrar no Windows"]
    vigia --> gpu["🎮 Libertar GPU<br/>ComfyUI parado"]
    vigia -- "caiu?" --> rearr["🔁 Volta a arrancar"]
    noite -- "ocupado?" --> espera["⏳ Volta a ver<br/>daqui a 15 min"]
    noite & manut & vigia -. "só quando importa" .-> discord["💬 Discord"]
```

## O que está aqui

| Pasta | O que faz | Quando |
|---|---|---|
| [`limpar-ram`](limpar-ram) | Esvazia a "lista em espera" da RAM **só** quando há menos de 1 GB livre. Não mexe na memória dos programas. | de 30 em 30 min |
| [`desligar-noite`](desligar-noite) | Desliga o PC de madrugada, **exceto** se alguém o estiver a usar, se a GPU ou a CPU estiverem ocupadas, se o Claude Code estiver a trabalhar ou se um programa da tua lista estiver aberto. Volta a tentar de 15 em 15 min. | 01:00 |
| [`reinicio-reserva`](reinicio-reserva) | Reinicia o PC se ficou ligado e está parado há 30 min. | 05:00 |
| [`manutencao`](manutencao) | Limpa temporários, relatórios de erro, a cache de atualizações e o Docker. Vigia a saúde dos discos e o espaço livre. | diária às 13:30, semanal ao domingo às 14:00 |
| [`vigia-servicos`](vigia-servicos) | Vê se os teus serviços respondem. Se um falha duas vezes seguidas, volta a arrancá-lo. Avisa se o PC se desligou de repente (falta de luz). | de 5 em 5 min |
| [`libertar-gpu`](libertar-gpu) | Quando o ComfyUI está parado com modelos na placa, descarrega-os para os jogos terem a GPU toda. | com o vigia |
| [`arranque`](arranque) | Ao entrares no Windows, abre os programas e serviços da tua lista, **só** se ainda não estiverem abertos. Vê pela porta ou pelo processo. | ao entrar |
| [`acordar-wol`](acordar-wol) | Liga outro PC da casa por Wake-on-LAN e espera que ele responda. | à mão |
| [`comum`](comum) | Peças partilhadas: correr escondido, criar tarefas, avisar no Discord. | — |

## Instalar

1. Descarrega o repositório para uma pasta fixa, por exemplo `C:\kcu-automaticos`.
2. Abre o **PowerShell como administrador** e corre o `instalar.ps1` de cada pasta que queres:

   ```powershell
   cd C:\kcu-automaticos
   powershell -ExecutionPolicy Bypass -File limpar-ram\instalar.ps1
   powershell -ExecutionPolicy Bypass -File desligar-noite\instalar.ps1 -Hora 01:00
   powershell -ExecutionPolicy Bypass -File manutencao\instalar.ps1
   ```

3. **Testa primeiro em modo ensaio.** Mostra o que faria, sem apagar nem desligar nada:

   ```powershell
   powershell -File limpar-ram\limpar_ram.ps1 -Ensaio
   powershell -File desligar-noite\desligar_noite.ps1 -Ensaio
   powershell -File manutencao\manutencao.ps1 -Semanal -Ensaio
   ```

4. Para desinstalar, corre o mesmo `instalar.ps1` com `-Remover`.

### Avisos no Discord (opcional)

Cria um webhook no teu canal (Definições do canal → Integrações → Webhooks) e guarda-o **numa variável de ambiente**, nunca no código:

```powershell
[Environment]::SetEnvironmentVariable('KCU_DISCORD_WEBHOOK', 'https://discord.com/api/webhooks/...', 'User')
```

### Ligar o PC sozinho de manhã

O desligar noturno só faz sentido se o PC voltar a ligar sozinho. Na BIOS, procura **"RTC Alarm"**, **"Power On By RTC"** ou **"Resume by Alarm"** e põe a hora (por exemplo, 09:00). O nome muda de marca para marca.

### Vigia de serviços

Copia `servicos.exemplo.json` para `servicos.json` e põe lá os teus serviços. Cada um precisa de:
- uma forma de ver se está vivo: `url` (responde?) ou `processo` (está aberto?);
- uma forma de o voltar a arrancar: `tarefa` (uma tarefa agendada) ou `programa` (um .exe);
- opcionalmente, `matar`: um texto do comando dos processos a fechar antes de arrancar de novo.

## Cuidados

- **Lê antes de correr.** São scripts com permissões de administrador. Estão comentados linha a linha para os poderes entender.
- **O limpar RAM não acelera um PC com pouca RAM.** Só evita os engasgos quando a cache do Windows ocupa a memória toda. Se o teu PC está sempre no limite, a solução é mais RAM.
- **Os scripts só usam ASCII** (sem acentos), porque o PowerShell 5.1 lê mal os ficheiros sem BOM.

## Episódios

| Ep. | Vídeo | Código | O que mudou |
|---|---|---|---|
| 00 | *em breve* | [ep00](../../tree/ep00) | Primeira versão pública |

O que mudou em cada versão está no [CHANGELOG](CHANGELOG.md).

## FAQ

**Funciona no Windows 10?**
Sim, no 10 e no 11. A versão do PowerShell que já vem com o Windows chega.

**O desligar noturno desligou-me o PC a meio de um jogo!**
Não devia: ele não desliga se usaste o rato ou o teclado nos últimos 20 min, nem com a GPU acima de 30 %. Se aconteceu, abre uma *issue* com o `desligar_noite.log`.

**Posso pôr isto num servidor sem ninguém a usar?**
Sim. Nesse caso tira o `desligar-noite` e fica com o vigia, a manutenção e o limpar RAM.

**Tenho uma ideia.**
Vai às [Discussions](https://github.com/orgs/KCUServices/discussions/categories/ideas).

## Mais da KCU Services

O setup completo onde isto corre está no [kcu-stack](https://github.com/KCUServices/kcu-stack). Outros projetos em [github.com/KCUServices](https://github.com/KCUServices).

## Licença

[PolyForm Noncommercial 1.0.0](LICENSE): podes usar, estudar, alterar e partilhar **para uso pessoal e sem fins comerciais**. Vender, revender ou usar isto num negócio precisa de autorização: fala connosco no Instagram [@kcu.services](https://www.instagram.com/kcu.services).
