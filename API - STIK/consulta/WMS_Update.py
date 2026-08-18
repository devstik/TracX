from flask import Blueprint, jsonify, send_file, request
import qrcode
from io import BytesIO
from flask import send_file

wms_update_bp = Blueprint('wms_update', __name__)

# Configuração simples dos apps (Poderia vir de um banco de dados)
APPS_DATA = {
    "stoqx": {
        "version_code": 100,
        "version_name": "1.1.100",
        "min_supported_version": 1,
        "force_update": False,
        "apk_filename": "stoqx_1.1.100.apk",
        "changelog": [
        "Ajustes na tela de separação",
         ]
    },
    "tracx": {
        "version_code": 50, 
        "version_name": "2.0.50",
        "min_supported_version": 1,
        "force_update": False,
        "apk_filename": "tracx_2.0.50.apk",
        "changelog": [
        "Ajustes",
        ]
    }, 
    "stikvendas": {
        "version_code": 13,
        "version_name": "1.0.13",
        "min_supported_version": 1,
        "force_update": False,
        "apk_filename": "stikvendas_1.0.13.apk",
        "changelog": [
            "Botão de filtro na tela de kanban"
            
        ]
    },
}

@wms_update_bp.route('/update/check', methods=['GET'])
def check_update():
    platform = request.args.get('platform', 'unknown')
    app_id = request.args.get('app', 'unknown') # Pega o ID do app (stoqx ou tracx)

    # Se não for Android ou o App não for reconhecido
    if platform != 'android' or app_id not in APPS_DATA:
        return jsonify({"version_code": 0, "apk_url": ""})

    app_info = APPS_DATA[app_id]
    
    return jsonify({
        "app": app_id,
        "version_code": app_info["version_code"],
        "version_name": app_info["version_name"],
        "min_supported_version": app_info["min_supported_version"],
        "force_update": app_info["force_update"],
        "apk_url": f"http://168.190.90.2:5000/update/download?app={app_id}",
        "changelog": app_info["changelog"]
    })

@wms_update_bp.route('/update/download', methods=['GET'])
def download_apk():
    app_id = request.args.get('app')
    if app_id in APPS_DATA:
        filename = APPS_DATA[app_id]["apk_filename"]
        return send_file(f'files/{filename}', as_attachment=True, download_name=f'{app_id}.apk')
    return "Arquivo não encontrado", 404

@wms_update_bp.route('/update/qrcode', methods=['GET'])
def qrcode_apk():
    app_id = request.args.get('app')

    if app_id not in APPS_DATA:
        return "App não encontrado", 404

    download_url = f"http://168.190.90.2:5000/update/download?app={app_id}"

    qr = qrcode.make(download_url)
    img_io = BytesIO()
    qr.save(img_io, 'PNG')
    img_io.seek(0)

    return send_file(img_io, mimetype='image/png')


@wms_update_bp.route('/update/stoqx', methods=['GET'])
def page_stoqx():
    return """
    <!DOCTYPE html>
    <html lang="pt-BR">
    <head>
        <meta charset="UTF-8">
        <title>Instalar STOQX</title>
        < style >
            body {
                font-family: Arial, sans-serif;
                background: #f4f4f4;
                display: flex;
                justify-content: center;
                align-items: center;
                height: 100vh;
            }
            .card {
                background: white;
                padding: 30px;
                border-radius: 10px;
                text-align: center;
                box-shadow: 0 0 10px rgba(0,0,0,.1);
            }
            img {
                width: 260px;
                margin: 20px 0;
            }
            .btn {
                display: inline-block;
                margin-top: 15px;
                padding: 10px 20px;
                background: #2c7be5;
                color: white;
                text-decoration: none;
                border-radius: 5px;
            }
        </style>
    </head>
    <body>
        <div class="card">
            <h1>📦 STOQX</h1>
            <p>Escaneie o QR Code para instalar</p>

            <img src="/update/qrcode?app=stoqx" alt="QR Code STOQX">

            <br>
            <a class="btn" href="/update/download?app=stoqx">
                Baixar APK
            </a>

            <p style="font-size: 12px; color: #666;">
                Permita instalação de fontes desconhecidas
            </p>
        </div>
    </body>
    </html>
    """
