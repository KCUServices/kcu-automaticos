"""Pagina de estado: uma pagina web pequena, so neste PC, que mostra se os teus servicos respondem.

So usa a biblioteca padrao do Python (3.8 ou mais recente). Le a lista em verificacoes.json
(copia verificacoes.exemplo.json e edita). Cada verificacao e uma de:
  {"nome": "...", "url": "http://127.0.0.1:8080/"}     responde por HTTP (qualquer codigo abaixo de 500)?
  {"nome": "...", "porta": 8188, "host": "127.0.0.1"}  a porta TCP aceita ligacao? (host opcional)
Se "maquinas" apontar para o estado.json do estado-maquinas, mostra tambem essa tabela.

Escuta SO em 127.0.0.1 (nao fica visivel na rede). Abre http://127.0.0.1:8765 no browser.
  python estado_pagina.py             arranca a pagina
  python estado_pagina.py --ensaio    faz as verificacoes uma vez, mostra-as e sai (nao abre porta nenhuma)
Rotas: /  (pagina, atualiza-se sozinha)   /estado.json  (o mesmo em JSON)
"""
import html
import json
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


def ler_maquinas(cfg):
    caminho = cfg.get("maquinas")
    if not caminho:
        return None
    if not os.path.isabs(caminho):
        caminho = os.path.join(PASTA, caminho)
    try:
        with open(caminho, encoding="utf-8-sig") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


_cache = {"quando": 0.0, "estado": None}
_trinco = threading.Lock()


def estado():
    with _trinco:
        if _cache["estado"] and time.monotonic() - _cache["quando"] < CACHE_SEG:
            return _cache["estado"]
        cfg, _ = ler_config()
        with ThreadPoolExecutor(max_workers=8) as ex:
            resultados = list(ex.map(verificar, cfg["verificacoes"]))
        e = {"titulo": cfg["titulo"], "gerado": datetime.now().isoformat(timespec="seconds"),
             "verificacoes": resultados, "maquinas": ler_maquinas(cfg)}
        _cache.update(quando=time.monotonic(), estado=e)
        return e


CSS = """
:root{--fundo:#f6f7f9;--cartao:#fff;--texto:#1d2330;--cinza:#6b7280;--ok:#15803d;--mal:#b91c1c;--linha:#e5e7eb}
@media (prefers-color-scheme:dark){:root{--fundo:#12151b;--cartao:#1b1f27;--texto:#e7e9ee;--cinza:#9aa1ad;--ok:#4ade80;--mal:#f87171;--linha:#2a2f3a}}
body{margin:0;padding:24px 16px;background:var(--fundo);color:var(--texto);font:15px/1.5 system-ui,sans-serif}
main{max-width:860px;margin:0 auto}h1{font-size:22px;margin:0 0 4px}h2{font-size:17px;margin:28px 0 10px}
p.sub{color:var(--cinza);margin:0 0 16px}
.grelha{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:10px}
.cartao{background:var(--cartao);border:1px solid var(--linha);border-radius:10px;padding:12px 14px}
.cartao small{display:block;color:var(--cinza)}
.luz{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:8px}.l-ok{background:var(--ok)}.l-mal{background:var(--mal)}
table{width:100%;border-collapse:collapse;background:var(--cartao);border-radius:10px;overflow:hidden}
td,th{padding:10px 12px;border-bottom:1px solid var(--linha);text-align:left}th{color:var(--cinza);font-size:13px}
"""


def pagina(e):
    esc = html.escape
    total = len(e["verificacoes"])
    bons = sum(1 for v in e["verificacoes"] if v["ok"])
    cartoes = "".join(
        '<div class="cartao"><span class="luz %s"></span>%s<small>%s &middot; %d ms</small></div>'
        % ("l-ok" if v["ok"] else "l-mal", esc(v["nome"]), esc(v["detalhe"]), v["ms"])
        for v in e["verificacoes"])
    maq = ""
    m = e.get("maquinas")
    if m and m.get("maquinas"):
        linhas = []
        for x in m["maquinas"]:
            u = x.get("atualizacoes") or {}
            if not u:
                tu = "&mdash;"
            elif u.get("erro"):
                tu = esc(u["erro"])
            else:
                tu = "%s pendentes (%s críticas)" % (u.get("pendentes", 0), u.get("criticas", 0))
            linhas.append('<tr><td><span class="luz %s"></span>%s</td><td>%s</td></tr>'
                          % ("l-ok" if x.get("ligada") else "l-mal", esc(str(x.get("nome", "?"))), tu))
        maq = ("<h2>Máquinas</h2><p class=sub>Do estado-maquinas, gerado a %s</p>"
               "<table><tr><th>Máquina</th><th>Atualizações</th></tr>%s</table>"
               % (esc(str(m.get("gerado", ""))[:16].replace("T", " ")), "".join(linhas)))
    return ("""<!doctype html><html lang="pt"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="refresh" content="30">
<title>%s</title><style>%s</style></head><body><main><h1>%s</h1>
<p class=sub>%d de %d a responder &middot; %s</p><div class=grelha>%s</div>%s</main></body></html>"""
            % (esc(e["titulo"]), CSS, esc(e["titulo"]), bons, total,
               esc(e["gerado"].replace("T", " ")), cartoes, maq))


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
        caminho = self.path.split("?")[0]
        if caminho == "/":
            return self.responder(pagina(estado()), "text/html; charset=utf-8")
        if caminho == "/estado.json":
            return self.responder(json.dumps(estado(), ensure_ascii=False, indent=2), "application/json; charset=utf-8")
        self.send_error(404)


def main():
    cfg, caminho = ler_config()
    if "--ensaio" in sys.argv:
        print("[ensaio] configuracao: %s" % os.path.basename(caminho))
        e = estado()
        for v in e["verificacoes"]:
            print("[ensaio] %-30s %s  (%s, %d ms)" % (v["nome"], "ok" if v["ok"] else "FALHA", v["detalhe"], v["ms"]))
        print("[ensaio] maquinas: %s" % ("lidas" if e["maquinas"] else "nenhuma"))
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
