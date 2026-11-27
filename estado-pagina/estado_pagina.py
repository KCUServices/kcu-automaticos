"""Pagina de estado ("Centro de operacoes"): uma pagina web pequena, so neste PC, com o estado dos teus servicos e maquinas.

So usa a biblioteca padrao do Python (3.8 ou mais recente). Le a lista em verificacoes.json
(copia verificacoes.exemplo.json e edita). Cada verificacao e uma de:
  {"nome": "...", "url": "http://127.0.0.1:8080/"}     responde por HTTP (qualquer codigo abaixo de 500)?
  {"nome": "...", "porta": 8188, "host": "127.0.0.1"}  a porta TCP aceita ligacao? (host opcional)
  "vigia": "nome"  (opcional) o nome do servico no servicos.json do vigia-servicos, para saber se esta a recuperar
Ficheiros opcionais, com o caminho no verificacoes.json:
  "maquinas"  o estado.json do estado-maquinas (tabela das maquinas)
  "vigia"     o vigia_servicos.estado.json do vigia-servicos (tentativas de recuperacao)
  "sensores"  o sensores.json da pasta sensores (temperaturas e discos; junta-se a maquina com o mesmo nome)
Cada servico e cada maquina recebe um dos 7 estados de estados.py (HEALTHY, WARNING, DEGRADED, FAILED,
OFFLINE, STALE, RECOVERING).

Escuta SO em 127.0.0.1 (nao fica visivel na rede). Abre http://127.0.0.1:8765 no browser.
  python estado_pagina.py             arranca a pagina
  python estado_pagina.py --ensaio    faz as verificacoes uma vez, mostra-as e sai (nao abre porta nenhuma)
Rotas: /  (pagina, atualiza-se sozinha)   /estado.json  (o mesmo em JSON)
"""
import html
import json
import math
import os
import socket
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PASTA = os.path.dirname(os.path.abspath(__file__))
sys.path.append(PASTA)  # o arrancar_pagina.ps1 corre com "python -I", que tira a pasta do script do caminho
import estados as est  # noqa: E402
CONFIG = os.path.join(PASTA, "verificacoes.json")
EXEMPLO = os.path.join(PASTA, "verificacoes.exemplo.json")
CACHE_SEG = 15  # nao repete as verificacoes mais do que uma vez a cada 15 s


def ler_config():
    caminho = CONFIG if os.path.exists(CONFIG) else EXEMPLO
    with open(caminho, encoding="utf-8") as f:
        cfg = json.load(f)
    cfg.setdefault("titulo", "Estado")
    cfg.setdefault("porta", 8765)
    cfg.setdefault("verificacoes", [])
    return cfg, caminho


def verificar(v):
    inicio = time.monotonic()
    try:
        if v.get("url"):
            try:
                with urllib.request.urlopen(v["url"], timeout=5) as r:
                    ok, detalhe = r.status < 500, "HTTP %d" % r.status
            except urllib.error.HTTPError as e:  # 4xx tambem quer dizer "esta vivo"
                ok, detalhe = e.code < 500, "HTTP %d" % e.code
        elif v.get("porta"):
            with socket.create_connection((v.get("host", "127.0.0.1"), int(v["porta"])), timeout=3):
                ok, detalhe = True, "porta %s aberta" % v["porta"]
        else:
            ok, detalhe = False, "falta url ou porta"
    except Exception as e:  # sem ligacao, tempo esgotado, nome desconhecido...
        ok, detalhe = False, type(e).__name__
    return {"nome": v.get("nome", "?"), "ok": ok, "detalhe": detalhe,
            "ms": int((time.monotonic() - inicio) * 1000)}


