import time
import requests
import win32print
import sys
import os
from datetime import datetime

# ===============================
# CONFIGURAÇÕES
# ===============================
API_BASE = "http://168.190.90.2:5000"
PRINTER_NAME = "EtqEmbalagem"
POLL_INTERVAL = 2

LOG_DIR = r"C:\AgenteImpressao"
LOG_FILE = os.path.join(LOG_DIR, "agente.log")

# ===============================
# LOG
# ===============================
def log(msg):
    if not os.path.exists(LOG_DIR):
        os.makedirs(LOG_DIR)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(f"[{datetime.now().strftime('%d/%m/%Y %H:%M:%S')}] {msg}\n")

# ===============================
# IMPRESSÃO
# ===============================
def imprimir_zpl(zpl, item_id):
    try:
        log(f"⏳ Enviando ID {item_id} para a impressora '{PRINTER_NAME}'")
        hPrinter = win32print.OpenPrinter(PRINTER_NAME)
        try:
            hJob = win32print.StartDocPrinter(
                hPrinter,
                1,
                (f"Etiqueta Zebra - ID {item_id}", None, "RAW")
            )
            win32print.StartPagePrinter(hPrinter)
            # Alterado para latin-1 para garantir integridade dos dados gráficos do ZPL
            win32print.WritePrinter(hPrinter, zpl.encode("latin-1"))
            win32print.EndPagePrinter(hPrinter)
            win32print.EndDocPrinter(hPrinter)
            return True
        finally:
            win32print.ClosePrinter(hPrinter)
    except Exception as e:
        log(f"❌ Erro na impressora: {e}")
        return False

# ===============================
# MAIN
# ===============================
def main():
    log(f"🟢 Agente iniciado v2 (Ack Mode) | Impressora: {PRINTER_NAME}")

    url_busca = f"{API_BASE}/consulta/wms/buscar_impressao"

    while True:
        try:
            resp = requests.get(url_busca, timeout=10)

            if resp.status_code == 200:
                data = resp.json()
                if not data:
                    time.sleep(POLL_INTERVAL)
                    continue

                item_id = data.get("id")
                zpl = data.get("zpl")
                endereco = data.get("endereco")

                log(f"📥 Recebido: {endereco} (ID: {item_id})")

                if zpl:
                    # TENTA IMPRIMIR
                    if imprimir_zpl(zpl, item_id):
                        log(f"✔️ Impressão enviada. Confirmando recebimento para deletar da fila...")
                        
                        # NOVO: Chamar a rota de confirmação (DELETE)
                        url_confirmar = f"{API_BASE}/consulta/wms/confirmar_impressao/{item_id}"
                        try:
                            confirm_resp = requests.delete(url_confirmar, timeout=5)
                            if confirm_resp.status_code == 200:
                                log(f"🗑️ ID {item_id} removido da fila do servidor.")
                            else:
                                log(f"⚠️ Servidor não deletou {item_id}, pode imprimir duplicado.")
                        except Exception as e:
                            log(f"⚠️ Erro ao confirmar deleção: {e}")
                    else:
                        log(f"⚠️ Falha no spooler. O item {item_id} permanecerá na fila para tentar novamente.")
                else:
                    log("🚫 ZPL vazio")

            elif resp.status_code != 204:
                log(f"⚠️ API retornou {resp.status_code}")

        except Exception as e:
            log(f"💥 Erro inesperado: {e}")

        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        log(f"🛑 Agente finalizado com erro: {e}")
        sys.exit(1)