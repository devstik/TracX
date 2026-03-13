"""
Servidor Zebra - Browser Print Minimalista
Recebe requisições do app Flutter e retorna HTML para imprimir
"""

from flask import Flask, request
import json
from datetime import datetime

app = Flask(__name__)

# ============================================================================
# ROTA PRINCIPAL - RECEBE ZPL E RETORNA HTML
# ============================================================================

@app.route('/imprimir', methods=['POST'])
def imprimir():
    """Recebe dados e retorna HTML para imprimir"""
    dados = request.get_json() or {}
    
    cdObj = dados.get('cdObj', '')
    nome = dados.get('nome', '')
    qrCode = dados.get('qrCode', '')
    detalhe = dados.get('detalhe', '')
    ean13 = dados.get('ean13', '')
    metragem = dados.get('metragem', '')
    
    # HTML para imprimir na Zebra
    html = f"""
    <!DOCTYPE html>
    <html>
    <head>
        <meta charset="UTF-8">
        <title>Etiqueta</title>
        <style>
            @page {{
                size: 80mm 50mm;
                margin: 0;
                padding: 0;
            }}
            body {{
                width: 80mm;
                height: 50mm;
                margin: 0;
                padding: 4mm;
                font-family: Arial, sans-serif;
                display: flex;
                font-size: 10px;
            }}
            .qr {{
                width: 40mm;
                height: 40mm;
                display: flex;
                align-items: center;
                justify-content: center;
                margin-right: 4mm;
            }}
            .qr img {{
                max-width: 100%;
                max-height: 100%;
            }}
            .info {{
                flex: 1;
                display: flex;
                flex-direction: column;
                justify-content: flex-start;
            }}
            .codigo {{
                font-weight: bold;
                font-size: 14px;
                margin-bottom: 2mm;
            }}
            .nome {{
                font-weight: bold;
                font-size: 11px;
                margin-bottom: 2mm;
                word-wrap: break-word;
            }}
            .campo {{
                font-size: 8px;
                margin-bottom: 1mm;
            }}
            @media print {{
                * {{
                    margin: 0 !important;
                    padding: 0 !important;
                }}
                body {{
                    margin: 0 !important;
                    padding: 4mm !important;
                }}
            }}
        </style>
    </head>
    <body>
        <div class="qr">
            <img src="https://api.qrserver.com/v1/create-qr-code/?size=100x100&data={qrCode}" alt="QR">
        </div>
        <div class="info">
            <div class="codigo">{cdObj}</div>
            <div class="nome">{nome}</div>
            {f'<div class="campo">Det: {detalhe}</div>' if detalhe else ''}
            {f'<div class="campo">EAN: {ean13}</div>' if ean13 else ''}
            {f'<div class="campo">Mtr: {metragem}</div>' if metragem else ''}
        </div>
    </body>
    <script>
        window.onload = function() {{
            setTimeout(() => {{
                window.print();
                setTimeout(() => {{
                    window.close();
                }}, 500);
            }}, 500);
        }};
    </script>
    </html>
    """
    
    return html, 200, {'Content-Type': 'text/html; charset=utf-8'}


@app.route('/status', methods=['GET'])
def status():
    """Verifica se servidor está online"""
    return {'status': 'online', 'timestamp': datetime.now().isoformat()}


if __name__ == '__main__':
    print("=" * 60)
    print("🖨️  SERVIDOR ZEBRA - BROWSER PRINT")
    print("=" * 60)
    print()
    print("✅ Servidor iniciado!")
    print()
    print("Endpoint: POST /imprimir")
    print("URL: http://localhost:5000/imprimir")
    print()
    print("Exemplo JSON:")
    print("""{
  "cdObj": "001",
  "nome": "Camiseta Azul",
  "qrCode": "SKU123456",
  "detalhe": "Tamanho M",
  "ean13": "1234567890128",
  "metragem": "2.5m"
}""")
    print()
    print("=" * 60)
    print("🚀 Servidor rodando em http://localhost:5000")
    print("   Pressione Ctrl+C para parar\n")
    
    app.run(host='0.0.0.0', port=5000, debug=False)