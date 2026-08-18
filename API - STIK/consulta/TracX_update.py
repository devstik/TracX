from flask import Blueprint, jsonify, send_file, request

wms_update_bp = Blueprint('wms_update', __name__)

@wms_update_bp.route('/update/tracx/check', methods=['GET'])
def check_update():
    # # Obtém o parâmetro 'platform' enviado pelo Flutter (?platform=android ou ?platform=ios)
    # platform = request.args.get('platform', 'unknown')
    
    # # Se NÃO for android, retornamos uma resposta neutra (version_code: 0)
    # # Isso impede que o app em iOS ou Mac mostre o diálogo de atualização forçada
    # if platform != 'android':
    #     return jsonify({
    #         "app": "StoqX",
    #         "version_code": 0,
    #         "version_name": "1.1.7",
    #         "min_supported_version": 0,
    #         "force_update": False,
    #         "apk_url": "",
    #         "changelog": []
    #     })

    # Dados de atualização exclusivos para Android
    return jsonify({
        "app": "TracX",
        "version_code": 1,
        "version_name": "1.0.2",
        "min_supported_version": 1,
        "force_update": False, 
        "apk_url": "http://168.190.90.2:5000/update/download",
        "changelog": [
            "Adição de novas telas e funcionalidades",
        ]
    })


@wms_update_bp.route('/update/download', methods=['GET'])
def download_apk():
    return send_file(
        'files/stoqx_1.1.11.apk',
        as_attachment=True,
        download_name='StoqX.apk'
    )