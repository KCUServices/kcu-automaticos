# Medir FPS

Mede quantos FPS um jogo está mesmo a dar, com o [PresentMon](https://github.com/GameTechDev/PresentMon) oficial da Intel (o mesmo motor que muitas ferramentas de benchmark usam por baixo). Serve para comparar antes e depois de uma mudança: um driver, uma definição do jogo, o [`otimizar-windows`](../otimizar-windows).

| Resultado | O que é |
|---|---|
| `fps_medio` | A média de FPS no tempo medido. |
| `fps_1pct_baixo` | A média do 1 % de frames mais lentos. É o que sentes como "engasgos": conta mais do que a média. |
| `frametime_medio_ms` / `frametime_p99_ms` | Quanto tempo demora cada frame, em média e no pior 1 %. |
| `pior_frame_ms` | O frame mais lento de todos. |
| `cpu_ms_por_frame` / `gpu_ms_por_frame` | Quanto tempo o CPU e a GPU passaram ocupados em cada frame. |
| `quem_limita` | `CPU`, `GPU` ou `equilibrado`: quem está a travar os FPS. Diz-te o que vale a pena melhorar. |

Cada medição grava o CSV completo e um resumo `ultima-medicao.json` em `capturas\`, ao lado do script.

## Instalar

1. Descarrega o PresentMon da página oficial de *releases* do [GameTechDev/PresentMon](https://github.com/GameTechDev/PresentMon/releases): o ficheiro de consola `PresentMon-<versão>-x64.exe` (não o instalador com a interface gráfica).
2. Põe o `.exe` na pasta `medir-fps\`, ao lado do `medir_fps.ps1`. O script usa o `PresentMon*.exe` mais recente que lá encontrar (ou indica outro com `-PresentMon <caminho>`).
3. Tira-lhe a marca de "veio da internet":

   ```powershell
   Unblock-File medir-fps\PresentMon-*.exe
   ```

## Usar

Abre o **PowerShell como administrador** (o PresentMon precisa disso para ver os jogos), abre o jogo e entra numa partida ou mapa.

```powershell
powershell -ExecutionPolicy Bypass -File medir-fps\medir_fps.ps1                                   # lista quem está a desenhar no ecrã, para saberes o nome do .exe
powershell -ExecutionPolicy Bypass -File medir-fps\medir_fps.ps1 -Jogo jogo.exe -Segundos 60        # mede 60 s
powershell -ExecutionPolicy Bypass -File medir-fps\medir_fps.ps1 -Csv medir-fps\capturas\<ficheiro>.csv   # volta a analisar uma captura
```

Depois de carregares Enter, **volta logo ao jogo**: só conta enquanto ele está em primeiro plano. Os primeiros 5 segundos são deitados fora (`-Ignorar`), porque a troca de janela dá engasgos que não são do jogo.

| Opção | O que faz |
|---|---|
| `-Jogo` | O nome do processo, por exemplo `jogo.exe`. Sem isto, mostra a lista. |
| `-Segundos` | Quanto tempo mede (por defeito 60). |
| `-Ignorar` | Segundos iniciais a deitar fora (por defeito 5). |
| `-Pasta` | Onde ficam as capturas (por defeito `capturas\` ao lado do script). |
| `-PresentMon` | O caminho do `.exe`, se não estiver ao lado do script. |
| `-Csv` | Analisa um CSV que já existe, sem medir de novo. |

## Dicas para comparar bem

- Mede sempre **no mesmo sítio do jogo**, a fazer a mesma coisa, e durante o mesmo tempo.
- Faz 2 ou 3 medições de cada lado e compara as médias: uma só pode enganar.
- Olha primeiro para o `fps_1pct_baixo`. Uma mudança que sobe a média mas desce o 1 % baixo deixa o jogo pior de jogar.

## Cuidados

- Corre como administrador. Guarda a pasta onde só tu escreves: um `.exe` trocado ao lado do script corria com os teus direitos.
- Só lê: não muda nada no jogo nem no Windows. Os CSV podem ficar grandes (vários MB por minuto); apaga os antigos de vez em quando.
- Alguns jogos com anti-batota não gostam de ferramentas a olhar para eles. O PresentMon só lê os eventos do Windows, mas em caso de dúvida vê as regras do jogo.
