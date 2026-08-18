from flask import Blueprint, jsonify, send_file, request

wms_update_pc_bp = Blueprint('wms_update_pc', __name__)

# Configuração simples dos apps (Poderia vir de um banco de dados)
APPS_DATA = {
    "interface_pc": {
        "version_code": 2, 
        "version_name": "2.0.0",
        "min_supported_version": 1,
        "force_update": False,
        "filename": "FichaArtigo.exe", 
        "changelog": ["Nova interface", "Auto-update implementado"]
    }
}

@wms_update_pc_bp .route('/update_pc/check', methods=['GET'])
def check_update():
    platform = request.args.get('platform', 'unknown')
    app_id = request.args.get('app', 'unknown')

    # Alterado: Agora permite 'android' ou 'windows'
    if platform not in ['android', 'windows'] or app_id not in APPS_DATA:
        return jsonify({"version_code": 0, "url": "", "error": "App ou plataforma inválida"}), 400

    app_info = APPS_DATA[app_id]
    
    return jsonify({
        "app": app_id,
        "version_code": app_info["version_code"],
        "version_name": app_info["version_name"],
        "min_supported_version": app_info["min_supported_version"],
        "force_update": app_info["force_update"],
        # Nome da chave alterado para 'download_url' (mais genérico que apk_url)
        "download_url": f"http://168.190.90.2:5000/update/download?app={app_id}",
        "changelog": app_info["changelog"]
    })

@wms_update_pc_bp .route('/update_pc/download', methods=['GET'])
def download_file():
    app_id = request.args.get('app')
    if app_id in APPS_DATA:
        # Pega o nome do arquivo independente de ser .apk ou .exe
        filename = APPS_DATA[app_id]["filename"] 
        return send_file(f'files/{filename}', as_attachment=True)
    return "Arquivo não encontrado", 404