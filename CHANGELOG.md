# O que mudou

Cada versão fica ligada ao episódio em que foi mostrada. As ideias da comunidade levam o nome de quem as deu.

## [Por lançar]: 2026-11-27

- **Medir FPS** (novo): mede um jogo com o PresentMon oficial da Intel durante N segundos, deita fora os primeiros, e dá o FPS médio, o 1 % baixo, os frametimes e quem limita (CPU ou GPU). Grava o CSV e um resumo `ultima-medicao.json`, e volta a analisar capturas antigas com `-Csv`.
- **Sensores** (novo): temperaturas do CPU e da GPU com o LibreHardwareMonitor e saúde dos discos com o `smartctl`, limites num `limites.json`, avisos só quando um alerta abre ou fecha, e sinal de vida opcional para o Healthchecks.
- **Alertas** (novo): o mesmo formato em Python e PowerShell, com catálogo. Cada aviso leva equipamento, serviço, hora, problema, evidência, impacto, histórico de 7 dias, causa provável, solução e estado, com nível `CRITICAL`, `HIGH`, `MEDIUM` ou `LOW`.
- **Página de estado**: visual novo "centro de operações" e 7 estados por serviço e por máquina (Saudável, Aviso, Degradado, A recuperar, Desatualizado, Falhou, Desligado), com as regras em `estados.py` e um autoteste. Lê também o vigia de serviços e os sensores. O `/estado.json` mantém os campos de antes e ganha `estados`. Recusa pedidos com outro nome no `Host` (proteção contra *DNS rebinding*).
- **Vigia de serviços**: no máximo 3 tentativas em 24 h, cada vez mais espaçadas (logo, 30 min, 60 min); depois pede ajuda uma vez no Discord e avisa quando o serviço voltar. Antes reiniciava de 30 em 30 min sem limite.

## [ep00] Primeira versão pública: 2026-11-24

- Limpar RAM, desligar à noite, reinício de reserva, manutenção, vigia de serviços, arranque de programas, libertar a GPU do ComfyUI e acordar por Wake-on-LAN.
- Avisos no Discord através de um webhook guardado numa variável de ambiente.
- Estado das máquinas (ligadas e atualizações pendentes), página de estado local em Python e otimizar o Windows com `-Ensaio` e `-Desfazer`.
