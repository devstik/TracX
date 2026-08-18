from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria
import datetime
import time

wms_etiqueta_produto_bp = Blueprint('wms_etiqueta_produto', __name__)

# ===============================
# FILA DE IMPRESSÃO (MEMÓRIA)
# ===============================
fila_impressao = []
historico_processados = []  # últimos 100 IDs

# ===============================
# POST - SOLICITAR IMPRESSÃO
# ===============================
@wms_etiqueta_produto_bp.route('/consulta/wms/imprimir_etiqueta_api', methods=['POST'])
def post_imprimir_etiqueta():
    global fila_impressao
    dados = request.json
    client_ip = request.remote_addr

    if not dados:
        return jsonify({"error": "Dados não fornecidos"}), 400

    agent_id = dados.get('AgentId')
    if not agent_id:
        return jsonify({"error": "AgentId é obrigatório"}), 400

    try:
        cd_obj = dados.get('CdObj')
        nm_obj = dados.get('NmObj')
        detalhe = dados.get('Detalhe', '')
        metragem = dados.get('Metragem', '')
        ean = dados.get('Ean13', '')
        data_fab = dados.get(
            'DataFabricacao',
            datetime.date.today().strftime('%d/%m/%Y')
        )

        zpl = f"""
^XA
^CI28
^CF0,60
^FO50,50^FD{nm_obj}^FS
^CF0,40
^FO50,130^FDCodigo: {cd_obj}^FS
^FO50,180^FDLote: {detalhe}^FS
^FO50,230^FDMetros: {metragem}^FS
^FO450,230^FDData: {data_fab}^FS
^FO50,300^BY3
^BCN,100,Y,N,N
^FD{ean}^FS
^XZ
"""

        item_id = int(time.time() * 1_000_000)

        item = {
            "id": item_id,
            "agent_id": agent_id,
            "zpl": zpl,
            "endereco": nm_obj,
            "status": "pendente",  # pendente → enviado → confirmado
            "tentativas": 0,
            "timestamp": time.time(),
            "criado_por": client_ip
        }

        fila_impressao.append(item)

        print(f"✅ [{client_ip}] Etiqueta criada | ID:{item_id} | Agent:{agent_id}")
        print(f"📦 Fila atual: {len(fila_impressao)} itens")

        return jsonify({"message": "OK", "id": item_id}), 200

    except Exception as e:
        print(f"❌ Erro ao criar etiqueta: {e}")
        return jsonify({"error": str(e)}), 500

# ===============================
# GET - AGENTE BUSCA IMPRESSÃO
# ===============================
@wms_etiqueta_produto_bp.route(
    '/consulta/wms/buscar_impressao/<agent_id>',
    methods=['GET']
)
def buscar_impressao(agent_id):
    global fila_impressao, historico_processados

    client_ip = request.remote_addr
    agora = time.time()

    # Limpa itens enviados há mais de 5 minutos
    fila_impressao[:] = [
        item for item in fila_impressao
        if item['status'] == 'pendente' or (agora - item['timestamp']) < 300
    ]

    for item in fila_impressao:
        if item['status'] == 'pendente' and item['agent_id'] == agent_id:
            item['status'] = 'enviado'
            item['tentativas'] += 1
            item['timestamp'] = agora

            print(f"📤 [{client_ip}] Enviando ID {item['id']} para {agent_id}")

            return jsonify({
                "id": item['id'],
                "zpl": item['zpl'],
                "endereco": item['endereco']
            }), 200

    return jsonify({"status": "vazio"}), 204

# ===============================
# POST - CONFIRMA IMPRESSÃO
# ===============================
@wms_etiqueta_produto_bp.route(
    '/consulta/wms/confirmar_impressao/<int:item_id>',
    methods=['POST']
)
def confirmar_impressao(item_id):
    global fila_impressao, historico_processados

    client_ip = request.remote_addr

    for i, item in enumerate(fila_impressao):
        if item['id'] == item_id:
            fila_impressao.pop(i)
            historico_processados.append(item_id)

            if len(historico_processados) > 100:
                historico_processados = historico_processados[-100:]

            print(f"✔️ [{client_ip}] Impressão confirmada | ID:{item_id}")
            return jsonify({"message": "Confirmado"}), 200

    print(f"⚠️ [{client_ip}] ID {item_id} não encontrado")
    return jsonify({"error": "Item não encontrado"}), 404

# ===============================
# GET - STATUS DA FILA (DEBUG)
# ===============================
@wms_etiqueta_produto_bp.route('/consulta/wms/status_fila', methods=['GET'])
def status_fila():
    return jsonify({
        "total": len(fila_impressao),
        "pendentes": len([i for i in fila_impressao if i['status'] == 'pendente']),
        "enviados": len([i for i in fila_impressao if i['status'] == 'enviado']),
        "itens": [
            {
                "id": i['id'],
                "agent_id": i['agent_id'],
                "endereco": i['endereco'],
                "status": i['status'],
                "tentativas": i['tentativas']
            }
            for i in fila_impressao
        ]
    }), 200

# ===============================
# CONSULTA DE PRODUTO (INALTERADA)
# ===============================
@wms_etiqueta_produto_bp.route('/consulta/wms/etiqueta_produto/<int:cd_obj>', methods=['GET'])
def get_etiqueta_produto(cd_obj):
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql = """
            SELECT
                Obj.CdObj,
                NmObj      = UPPER(LTRIM(RTRIM(Obj.NmObj))),
                QrCode     = '{"CdObj":' + CAST(Obj.CdObj AS VARCHAR) + ',"Detalhe":' + CAST(ISNULL(Lot.CdLot, 0) AS VARCHAR) + '}',
                Detalhe    = ISNULL(Lot.NmLot, ''),
                Ean13      = dbo.UFN_GeraCodigoEAN(CaoEan13.NrCao),
                Metragem   = CASE 
                                WHEN Carretel.NmOpc = 'ENF' THEN 'ENF - Enfestado' 
                                WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
                                ELSE ISNULL(CONVERT(varchar, Carretel.NmOpc), '0') + ' Mts' 
                             END
            FROM TbObj Obj
            LEFT JOIN (
                SELECT L1.CdObj, L1.NmLot, L1.CdLot 
                FROM TbLot L1
                WHERE L1.CdLot = (SELECT MAX(CdLot) FROM TbLot L2 WHERE L2.CdObj = L1.CdObj)
            ) Lot ON Lot.CdObj = Obj.CdObj
            LEFT JOIN TbCao CaoEan13 ON CaoEan13.CdObj = Obj.CdObj AND CaoEan13.CdTca = 2 
            LEFT JOIN (
                SELECT Opo.CdObj, Opc.NmOpc
                FROM TbOpo Opo
                JOIN TbCrc Crc ON Crc.CdCrc = Opo.CdCrc AND Crc.CdCrc = 96
                LEFT JOIN TbOpc Opc ON Opc.CdOpc = Opo.CdOpc 
            ) Carretel ON Carretel.CdObj = Obj.CdObj
            WHERE Obj.CdObj = @CD_PARAM
            ORDER BY Obj.NmObj
        """

        cursor.execute(sql.replace("@CD_PARAM", str(cd_obj)))

        colunas = [c[0] for c in cursor.description]
        dados = [dict(zip(colunas, row)) for row in cursor.fetchall()]

        if not dados:
            return jsonify({"message": "Nenhum produto encontrado"}), 404

        return jsonify(dados)

    except Exception as e:
        print(f"❌ Erro SQL: {e}")
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()