def ler_ficheiro(cfg, chave):
    """O JSON do caminho cfg[chave] e a idade do ficheiro em minutos; (None, None) se nao houver."""
    caminho = cfg.get(chave)
    if not caminho:
        return None, None
    if not os.path.isabs(caminho):
        caminho = os.path.join(PASTA, caminho)
    try:
        with open(caminho, encoding="utf-8-sig") as f:
            return json.load(f), int((time.time() - os.path.getmtime(caminho)) // 60)
    except (OSError, ValueError):
        return None, None


def ler_maquinas(cfg):
    return ler_ficheiro(cfg, "maquinas")[0]


def juntar_estados(cfg, verificacoes, maq):
    """Os 7 estados de cada servico e de cada maquina (regras em estados.py)."""
    vigia, vigia_min = ler_ficheiro(cfg, "vigia")
    hw, _ = ler_ficheiro(cfg, "sensores")
    vigia = vigia if isinstance(vigia, dict) else {}
    nomes_v = {v.get("nome"): v.get("vigia") for v in cfg["verificacoes"]}
    serv = []
    for r in verificacoes:
        nv = nomes_v.get(r["nome"])
        serv.append(dict(nome=r["nome"], **est.estado_servico(r["ok"], vigia.get(nv) if nv else None, vigia_min)))
    lista = [m for m in ((maq or {}).get("maquinas") or []) if isinstance(m, dict)]
    gerado_min = est.idade_min((maq or {}).get("gerado")) if maq else None
    hw_nome = hw.get("maquina") if isinstance(hw, dict) else None
    out = [dict(nome=m.get("nome", "?"), **est.estado_maquina(m, gerado_min, hw if m.get("nome") == hw_nome else None))
           for m in lista]
    if hw_nome and hw_nome not in [m.get("nome") for m in lista]:  # so ha sensores: e este PC, que esta a responder
        out.append(dict(nome=hw_nome, **est.estado_maquina({"ligada": True}, 0, hw)))
    return {"servicos": serv, "maquinas": out, "contagem": est.contagem(serv + out), "etiquetas": est.ETIQUETAS}


_cache = {"quando": 0.0, "estado": None}
_trinco = threading.Lock()


def estado():
    with _trinco:
        if _cache["estado"] and time.monotonic() - _cache["quando"] < CACHE_SEG:
            return _cache["estado"]
        cfg, _ = ler_config()
        with ThreadPoolExecutor(max_workers=8) as ex:
            resultados = list(ex.map(verificar, cfg["verificacoes"]))
        maq = ler_maquinas(cfg)
        e = {"titulo": cfg["titulo"], "gerado": datetime.now().isoformat(timespec="seconds"),
             "verificacoes": resultados, "maquinas": maq, "estados": juntar_estados(cfg, resultados, maq)}
        _cache.update(quando=time.monotonic(), estado=e)
        return e


# cor de cada estado: classe da pilula e do ponto (CL) e cor do cartao (DS)
CL = {"HEALTHY": "ok", "WARNING": "atencao", "DEGRADED": "atencao", "RECOVERING": "info", "STALE": "cinza",
      "FAILED": "mal", "OFFLINE": "mal"}
DS = {"HEALTHY": "ok", "WARNING": "mal", "DEGRADED": "mal", "RECOVERING": "info", "STALE": "cinza",
      "FAILED": "erro", "OFFLINE": "erro"}

CSS = """
:root{--fundo:#050a14;--painel:rgba(10,19,36,.82);--painel2:rgba(14,26,48,.7);--linha:rgba(125,170,255,.13);--linha2:rgba(125,170,255,.26);
--texto:#e7eef8;--suave:#b7c4d8;--cinza:#8a9bb5;--ciano:#38d9f5;--verde:#34d399;--ambar:#fbbf24;--vermelho:#fb7185;--azul:#60a5fa;
--sans:"Segoe UI Variable","Segoe UI",system-ui,-apple-system,sans-serif;--mono:"Cascadia Mono",Consolas,ui-monospace,monospace;--r:14px}
*{box-sizing:border-box}
body{margin:0;min-height:100vh;color:var(--texto);font:14px/1.45 var(--sans);background-color:var(--fundo);overflow-x:hidden}
html::before{content:"";position:fixed;inset:0;z-index:-1;pointer-events:none;
background-image:radial-gradient(1200px 700px at 12% -12%,rgba(56,217,245,.11),transparent 60%),
radial-gradient(1000px 640px at 100% -5%,rgba(96,165,250,.10),transparent 58%),radial-gradient(900px 700px at 50% 115%,rgba(52,211,153,.07),transparent 60%)}
body::before{content:"";position:fixed;inset:0;z-index:-1;pointer-events:none;
background-image:linear-gradient(rgba(125,170,255,.055) 1px,transparent 1px),linear-gradient(90deg,rgba(125,170,255,.055) 1px,transparent 1px);
background-size:48px 48px;-webkit-mask-image:radial-gradient(ellipse 90% 70% at 50% 0%,#000 25%,transparent 85%);mask-image:radial-gradient(ellipse 90% 70% at 50% 0%,#000 25%,transparent 85%)}
.so-leitor{position:absolute;width:1px;height:1px;overflow:hidden;clip:rect(0 0 0 0);white-space:nowrap}
.barra{position:sticky;top:0;z-index:20;background:rgba(5,10,20,.94);border-bottom:1px solid var(--linha)}
.barra-in{max-width:1500px;margin:0 auto;display:flex;flex-wrap:wrap;align-items:center;gap:10px 18px;padding:10px 20px}
.marca{display:flex;align-items:center;gap:11px}
.logo{width:36px;height:36px;border-radius:10px;display:grid;place-items:center;font:800 11.5px/1 var(--mono);letter-spacing:.06em;color:#03131a;
background:linear-gradient(135deg,var(--ciano),var(--verde));box-shadow:0 0 0 1px rgba(255,255,255,.12) inset,0 6px 22px rgba(56,217,245,.28)}
.marca-t{display:flex;flex-direction:column;line-height:1.15}
.marca-t strong{font-size:16px;font-weight:650}
.marca-t small{font:600 10.5px/1.3 var(--mono);letter-spacing:.14em;text-transform:uppercase;color:var(--cinza)}
.selo{display:inline-flex;align-items:center;gap:9px;padding:7px 13px 7px 11px;border-radius:999px;font-weight:600;font-size:13px;
border:1px solid var(--linha2);background:rgba(125,170,255,.06);color:var(--suave);--c:var(--cinza)}
body[data-geral=ok] .selo{--c:var(--verde);color:#b9f5dc;border-color:rgba(52,211,153,.4);background:rgba(52,211,153,.09)}
body[data-geral=mal] .selo{--c:var(--ambar);color:#fde4a1;border-color:rgba(251,191,36,.42);background:rgba(251,191,36,.09)}
body[data-geral=off] .selo{--c:var(--vermelho);color:#fecdd3;border-color:rgba(251,113,133,.45);background:rgba(251,113,133,.1)}
.esp{flex:1}
.tele{display:flex;flex-direction:column;align-items:flex-end;line-height:1.15}
.tele-v{font:600 15px/1.2 var(--mono);font-variant-numeric:tabular-nums}
.tele-l{font:600 10px/1.3 var(--mono);letter-spacing:.12em;text-transform:uppercase;color:var(--cinza)}
.ponto{position:relative;width:8px;height:8px;border-radius:50%;background:var(--c,var(--cinza));box-shadow:0 0 10px var(--c,transparent);flex:none}
.selo .ponto::after,.ponto.mal::after{content:"";position:absolute;inset:0;border-radius:50%;border:1.5px solid var(--c);animation:onda 2.4s ease-out infinite}
@keyframes onda{from{transform:scale(1);opacity:.9}to{transform:scale(2.8);opacity:0}}
[data-s=ok]{--c:var(--verde)}[data-s=mal]{--c:var(--ambar)}[data-s=erro]{--c:var(--vermelho)}[data-s=cinza]{--c:var(--cinza)}[data-s=info]{--c:var(--azul)}
.ponto.ok{--c:var(--verde)}.ponto.mal{--c:var(--vermelho)}.ponto.atencao{--c:var(--ambar)}.ponto.info{--c:var(--azul)}.ponto.cinza{--c:#5b6b85;box-shadow:none}
.pagina{max-width:1500px;margin:0 auto;padding:18px 20px 40px}
.grelha{display:grid;grid-template-columns:repeat(12,minmax(0,1fr));gap:14px}
.heroi{grid-column:span 5}.kpis{grid-column:span 7}.p-srv{grid-column:span 12}.p-map{grid-column:span 12}
.painel,.kpi{animation:entra .6s cubic-bezier(.2,.8,.2,1) both;animation-delay:calc(var(--i,0) * 55ms)}
@keyframes entra{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:none}}
.painel{position:relative;background:var(--painel);border:1px solid var(--linha);border-radius:var(--r);min-width:0;
box-shadow:0 1px 0 rgba(255,255,255,.03) inset,0 18px 40px -24px rgba(0,0,0,.6)}
.painel::before,.painel::after{content:"";position:absolute;width:12px;height:12px;pointer-events:none;border:0 solid rgba(56,217,245,.55)}
.painel::before{top:-1px;left:-1px;border-top-width:2px;border-left-width:2px;border-top-left-radius:var(--r)}
.painel::after{bottom:-1px;right:-1px;border-bottom-width:2px;border-right-width:2px;border-bottom-right-radius:var(--r)}
.cab{display:flex;align-items:center;gap:10px;padding:11px 16px;border-bottom:1px solid var(--linha);min-height:42px}
.cab h2{margin:0;font:650 11px/1.2 var(--mono);letter-spacing:.14em;text-transform:uppercase;color:var(--suave)}
.cab .idx{font:600 10.5px/1 var(--mono);color:var(--ciano);padding:3px 6px;border-radius:5px;background:rgba(56,217,245,.09);border:1px solid rgba(56,217,245,.2)}
.meta{margin-left:auto;font-size:12px;color:var(--cinza);text-align:right}
.corpo{padding:14px 16px}
.vazio{color:var(--cinza);font-size:13px;padding:6px 0;margin:0}
.heroi-c{display:grid;grid-template-columns:auto minmax(0,1fr);gap:22px;align-items:center;padding:18px 20px 20px}
.anel{position:relative;width:min(220px,62vw);aspect-ratio:1;flex:none}
.anel svg{width:100%;height:100%;display:block}
.anel .trilho{fill:none;stroke:rgba(125,170,255,.09);stroke-width:12}
.anel .valor{fill:none;stroke:url(#gOk);stroke-width:12;stroke-linecap:round;stroke-dasharray:603.19;animation:enche 1.3s cubic-bezier(.2,.8,.2,1) both;
filter:drop-shadow(0 0 6px rgba(56,217,245,.45))}
@keyframes enche{from{stroke-dashoffset:603.19}}
body[data-geral=mal] .anel .valor,body[data-geral=off] .anel .valor{stroke:url(#gMal);filter:drop-shadow(0 0 6px rgba(251,191,36,.4))}
.anel .tick{stroke:rgba(125,170,255,.22);stroke-width:1}.anel .tick.m{stroke:rgba(56,217,245,.55);stroke-width:1.5}
.anel svg.gira{position:absolute;inset:0;animation:gira 80s linear infinite}
.anel .gira circle{fill:none;stroke:rgba(56,217,245,.3);stroke-width:1;stroke-dasharray:1.5 6}
@keyframes gira{to{transform:rotate(360deg)}}
.anel-c{position:absolute;inset:0;display:grid;place-items:center;text-align:center;pointer-events:none}
.pct{font:600 50px/1 var(--mono);letter-spacing:-.04em;font-variant-numeric:tabular-nums}
.pct small{font-size:20px;color:var(--cinza);margin-left:2px;letter-spacing:0}
.anel-l{font:600 10px/1.3 var(--mono);letter-spacing:.16em;text-transform:uppercase;color:var(--cinza);margin-top:6px}
.anel-b{font-size:11.5px;color:var(--suave);margin-top:3px}
.frase{margin:0 0 6px;font-size:clamp(19px,1.7vw,25px);font-weight:650;letter-spacing:-.01em;line-height:1.2}
.frase2{margin:0;color:var(--cinza);font-size:13px}
.areas{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:6px;margin-top:14px}
.area{display:flex;align-items:center;gap:8px;padding:7px 10px;border-radius:8px;font-size:12.5px;background:rgba(125,170,255,.045);border:1px solid var(--linha);min-width:0}
.area span:nth-child(2){overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.area em{margin-left:auto;font:600 10.5px/1 var(--mono);font-style:normal;letter-spacing:.1em;text-transform:uppercase;color:var(--c)}
.area[data-s=mal],.area[data-s=erro]{border-color:rgba(251,191,36,.35);background:rgba(251,191,36,.07)}
.kpis{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));grid-auto-rows:1fr;gap:14px;min-width:0}
.kpi{position:relative;display:flex;flex-direction:column;gap:4px;padding:13px 14px 12px 16px;border-radius:12px;background:var(--painel);
border:1px solid var(--linha);min-height:118px;min-width:0;overflow:hidden}
.kpi::before{content:"";position:absolute;left:0;top:12px;bottom:12px;width:2px;border-radius:2px;background:var(--c);box-shadow:0 0 12px var(--c)}
.kpi::after{content:"";position:absolute;right:-40px;top:-40px;width:120px;height:120px;border-radius:50%;background:radial-gradient(closest-side,var(--c),transparent);opacity:.07;pointer-events:none}
.kpi.zero{opacity:.55}
.k-cab{display:flex;align-items:center;gap:8px;min-width:0}
.k-tit{font-size:12.5px;font-weight:600;color:var(--suave)}
.k-cab .ponto{margin-left:auto}
.k-num{font:600 32px/1.05 var(--mono);letter-spacing:-.03em;font-variant-numeric:tabular-nums;margin-top:6px}
.k-sub{font:600 10px/1.3 var(--mono);letter-spacing:.12em;text-transform:uppercase;color:var(--cinza);margin-top:auto}
.pil{font:600 10.5px/1.6 var(--mono);letter-spacing:.04em;padding:1px 8px;border-radius:999px;white-space:nowrap;border:1px solid var(--linha2);color:var(--suave)}
.pil.ok{color:var(--verde);border-color:rgba(52,211,153,.35);background:rgba(52,211,153,.07)}
.pil.mal{color:var(--vermelho);border-color:rgba(251,113,133,.4);background:rgba(251,113,133,.08)}
.pil.atencao{color:var(--ambar);border-color:rgba(251,191,36,.4);background:rgba(251,191,36,.08)}
.pil.info{color:var(--azul);border-color:rgba(96,165,250,.4);background:rgba(96,165,250,.08)}
.pil.cinza{color:var(--cinza)}
.pil .cod{font-size:9px;opacity:.55;margin-left:5px;letter-spacing:.08em}
.srv{display:grid;grid-template-columns:repeat(auto-fill,minmax(min(100%,260px),1fr));gap:8px}
.sv{display:flex;align-items:center;gap:10px;padding:10px 12px;border-radius:10px;border:1px solid var(--linha);background:var(--painel2);min-width:0}
.sv .nm{font-size:12.8px;overflow-wrap:anywhere;line-height:1.25;min-width:0}
.sv .nm small{display:block;font-size:11px;color:var(--cinza);margin-top:1px}
.sv .pil{flex:none;margin-left:auto}
.sv[data-s=erro]{border-color:rgba(251,113,133,.45);background:rgba(251,113,133,.07)}
.sv[data-s=mal]{border-color:rgba(251,191,36,.35)}.sv[data-s=info]{border-color:rgba(96,165,250,.35)}
.hub{position:relative;display:flex;align-items:center;gap:10px;width:max-content;max-width:100%;margin:4px auto 30px;padding:6px 14px 6px 6px;border-radius:999px;
border:1px solid rgba(56,217,245,.4);background:rgba(56,217,245,.07);box-shadow:0 0 28px -8px rgba(56,217,245,.55);
font:650 11px/1.2 var(--mono);letter-spacing:.14em;text-transform:uppercase}
.hub .logo{width:28px;height:28px;border-radius:8px;font-size:9.5px}
.hub::after{content:"";position:absolute;left:50%;top:100%;width:1px;height:16px;background:rgba(56,217,245,.55)}
.nos-w{position:relative}
.nos-w::before{content:"";position:absolute;top:-15px;left:12%;right:12%;height:1px;background:linear-gradient(90deg,rgba(56,217,245,.2),rgba(56,217,245,.6),rgba(56,217,245,.2))}
.nos{display:grid;grid-template-columns:repeat(auto-fit,minmax(min(100%,240px),1fr));gap:14px}
.no{position:relative;padding:12px 13px;border-radius:11px;border:1px solid var(--linha);background:var(--painel2);min-width:0}
.no::before{content:"";position:absolute;left:50%;top:-16px;width:1px;height:15px;background:rgba(56,217,245,.45)}
.no[data-s=ok]{border-color:rgba(52,211,153,.24)}.no[data-s=mal]{background:rgba(251,191,36,.045);border-color:rgba(251,191,36,.4)}
.no[data-s=erro]{background:rgba(251,113,133,.045);border-color:rgba(251,113,133,.45)}.no[data-s=info]{border-color:rgba(96,165,250,.35)}
.no-c{display:flex;align-items:center;gap:9px;margin-bottom:8px;min-width:0}
.no-c strong{font-size:13.5px;font-weight:650;overflow-wrap:anywhere;min-width:0}
.no-c .pil{margin-left:auto}
.motivo{font-size:11.5px;color:var(--cinza);margin:0 0 8px;overflow-wrap:anywhere}
.linhas{margin:0;padding:0;list-style:none}
.linhas li{display:flex;align-items:baseline;gap:10px;padding:6px 0;border-top:1px solid rgba(125,170,255,.07);font-size:12.5px}
.linhas li:first-child{border-top:0}
.linhas li span{color:var(--cinza)}
.linhas li b{margin-left:auto;font:600 12px var(--mono);text-align:right;overflow-wrap:anywhere;min-width:0}
.linhas b.mal{color:var(--vermelho)}.linhas b.atencao{color:var(--ambar)}.linhas b.ok{color:var(--verde)}
.rodape{margin-top:22px;text-align:center;font:600 10.5px/1.6 var(--mono);letter-spacing:.12em;text-transform:uppercase;color:#6f819e}
@media (max-width:1180px){.heroi,.kpis{grid-column:span 12}}
@media (max-width:900px){.kpis{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media (max-width:720px){
.barra{position:relative}.barra-in{padding:9px 16px;gap:8px 12px}.esp{display:none}.tele{align-items:flex-start}
.pagina{padding:14px 16px 32px}.grelha,.kpis{gap:10px}
.heroi-c{grid-template-columns:1fr;justify-items:center;text-align:center;padding:16px}.heroi-c>div:last-child{width:100%}.areas{text-align:left}
.kpi{min-height:104px}.k-num{font-size:27px}.cab{padding:10px 14px}.corpo{padding:12px 14px}
.hub{margin:0 0 16px}.hub::after,.nos-w::before,.no::before{display:none}}
@media (max-width:420px){.areas{grid-template-columns:1fr}.pil .cod{display:none}.marca-t small{display:none}}
@media (prefers-reduced-motion:reduce){*,*::before,*::after{animation:none!important;transition:none!important}}
"""


def _ticks():
    s = []
    for i in range(72):
        a, m = math.radians(i * 5), i % 6 == 0
        r1, r2 = (74 if m else 78), 83
        s.append('<line class="tick%s" x1="%.2f" y1="%.2f" x2="%.2f" y2="%.2f"/>'
                 % (" m" if m else "", 120 + r1 * math.cos(a), 120 + r1 * math.sin(a), 120 + r2 * math.cos(a), 120 + r2 * math.sin(a)))
    return "".join(s)


TICKS = _ticks()


def pil(x):
    return '<span class="pil %s">%s<span class="cod">%s</span></span>' % (
        CL[x["estado"]], html.escape(x["etiqueta"]), x["estado"])


def pagina(e):
    esc = html.escape
    es = e["estados"]
    todos = es["servicos"] + es["maquinas"]
    cont = es["contagem"]
    bons = cont["HEALTHY"]
    pct = round(100 * bons / len(todos)) if todos else 100
    mal = [x for x in todos if x["estado"] != "HEALTHY"]
    graves = cont["OFFLINE"] + cont["FAILED"]
    geral = "ok" if not mal else "off" if graves else "mal"
    selo = ("Tudo a funcionar" if not mal else "%d %s atenção" % (len(mal), "precisa de" if len(mal) == 1 else "precisam de"))
    frase = ("Tudo a funcionar." if not mal else "%s: %s." % (esc(mal[0]["nome"]), esc(mal[0]["motivo"] or mal[0]["etiqueta"].lower())))
    areas = "".join('<div class="area" data-s="%s"><span class="ponto %s"></span><span>%s</span><em>%s</em></div>'
                    % (DS[x["estado"]], CL[x["estado"]], esc(x["nome"]), esc(x["etiqueta"]))
                    for x in (mal or todos)[:8])
    kpis = "".join('<div class="kpi%s" data-s="%s" style="--i:%d"><div class="k-cab"><span class="k-tit">%s</span><span class="ponto %s"></span></div>'
                   '<div class="k-num">%d</div><div class="k-sub">%s</div></div>'
                   % ("" if cont[k] else " zero", DS[k], i + 1, esc(est.ETIQUETAS[k]), CL[k], cont[k], k)
                   for i, k in enumerate(("HEALTHY", "WARNING", "RECOVERING", "STALE", "DEGRADED", "FAILED", "OFFLINE")))
    kpis += '<div class="kpi" data-s="cinza" style="--i:8"><div class="k-cab"><span class="k-tit">Total</span></div><div class="k-num">%d</div><div class="k-sub">serviços e máquinas</div></div>' % len(todos)
    ver = {v["nome"]: v for v in e["verificacoes"]}
    cartoes = "".join(
        '<div class="sv" data-s="%s"><span class="ponto %s"></span><span class="nm">%s<small>%s</small></span>%s</div>'
        % (DS[x["estado"]], CL[x["estado"]], esc(x["nome"]),
           esc(x["motivo"] if x["estado"] != "HEALTHY" else "%s · %d ms" % (ver[x["nome"]]["detalhe"], ver[x["nome"]]["ms"])), pil(x))
        for x in sorted(es["servicos"], key=lambda s: est.ORDEM.index(s["estado"])))
    maq_lista = {m.get("nome"): m for m in ((e.get("maquinas") or {}).get("maquinas") or []) if isinstance(m, dict)}
    nos = []
    for x in es["maquinas"]:
        m = maq_lista.get(x["nome"]) or {}
        u = m.get("atualizacoes") or {}
        if not u:
            tu, cu = "&mdash;", ""
        elif u.get("erro"):
            tu, cu = esc(str(u["erro"])), "mal"
        elif not u.get("pendentes"):
            tu, cu = "em dia", "ok"
        else:
            tu, cu = "%s pendentes (%s críticas)" % (u.get("pendentes", 0), u.get("criticas", 0)), "atencao" if u.get("criticas") else ""
        linhas = '<li><span>Ligada</span><b class="%s">%s</b></li><li><span>Atualizações</span><b class="%s">%s</b></li>' % (
            "ok" if m.get("ligada", True) else "mal", "sim" if m.get("ligada", True) else "não", cu, tu)
        nos.append('<div class="no" data-s="%s"><div class="no-c"><span class="ponto %s"></span><strong>%s</strong>%s</div>'
                   '<p class="motivo">%s</p><ul class="linhas">%s</ul></div>'
                   % (DS[x["estado"]], CL[x["estado"]], esc(x["nome"]), pil(x), esc(x["motivo"]), linhas))
    mapa = ('<div class="hub" data-s="%s"><span class="logo" aria-hidden="true">KCU</span><span>A tua casa</span><span class="ponto %s"></span></div>'
            '<div class="nos-w"><div class="nos">%s</div></div>'
            % ({"ok": "ok", "mal": "mal", "off": "erro"}[geral], {"ok": "ok", "mal": "atencao", "off": "mal"}[geral], "".join(nos))
            if nos else '<p class="vazio">Sem máquinas: aponta "maquinas" para o estado.json do estado-maquinas.</p>')
    gerado_m = (e.get("maquinas") or {}).get("gerado")
    return """<!doctype html><html lang="pt"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="30">
<meta name="color-scheme" content="dark"><meta name="theme-color" content="#050a14">
<title>%(titulo)s</title><style>%(css)s</style></head><body data-geral="%(geral)s">
<header class="barra"><div class="barra-in">
<div class="marca"><span class="logo" aria-hidden="true">KCU</span><span class="marca-t"><strong>%(titulo)s</strong><small>Centro de operações</small></span></div>
<span class="selo" role="status"><span class="ponto"></span><span>%(selo)s</span></span><span class="esp"></span>
<div class="tele"><span class="tele-v">%(hora)s</span><span class="tele-l">última leitura</span></div>
</div></header>
<main class="pagina"><h1 class="so-leitor">%(titulo)s</h1><div class="grelha">
<section class="painel heroi" style="--i:0"><div class="cab"><span class="idx">01</span><h2>Saúde do sistema</h2><span class="meta">%(bons)d de %(total)d bem</span></div>
<div class="heroi-c"><div class="anel">
<svg viewBox="0 0 240 240" aria-hidden="true"><defs>
<linearGradient id="gOk" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#38d9f5"/><stop offset="1" stop-color="#34d399"/></linearGradient>
<linearGradient id="gMal" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#fbbf24"/><stop offset="1" stop-color="#fb7185"/></linearGradient></defs>
<g transform="rotate(-90 120 120)"><circle class="trilho" cx="120" cy="120" r="96"/>
<circle class="valor" cx="120" cy="120" r="96" style="stroke-dashoffset:%(offset).2f"/>%(ticks)s</g></svg>
<svg class="gira" viewBox="0 0 240 240" aria-hidden="true"><circle cx="120" cy="120" r="64"/></svg>
<div class="anel-c"><div><div class="pct">%(pct)d<small>%%</small></div><div class="anel-l">a correr bem</div><div class="anel-b">%(bons)d/%(total)d</div></div></div>
</div><div><p class="frase">%(frase)s</p><p class="frase2">%(frase2)s</p><div class="areas">%(areas)s</div></div></div></section>
<div class="kpis">%(kpis)s</div>
<section class="painel p-srv" style="--i:9"><div class="cab"><span class="idx">02</span><h2>Serviços</h2><span class="meta">%(srv_m)s</span></div>
<div class="corpo"><div class="srv">%(cartoes)s</div></div></section>
<section class="painel p-map" style="--i:10"><div class="cab"><span class="idx">03</span><h2>Máquinas</h2><span class="meta">%(maq_m)s</span></div>
<div class="corpo">%(mapa)s</div></section>
</div><p class="rodape">Só neste PC · atualiza-se de 30 em 30 s</p></main></body></html>""" % dict(
        titulo=esc(e["titulo"]), css=CSS, geral=geral, selo=esc(selo), hora=esc(e["gerado"][11:19]),
        bons=bons, total=len(todos), offset=603.19 * (1 - pct / 100), ticks=TICKS, pct=pct, frase=frase,
        frase2=("%d serviços e %d máquinas vigiados." % (len(es["servicos"]), len(es["maquinas"]))
                + ("" if not mal else " O pior aparece primeiro.")),
        areas=areas, kpis=kpis, cartoes=cartoes or '<p class="vazio">Sem verificações no verificacoes.json.</p>',
        srv_m="%d de %d a responder" % (sum(1 for v in e["verificacoes"] if v["ok"]), len(e["verificacoes"])),
        maq_m=("gerado a " + esc(str(gerado_m)[:16].replace("T", " "))) if gerado_m else "", mapa=mapa)


class Pedido(BaseHTTPRequestHandler):
    def log_message(self, *a):  # sem barulho na consola
        pass

    def responder(self, corpo, tipo):
        dados = corpo.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", tipo)
        self.send_header("Content-Length", str(len(dados)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(dados)

    def do_GET(self):
        # recusa outro nome no Host: um site aberto no browser podia ler isto por DNS rebinding
        if self.headers.get("Host", "").rsplit(":", 1)[0] not in ("127.0.0.1", "localhost"):
            return self.send_error(403)
        caminho = self.path.split("?")[0]
        if caminho == "/":
            return self.responder(pagina(estado()), "text/html; charset=utf-8")
        if caminho == "/estado.json":
            return self.responder(json.dumps(estado(), ensure_ascii=False, indent=2), "application/json; charset=utf-8")
        self.send_error(404)


def main():
    cfg, caminho = ler_config()
    if "--ensaio" in sys.argv:
        if sys.stdout is not None:
            sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        print("[ensaio] configuracao: %s" % os.path.basename(caminho))
        e = estado()
        for v, x in zip(e["verificacoes"], e["estados"]["servicos"]):
            print("[ensaio] %-30s %-10s %s (%s, %d ms)" % (v["nome"], x["estado"], x["motivo"], v["detalhe"], v["ms"]))
        for x in e["estados"]["maquinas"]:
            print("[ensaio] maquina %-22s %-10s %s" % (x["nome"], x["estado"], x["motivo"]))
        print("[ensaio] a pagina abriria em http://127.0.0.1:%d (nada foi aberto)" % cfg["porta"])
        return
    servidor = ThreadingHTTPServer(("127.0.0.1", int(cfg["porta"])), Pedido)
    print("Pagina de estado em http://127.0.0.1:%d  (Ctrl+C para parar)" % cfg["porta"])
    try:
        servidor.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
