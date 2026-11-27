# Página de estado

Um "centro de operações" pequeno, **só neste PC** (`http://127.0.0.1:8765`): anel com a percentagem do que está bem, contagem por estado, cartões dos serviços e o mapa das máquinas. Python 3.8 ou mais recente, sem instalar mais nada. Atualiza-se de 30 em 30 segundos.

Copia `verificacoes.exemplo.json` para `verificacoes.json` e põe lá:

- `verificacoes`: os teus serviços, cada um com `url` (responde por HTTP?) ou `porta` (e `host`, se não for este PC). Com `"vigia": "nome"` liga-se ao serviço com esse nome no `servicos.json` do [`vigia-servicos`](../vigia-servicos), para a página saber se ele está a ser recuperado;
- `maquinas`: o `estado.json` do [`estado-maquinas`](../estado-maquinas);
- `vigia`: o `vigia_servicos.estado.json` do vigia-servicos;
- `sensores`: o `sensores.json` da pasta [`sensores`](../sensores) (junta-se à máquina com o mesmo `equipamento`).

Só a lista de verificações é obrigatória: o resto, se faltar, simplesmente não aparece.

## Os 7 estados

Cada serviço e cada máquina recebe um estado. Se houver vários problemas, ganha o pior (por esta ordem) e o motivo dele aparece no cartão. As regras estão em [`estados.py`](estados.py), com um autoteste: `python estados.py --teste`.

| Estado | Na página | Quando |
|---|---|---|
| `OFFLINE` | Desligado | A máquina não responde (ping ou porta). |
| `FAILED` | Falhou | Serviço em baixo sem recuperação automática (não está no vigia, ou o vigia parou), ou o vigia já esgotou as tentativas de 24 h. Máquina com um disco de SMART falhado. |
| `DEGRADED` | Degradado | A máquina responde mas o hardware está em alerta (temperatura ou disco). |
| `RECOVERING` | A recuperar | Serviço em baixo com o vigia a tratar dele (tentativa recente, ou à espera da próxima). |
| `STALE` | Desatualizado | Os dados são mais velhos do que deviam (estado das máquinas > 30 min, atualizações > 14 h, sensores > 15 min). |
| `WARNING` | Aviso | Serviço instável (2 ou mais tentativas de recuperação em 24 h), atualizações críticas por instalar, temperatura perto do limite, sensores por ler (falta o LibreHardwareMonitor ou o `smartctl`). |
| `HEALTHY` | Saudável | Nenhum dos anteriores. |

`/estado.json` devolve o mesmo em JSON (os campos de antes e um campo novo, `estados`).

```powershell
powershell -File estado-pagina\arrancar_pagina.ps1 -Ensaio   # faz as verificações uma vez e mostra os estados
powershell -ExecutionPolicy Bypass -File estado-pagina\instalar.ps1   # como administrador: arranca ao entrar no Windows
powershell -ExecutionPolicy Bypass -File estado-pagina\instalar.ps1 -Remover   # deixa de arrancar ao entrar
```

A página escuta só em `127.0.0.1`: não fica visível na rede. E recusa pedidos com outro nome no `Host` (proteção contra *DNS rebinding*).
