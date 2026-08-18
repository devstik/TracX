from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 
import datetime  
import requests
from datetime import datetime

# Define o Blueprint
wms_movimentos_bp = Blueprint('wms_movimentos', __name__)


# ===================================================================
# ROTA 1: POST (para INSERIR um novo movimento)
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/movimentar', methods=['POST'])
def inserir_movimento():
    """
    Endpoint para registrar uma nova entrada (1) ou saída (2)
    de um SKU em um endereço.
    Agora suporta os campos 'Detalhe', 'Origem' e 'Observacao'.
    """
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        # Pega os dados do JSON enviado
        endereco = data.get('Endereco')
        cod_sku = data.get('CodSKU')
        tp_mov = data.get('TpMov')
        qt_movida = data.get('QtMovida')
        detalhe = data.get('Detalhe')

        origem = (data.get('Origem') or '').strip() or None
        observacao = (data.get('Observacao') or '').strip() or None

        # Validação de campos obrigatórios
        if not all([endereco, cod_sku, tp_mov, qt_movida]):
            return jsonify({
                "error": "Campos 'Endereco', 'CodSKU', 'TpMov' e 'QtMovida' são obrigatórios"
            }), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;
            INSERT INTO dbo.Stik_WMS_Movimento
                (Endereco, CodSKU, TpMov, QtMovida, Detalhe, DataMovimento, Origem, Observacao)
            VALUES
                (?, ?, ?, ?, ?, GETDATE(), ISNULL(?, 'WMS'), ?);
        """

        cursor.execute(sql_query, (
            endereco,
            cod_sku,
            tp_mov,
            qt_movida,
            detalhe,
            origem,
            observacao
        ))

        connection.commit()

        print(
            f"✅ Movimento registrado: SKU {cod_sku} | "
            f"Detalhe: {detalhe} -> Endereço {endereco} | "
            f"Origem: {origem or 'WMS'}"
        )
        return jsonify({"message": "Movimento registrado com sucesso!"}), 201

    except Exception as e:
        if connection:
            connection.rollback()
        print(f"❌ Erro ao registrar movimento: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔌 Conexão com o banco de dados fechada.")


# ===================================================================
# ROTA 2: GET (para CONSULTAR os movimentos)
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/movimentos', methods=['GET'])
def get_movimentos():
    """
    Endpoint para consultar o histórico de movimentos.
    Aceita filtros por ?CodSKU=..., ?Endereco=... ou ?Detalhe=...
    """
    connection = None
    try:
        # Pega filtros opcionais da URL
        cod_sku = request.args.get('CodSKU')
        endereco = request.args.get('Endereco')
        detalhe = request.args.get('Detalhe')

        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        # Constrói a query base
        sql_query = "SET NOCOUNT ON; SELECT * FROM dbo.stik_WMS_Movimento"
        params = []
        
        # Adiciona filtros dinamicamente
        condicoes = []
        
        if cod_sku:
            condicoes.append("CodSKU = ?")
            params.append(int(cod_sku))
        
        if endereco:
            condicoes.append("Endereco = ?")
            params.append(endereco)
            
        if detalhe:
            condicoes.append("Detalhe = ?")
            params.append(detalhe)
        
        # Se houver condições, adiciona o WHERE
        if condicoes:
            sql_query += " WHERE " + " AND ".join(condicoes)
        
        sql_query += " ORDER BY DataMovimento DESC;"

        cursor.execute(sql_query, params)
        registros = [dict(zip([column[0] for column in cursor.description], row)) for row in cursor.fetchall()]
        
        print(f"✅ Consulta de movimentos executada. {len(registros)} linhas retornadas.")
        return jsonify(registros)

    except Exception as e:
        print(f"❌ Erro ao consultar movimentos: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔌 Conexão com o banco de dados fechada.")

@wms_movimentos_bp.route('/consulta/wms/rastrear', methods=['POST'])
def inserir_rastreio():
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        # Captura os dados brutos
        nr_romaneio = data.get('nr_romaneio')
        evento = data.get('evento')
        data_hora_raw = data.get('data_hora')
        usuario_id = data.get('usuario_id')
        dispositivo_id = data.get('dispositivo_id')

        if not all([nr_romaneio, evento, data_hora_raw]):
            return jsonify({"error": "Campos 'nr_romaneio', 'evento' e 'data_hora' são obrigatórios"}), 400

        # --- CONVERSÃO CORRETA DE DATA PARA SQL SERVER ---
        from datetime import datetime
        
        try:
            # Tenta parsear o ISO8601 do Flutter
            if 'T' in str(data_hora_raw):
                # Remove o 'Z' se existir e converte
                data_hora_str = str(data_hora_raw).replace('Z', '').split('.')[0]
                data_hora_obj = datetime.fromisoformat(data_hora_str)
            else:
                # Se vier em outro formato, tenta parsear
                data_hora_obj = datetime.strptime(str(data_hora_raw), '%Y-%m-%d %H:%M:%S')
            
            # Formata no padrão aceito pelo SQL Server: 'YYYY-MM-DD HH:MM:SS'
            data_hora_formatada = data_hora_obj.strftime('%Y-%m-%d %H:%M:%S')
            
        except ValueError as ve:
            return jsonify({"error": f"Formato de data inválido: {str(ve)}"}), 400

        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;
            INSERT INTO dbo.STIK_WMS_ROMANEIO_RASTREIO
                (nr_romaneio, evento, data_hora, usuario_id, dispositivo_id, sincronizado_em)
            VALUES
                (?, ?, CONVERT(DATETIME, ?, 120), ?, ?, GETDATE());
        """
        
        # Parâmetros tratados
        params = (
            int(nr_romaneio), 
            str(evento), 
            data_hora_formatada,  # Já formatada corretamente
            str(usuario_id) if usuario_id else '0',
            str(dispositivo_id) if dispositivo_id else 'MOBILE'
        )
        
        cursor.execute(sql_query, params)
        connection.commit() 
        
        return jsonify({
            "message": f"Evento {evento} registrado para o romaneio {nr_romaneio}",
            "data_hora_processada": data_hora_formatada
        }), 201

    except ValueError as ve:
        return jsonify({"error": f"Erro de validação: {str(ve)}"}), 400
    except Exception as e:
        if connection: 
            connection.rollback()
        print(f"❌ ERRO NO BANCO: {str(e)}")
        print(f"📋 Dados recebidos: {data}")
        return jsonify({"error": str(e)}), 500
    finally:
        if connection: 
            connection.close()

# ===================================================================
# ROTA: CONSULTAR RASTREIO (GET)
# Usada pela tela de Ociosidade para saber os horários de cada etapa
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/rastreio/<int:nr_romaneio>', methods=['GET'])
def get_rastreio_romaneio(nr_romaneio):
    connection = None
    try:
        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;
            SELECT 
                nr_romaneio,
                MIN(CASE WHEN evento = 'INICIO_SEPARACAO' THEN data_hora END) AS startedAt,
                MAX(CASE WHEN evento = 'FIM_SEPARACAO' THEN data_hora END) AS finishedAt,
                MIN(CASE WHEN evento = 'INICIO_CONFERENCIA' THEN data_hora END) AS conferenceStartedAt
            FROM dbo.STIK_WMS_ROMANEIO_RASTREIO
            WHERE nr_romaneio = ?
            GROUP BY nr_romaneio;
        """

        cursor.execute(sql_query, (nr_romaneio,))
        row = cursor.fetchone()
        
        if row:
            # Pega os nomes das colunas
            columns = [column[0] for column in cursor.description]
            # Cria o dicionário inicial
            resultado = dict(zip(columns, row))
            
            # --- CORREÇÃO AQUI: Converter datas para ISO 8601 ---
            for chave in ['startedAt', 'finishedAt', 'conferenceStartedAt']:
                if resultado[chave] is not None:
                    # isoformat() transforma em "2026-01-21T15:22:47"
                    resultado[chave] = resultado[chave].isoformat()
            
            return jsonify(resultado)
        else:
            return jsonify({"message": "Nenhum rastreio encontrado"}), 404

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection: connection.close()


# ===================================================================
# ROTA: INSERIR FEEDBACK (POST)
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/feedback', methods=['POST'])
def inserir_feedback():
    """
    Endpoint para registrar o feedback anônimo dos usuários.
    """
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        # Captura os dados enviados pelo Flutter
        nota_emoji = data.get('NotaEmoji')
        motivos = data.get('MotivosRapidos')
        comentario = data.get('Comentario')
        versao_app = data.get('VersaoApp')
        plataforma = data.get('Plataforma')

        # Validação simples (Nota é obrigatória)
        if nota_emoji is None:
            return jsonify({"error": "O campo 'NotaEmoji' é obrigatório"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;
            INSERT INTO dbo.STIK_WMS_FEEDBACKS
                (NotaEmoji, MotivosRapidos, Comentario, VersaoApp, Plataforma, DataCriacao)
            VALUES
                (?, ?, ?, ?, ?, GETDATE());
        """

        params = (
            int(nota_emoji),
            str(motivos) if motivos else None,
            str(comentario) if comentario else None,
            str(versao_app) if versao_app else '1.0.0',
            str(plataforma) if plataforma else 'Desconhecido'
        )

        cursor.execute(sql_query, params)
        connection.commit()

        print(f"✅ Feedback recebido: Nota {nota_emoji} | Plataforma: {plataforma}")
        return jsonify({"message": "Feedback enviado com sucesso!"}), 201

    except Exception as e:
        if connection:
            connection.rollback()
        print(f"❌ Erro ao salvar feedback: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@wms_movimentos_bp.route('/consulta/wms/feedbacks_recebidos', methods=['GET'])
def get_feedbacks():
    """
    Endpoint para listar todos os feedbacks recebidos.
    """
    connection = None
    try:
        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        # Seleciona todos os feedbacks, do mais novo para o mais antigo
        sql_query = "SET NOCOUNT ON; SELECT * FROM dbo.STIK_WMS_FEEDBACKS ORDER BY DataCriacao DESC"

        cursor.execute(sql_query)
        
        # Converte as linhas do banco em uma lista de dicionários (JSON)
        columns = [column[0] for column in cursor.description]
        registros = []
        
        for row in cursor.fetchall():
            item = dict(zip(columns, row))
            # Tratamento para a data não dar erro no JSON
            if item['DataCriacao']:
                item['DataCriacao'] = item['DataCriacao'].isoformat()
            registros.append(item)
        
        return jsonify(registros), 200

    except Exception as e:
        print(f"❌ Erro ao consultar feedbacks: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: GET (Consultar Fila de Faturamento WMS)
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/faturamento/fila', methods=['GET'])
def get_fila_faturamento():
    """
    Endpoint para consultar a fila de faturamento do WMS.

    Filtros opcionais:
    ?Status=
    ?NrRomaneio=
    ?CdVpd=
    ?CdVpo=
    ?CdFat=
    """

    connection = None
    try:
        # Filtros opcionais via query string
        status = request.args.get('Status')
        nr_romaneio = request.args.get('NrRomaneio')
        cd_vpd = request.args.get('CdVpd')
        cd_vpo = request.args.get('CdVpo')
        cd_fat = request.args.get('CdFat')

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;
            SELECT 
                IDFila,
                Status,
                CdVpd,
                CdVpo,
                Quantidade,
                NrRomaneio,
                CdUsr,
                Origem,
                CdFat,
                MsgErro,
                Tentativas,
                DtInclusao,
                DtInicioProc,
                DtFimProc
            FROM dbo.Stik_WMS_Faturamento_Fila
        """

        params = []
        condicoes = []

        # Filtros dinâmicos
        if status:
            condicoes.append("Status = ?")
            params.append(status)

        if nr_romaneio:
            condicoes.append("NrRomaneio = ?")
            params.append(int(nr_romaneio))

        if cd_vpd:
            condicoes.append("CdVpd = ?")
            params.append(int(cd_vpd))

        if cd_vpo:
            condicoes.append("CdVpo = ?")
            params.append(int(cd_vpo))

        if cd_fat:
            condicoes.append("CdFat = ?")
            params.append(int(cd_fat))

        # Adiciona WHERE se houver filtros
        if condicoes:
            sql_query += " WHERE " + " AND ".join(condicoes)

        sql_query += " ORDER BY DtInclusao DESC;"

        cursor.execute(sql_query, params)

        columns = [column[0] for column in cursor.description]
        registros = []

        for row in cursor.fetchall():
            item = dict(zip(columns, row))

            # Conversão de datas para ISO (evita erro no JSON)
            for campo_data in ['DtInclusao', 'DtInicioProc', 'DtFimProc']:
                if item[campo_data]:
                    item[campo_data] = item[campo_data].isoformat()

            registros.append(item)

        print(f"✅ Consulta da fila executada. {len(registros)} registros retornados.")
        return jsonify(registros), 200

    except Exception as e:
        print(f"❌ Erro ao consultar fila de faturamento: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔌 Conexão com o banco de dados fechada.")


#Rotas para baixar metros-embalagem apos leitura
# ===================================================================
# ROTA: CONFIRMAR ITEM DA SEPARACAO
# Baixa estoque e embalagem no momento da confirmacao
# ===================================================================

def _to_int_sep(value, default=0):
    if value is None:
        return default
    try:
        if isinstance(value, str):
            value = value.strip().replace(',', '.')
        return int(float(value))
    except Exception:
        return default


def _to_float_sep(value, default=0.0):
    if value is None:
        return default
    try:
        if isinstance(value, str):
            value = value.strip().replace(',', '.')
        return float(value)
    except Exception:
        return default


def _base_url_sep():
    return request.host_url.rstrip('/')


def _post_json_sep(path, payload, timeout=20):
    url = f'{_base_url_sep()}{path}'
    response = requests.post(url, json=payload, timeout=timeout)
    if response.status_code < 200 or response.status_code >= 300:
        raise Exception(f'Erro {response.status_code} em {path}: {response.text}')
    try:
        return response.json()
    except Exception:
        return {"success": True}


def _tem_embalagem_sep(item):
    return any([
        _to_int_sep(item.get('qt_caixa_p')) > 0,
        _to_int_sep(item.get('qt_caixa_g')) > 0,
        _to_int_sep(item.get('qt_enfestado')) > 0,
        _to_int_sep(item.get('qt_enfraldado')) > 0,
    ])


def _row_to_dict_sep(cursor, row):
    if not row:
        return None
    cols = [col[0] for col in cursor.description]
    return dict(zip(cols, row))


@wms_movimentos_bp.route('/consulta/wms/separacao/confirmar_item', methods=['POST'])
def confirmar_item_separacao():
    connection = None
    item = None
    movimento_saida_ok = False
    embalagem_saida_ok = False

    try:
        data = request.get_json() or {}

        item = {
            'nr_romaneio': _to_int_sep(data.get('nr_romaneio')),
            'linha_id': (data.get('linha_id') or '').strip(),
            'endereco': (data.get('endereco') or '').strip().upper(),
            'cod_sku': _to_int_sep(data.get('cod_sku')),
            'detalhe': _to_int_sep(data.get('detalhe')),
            'quantidade': _to_float_sep(data.get('quantidade')),
            'qt_caixa_p': _to_int_sep(data.get('qt_caixa_p')),
            'qt_caixa_g': _to_int_sep(data.get('qt_caixa_g')),
            'qt_enfestado': _to_int_sep(data.get('qt_enfestado')),
            'qt_enfraldado': _to_int_sep(data.get('qt_enfraldado')),
            'artigo': (data.get('artigo') or '').strip(),
            'cd_usr': _to_int_sep(data.get('cd_usr')) or None,
            'observacao': (data.get('observacao') or '').strip(),
        }

        if (
            item['nr_romaneio'] <= 0 or
            not item['linha_id'] or
            not item['endereco'] or
            item['cod_sku'] <= 0 or
            item['quantidade'] <= 0
        ):
            return jsonify({
                'error': 'Campos obrigatórios: nr_romaneio, linha_id, endereco, cod_sku, quantidade'
            }), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({'error': 'Falha ao conectar ao banco.'}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute("""
            SELECT TOP 1 *
            FROM dbo.Stik_WMS_Separacao_Confirmacao WITH (UPDLOCK, HOLDLOCK)
            WHERE NrRomaneio = ?
              AND LinhaId = ?
              AND UPPER(LTRIM(RTRIM(Endereco))) = ?
              AND CodSKU = ?
              AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
              AND Status = 'BAIXADO'
        """, (
            item['nr_romaneio'],
            item['linha_id'],
            item['endereco'],
            item['cod_sku'],
            item['detalhe'],
        ))
        existente = cursor.fetchone()

        if existente:
            connection.commit()
            return jsonify({
                'success': True,
                'message': 'Item já estava confirmado/baixado.',
                'already_processed': True
            }), 200

        _post_json_sep('/consulta/wms/movimentar', {
            'Endereco': item['endereco'],
            'CodSKU': item['cod_sku'],
            'CdObj': item['cod_sku'],
            'Detalhe': item['detalhe'],
            'TpMov': 2,
            'QtMovida': item['quantidade'],
        })
        movimento_saida_ok = True

        if _tem_embalagem_sep(item):
            _post_json_sep('/consulta/wms/saida_embalagem', {
                'endereco': item['endereco'],
                'cod_sku': item['cod_sku'],
                'detalhe': item['detalhe'],
                'artigo': item['artigo'],
                'qt_caixa_p': item['qt_caixa_p'],
                'qt_caixa_g': item['qt_caixa_g'],
                'qt_enfestado': item['qt_enfestado'],
                'qt_enfraldado': item['qt_enfraldado'],
                'quantidade': item['quantidade'],
                'cd_usr': item['cd_usr'],
            })
            embalagem_saida_ok = True

        cursor.execute("""
            INSERT INTO dbo.Stik_WMS_Separacao_Confirmacao
                (NrRomaneio, LinhaId, Endereco, CodSKU, Detalhe,
                 QuantidadeMetro, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
                 CdUsr, Status, Origem, DtConfirmacao, Observacao)
            VALUES
                (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'BAIXADO', 'CONFIRMAR_ITEM', GETDATE(), ?)
        """, (
            item['nr_romaneio'],
            item['linha_id'],
            item['endereco'],
            item['cod_sku'],
            item['detalhe'],
            item['quantidade'],
            item['qt_caixa_p'],
            item['qt_caixa_g'],
            item['qt_enfestado'],
            item['qt_enfraldado'],
            item['cd_usr'],
            item['observacao'] or None,
        ))

        connection.commit()
        return jsonify({
            'success': True,
            'message': 'Item confirmado com baixa de estoque e embalagem.'
        }), 201

    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass

        try:
            if embalagem_saida_ok and item:
                _post_json_sep('/consulta/wms/alocar_embalagem', {
                    'endereco': item['endereco'],
                    'cod_sku': item['cod_sku'],
                    'detalhe': item['detalhe'],
                    'artigo': item['artigo'],
                    'quantidade': item['quantidade'],
                    'qt_caixa_p': item['qt_caixa_p'],
                    'qt_caixa_g': item['qt_caixa_g'],
                    'qt_enfestado': item['qt_enfestado'],
                    'qt_enfraldado': item['qt_enfraldado'],
                    'cd_usr': item['cd_usr'],
                    'origem': 'ROLLBACK_CONFIRMAR_ITEM',
                })
        except Exception:
            pass

        try:
            if movimento_saida_ok and item:
                _post_json_sep('/consulta/wms/movimentar', {
                    'Endereco': item['endereco'],
                    'CodSKU': item['cod_sku'],
                    'CdObj': item['cod_sku'],
                    'Detalhe': item['detalhe'],
                    'TpMov': 1,
                    'QtMovida': item['quantidade'],
                })
        except Exception:
            pass

        return jsonify({'error': str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: REINICIAR UM ITEM
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/separacao/reiniciar_item', methods=['POST'])
def reiniciar_item_separacao():
    connection = None
    payload = None
    movimento_entrada_ok = False
    embalagem_entrada_ok = False
    avisos = []

    try:
        data = request.get_json() or {}
        nr_romaneio = _to_int_sep(data.get('nr_romaneio'))
        linha_id = (data.get('linha_id') or '').strip()
        cd_usr = _to_int_sep(data.get('cd_usr')) or None

        if nr_romaneio <= 0 or not linha_id:
            return jsonify({'error': 'Campos obrigatórios: nr_romaneio, linha_id'}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({'error': 'Falha ao conectar ao banco.'}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute("""
            SELECT TOP 1 *
            FROM dbo.Stik_WMS_Separacao_Confirmacao WITH (UPDLOCK, HOLDLOCK)
            WHERE NrRomaneio = ?
              AND LinhaId = ?
              AND Status = 'BAIXADO'
            ORDER BY ID DESC
        """, (nr_romaneio, linha_id))
        row = cursor.fetchone()
        item = _row_to_dict_sep(cursor, row)

        if not item:
            connection.commit()
            return jsonify({
                'success': True,
                'message': 'Item não possui baixa ativa para reinício.',
                'already_reverted': True
            }), 200

        payload = {
            'endereco': (item['Endereco'] or '').strip().upper(),
            'cod_sku': _to_int_sep(item['CodSKU']),
            'detalhe': _to_int_sep(item['Detalhe']),
            'quantidade': _to_float_sep(item['QuantidadeMetro']),
            'qt_caixa_p': _to_int_sep(item['QtCaixaP']),
            'qt_caixa_g': _to_int_sep(item['QtCaixaG']),
            'qt_enfestado': _to_int_sep(item['QtEnfestado']),
            'qt_enfraldado': _to_int_sep(item['QtEnfraldado']),
            'cd_usr': cd_usr,
        }

        _post_json_sep('/consulta/wms/movimentar', {
            'Endereco': payload['endereco'],
            'CodSKU': payload['cod_sku'],
            'CdObj': payload['cod_sku'],
            'Detalhe': payload['detalhe'],
            'TpMov': 1,
            'QtMovida': payload['quantidade'],
        })
        movimento_entrada_ok = True

        if _tem_embalagem_sep(payload):
            try:
                _post_json_sep('/consulta/wms/alocar_embalagem', {
                    'endereco': payload['endereco'],
                    'cod_sku': payload['cod_sku'],
                    'detalhe': payload['detalhe'],
                    'artigo': '',
                    'quantidade': payload['quantidade'],
                    'qt_caixa_p': payload['qt_caixa_p'],
                    'qt_caixa_g': payload['qt_caixa_g'],
                    'qt_enfestado': payload['qt_enfestado'],
                    'qt_enfraldado': payload['qt_enfraldado'],
                    'cd_usr': payload['cd_usr'],
                    'origem': 'REINICIO_ITEM',
                })
                embalagem_entrada_ok = True
            except Exception as emb_err:
                embalagem_entrada_ok = False
                avisos.append(f'Embalagem não revertida: {emb_err}')

        cursor.execute("""
            UPDATE dbo.Stik_WMS_Separacao_Confirmacao
            SET Status = 'REVERTIDO',
                Origem = 'REINICIAR_ITEM',
                DtReversao = GETDATE(),
                CdUsr = ISNULL(?, CdUsr),
                Observacao = 'Reinício manual do item'
            WHERE ID = ?
        """, (cd_usr, item['ID']))

        connection.commit()
        return jsonify({
            'success': True,
            'message': 'Item reiniciado com sucesso.',
            'embalagem_ok': len(avisos) == 0,
            'avisos': avisos,
        }), 200

    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass

        try:
            if embalagem_entrada_ok and payload:
                _post_json_sep('/consulta/wms/saida_embalagem', {
                    'endereco': payload['endereco'],
                    'cod_sku': payload['cod_sku'],
                    'detalhe': payload['detalhe'],
                    'artigo': '',
                    'qt_caixa_p': payload['qt_caixa_p'],
                    'qt_caixa_g': payload['qt_caixa_g'],
                    'qt_enfestado': payload['qt_enfestado'],
                    'qt_enfraldado': payload['qt_enfraldado'],
                    'quantidade': payload['quantidade'],
                    'cd_usr': payload['cd_usr'],
                })
        except Exception:
            pass

        try:
            if movimento_entrada_ok and payload:
                _post_json_sep('/consulta/wms/movimentar', {
                    'Endereco': payload['endereco'],
                    'CodSKU': payload['cod_sku'],
                    'CdObj': payload['cod_sku'],
                    'Detalhe': payload['detalhe'],
                    'TpMov': 2,
                    'QtMovida': payload['quantidade'],
                })
        except Exception:
            pass

        return jsonify({'error': str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: REINICIAR ROMANEIO INTEIRO
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/separacao/reiniciar_romaneio', methods=['POST'])
def reiniciar_romaneio_separacao():
    connection = None
    try:
        data = request.get_json() or {}
        nr_romaneio = _to_int_sep(data.get('nr_romaneio'))
        cd_usr = _to_int_sep(data.get('cd_usr')) or None

        if nr_romaneio <= 0:
            return jsonify({'error': 'Campo obrigatório: nr_romaneio'}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({'error': 'Falha ao conectar ao banco.'}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        cursor.execute("""
            SELECT *
            FROM dbo.Stik_WMS_Separacao_Confirmacao WITH (NOLOCK)
            WHERE NrRomaneio = ?
              AND Status = 'BAIXADO'
            ORDER BY ID
        """, (nr_romaneio,))
        rows = cursor.fetchall()
        cols = [col[0] for col in cursor.description]
        itens = [dict(zip(cols, row)) for row in rows]

        if not itens:
            return jsonify({
                'success': True,
                'message': 'Romaneio sem itens baixados para reiniciar.',
                'itens_revertidos': 0
            }), 200

        erros = []
        revertidos = 0

        for item in itens:
            resp = requests.post(
                f'{_base_url_sep()}/consulta/wms/separacao/reiniciar_item',
                json={
                    'nr_romaneio': nr_romaneio,
                    'linha_id': item['LinhaId'],
                    'cd_usr': cd_usr,
                },
                timeout=30,
            )
            if 200 <= resp.status_code < 300:
                revertidos += 1
            else:
                erros.append({
                    'linha_id': item['LinhaId'],
                    'status': resp.status_code,
                    'body': resp.text,
                })

        if erros:
            return jsonify({
                'success': False,
                'message': 'Romaneio reiniciado parcialmente.',
                'itens_revertidos': revertidos,
                'erros': erros
            }), 409

        return jsonify({
            'success': True,
            'message': 'Romaneio reiniciado com sucesso.',
            'itens_revertidos': revertidos
        }), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: ENVIAR PARA CONFERENCIA
# Nao baixa estoque. So marca conferido.
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/separacao/enviar_conferencia', methods=['POST'])
def enviar_conferencia_separacao():
    connection = None
    try:
        data = request.get_json() or {}
        nr_romaneio = _to_int_sep(data.get('nr_romaneio'))
        cd_usr = _to_int_sep(data.get('cd_usr')) or None
        observacao = (data.get('observacao') or '').strip()

        if nr_romaneio <= 0:
            return jsonify({'error': 'Campo obrigatório: nr_romaneio'}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({'error': 'Falha ao conectar ao banco.'}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute("""
            SELECT COUNT(1)
            FROM dbo.Stik_WMS_Separacao_Confirmacao WITH (UPDLOCK, HOLDLOCK)
            WHERE NrRomaneio = ?
              AND Status = 'BAIXADO'
        """, (nr_romaneio,))
        total_baixado = _to_int_sep(cursor.fetchone()[0])

        if total_baixado <= 0:
            return jsonify({'error': 'Nenhum item baixado para este romaneio.'}), 409

        cursor.execute("""
            UPDATE dbo.Stik_WMS_Separacao_Confirmacao
            SET Status = 'CONFERIDO',
                Origem = 'ENVIAR_CONFERENCIA',
                DtConferencia = GETDATE(),
                CdUsr = ISNULL(?, CdUsr),
                Observacao = ?
            WHERE NrRomaneio = ?
              AND Status = 'BAIXADO'
        """, (
            cd_usr,
            observacao or 'Separação enviada para conferência',
            nr_romaneio,
        ))

        connection.commit()
        return jsonify({
            'success': True,
            'message': 'Romaneio marcado como enviado para conferência.',
            'itens_conferidos': total_baixado
        }), 200

    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({'error': str(e)}), 500

    finally:
        if connection:
            connection.close()

# ===================================================================
# ROTA: ENFILEIRAR RESERVA
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/entrada/enfileirar_reserva', methods=['POST'])
def enfileirar_reserva_entrada():
    connection = None
    try:
        data = request.get_json() or {}

        ordem_id = int(data.get('ordem_id') or 0)
        dt_entrada_raw = data.get('dt_entrada')
        cod_sku = int(data.get('cod_sku') or 0)
        detalhe = int(data.get('detalhe') or 0)
        quantidade = float(str(data.get('quantidade') or 0).replace(',', '.'))
        cd_usr = data.get('cd_usr')
        cd_usr = int(cd_usr) if cd_usr not in (None, '', 0, '0') else None
        linha_id = (data.get('linha_id') or '').strip()

        if ordem_id <= 0:
            return jsonify({"error": "Campo obrigatório: ordem_id"}), 400
        if not dt_entrada_raw:
            return jsonify({"error": "Campo obrigatório: dt_entrada"}), 400
        if cod_sku <= 0:
            return jsonify({"error": "Campo obrigatório: cod_sku"}), 400
        if quantidade <= 0:
            return jsonify({"error": "Campo obrigatório: quantidade"}), 400
        if not linha_id:
            return jsonify({"error": "Campo obrigatório: linha_id"}), 400

        try:
            dt_entrada_str = str(dt_entrada_raw).strip()
            if 'T' in dt_entrada_str:
                dt_entrada_str = dt_entrada_str.replace('Z', '')
                dt_entrada_obj = datetime.fromisoformat(dt_entrada_str.split('.')[0])
            else:
                dt_entrada_obj = datetime.strptime(dt_entrada_str, '%Y-%m-%d %H:%M:%S')

            dt_entrada_sql = dt_entrada_obj.strftime('%Y-%m-%d %H:%M:%S')
        except ValueError:
            return jsonify({
                "error": "dt_entrada inválida. Use 'YYYY-MM-DD HH:MM:SS' ou ISO8601."
            }), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        cursor.execute("""
            INSERT INTO dbo.Stik_WMS_Reserva_Fila
                (OrdemID, DtEntrada, CodSKU, Detalhe, Quantidade, CdUsr, LinhaID, Status, DtInclusao)
            OUTPUT INSERTED.ID
            VALUES
                (?, CONVERT(DATETIME, ?, 120), ?, ?, ?, ?, ?, 'PENDENTE', GETDATE())
        """, (
            ordem_id,
            dt_entrada_sql,
            cod_sku,
            detalhe,
            quantidade,
            cd_usr,
            linha_id
        ))

        row = cursor.fetchone()
        id_fila = int(row[0])

        connection.commit()

        return jsonify({
            "success": True,
            "message": "Registro incluído na fila de reserva.",
            "id": id_fila,
            "status": "PENDENTE"
        }), 201

    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@wms_movimentos_bp.route('/consulta/wms/entrada/consultar_ordem_reserva', methods=['GET'])
def consultar_ordem_reserva():
    connection = None
    try:
        cod_sku = int(request.args.get('cod_sku') or 0)
        detalhe = int(request.args.get('detalhe') or 0)

        if cod_sku <= 0:
            return jsonify({"error": "Campo obrigatório: cod_sku"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        sql = """
            SELECT TOP 1
                Vpo.CdVpo,
                Vpo.CdVpd,
                Vpo.CdObj,
                Vpo.CdLot,
                Vpo.CdUnd,
                T.NrOrdem,
                Saldo =
                    ISNULL(Vpo.QtVpo, 0)
                    - ISNULL(Vpo.QtVpoFat, 0)
                    - ISNULL((
                        SELECT -SUM(QtReserva * (TpResSin - 2))
                        FROM Stik_Pedido_Reserva
                        WHERE CdVpo = Vpo.CdVpo
                    ), 0)
                    + ISNULL(FatDoc.Qt, 0)
            FROM Stik_ProgTinturaria T WITH (NOLOCK)
            JOIN TBVpo Vpo WITH (NOLOCK)
                ON Vpo.CdVpo = T.CdVpo
            JOIN TbVpd Vpd WITH (NOLOCK)
                ON Vpd.CdVpd = Vpo.CdVpd
            LEFT JOIN (
                SELECT
                    Rco.CdVpo,
                    Qt = CASE
                        WHEN SUM(Rco.QtRcoExp) > 0 THEN SUM(Rco.QtRcoExp)
                        WHEN SUM(Rco.QtRcoExp) = 0 THEN SUM(Rco.QtRco)
                        ELSE SUM(Rco.QtRco)
                    END
                FROM TbRco Rco WITH (NOLOCK)
                LEFT JOIN TbVpo Vpo WITH (NOLOCK)
                    ON Vpo.CdVpo = Rco.CdVpo
                   AND Rco.TpRcoSta <> 3
                   AND Rco.CdFin = 28
                GROUP BY Rco.CdVpo
            ) FatDoc
                ON FatDoc.CdVpo = Vpo.CdVpo
            WHERE
                ISNULL(Vpo.QtVpo, 0)
                - ISNULL(Vpo.QtVpoFat, 0)
                - ISNULL((
                    SELECT -SUM(QtReserva * (TpResSin - 2))
                    FROM Stik_Pedido_Reserva
                    WHERE CdVpo = Vpo.CdVpo
                ), 0)
                + ISNULL(FatDoc.Qt, 0) > 0
                AND Vpo.CdObj = ?
                AND Vpo.QtVpo - Vpo.QtVpoFat > 0
                AND Vpo.TpVpoSta = 1
                AND (
                    ISNULL(?, 0) = 0
                    OR ISNULL(Vpo.CdLot, 0) = ISNULL(?, 0)
                )
            ORDER BY Vpd.DtVpd, Vpd.CdVpd
        """

        cursor.execute(sql, (cod_sku, detalhe, detalhe))
        row = cursor.fetchone()

        if not row:
            return jsonify({
                "success": False,
                "message": "Nenhuma NrOrdem encontrada para o item.",
            }), 404

        return jsonify({
            "success": True,
            "CdVpo": int(row[0] or 0),
            "CdVpd": int(row[1] or 0),
            "CdObj": int(row[2] or 0),
            "CdLot": int(row[3] or 0),
            "CdUnd": int(row[4] or 0),
            "NrOrdem": int(row[5] or 0),
            "Saldo": float(row[6] or 0),
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: AUDITAR PALETE
# Ajusta metros e embalagem com origem AUDITORIA
# ===================================================================
@wms_movimentos_bp.route('/consulta/wms/palete/auditar', methods=['POST'])
def auditar_palete():
    connection = None
    try:
        data = request.get_json() or {}

        endereco = (data.get('endereco') or '').strip().upper()
        cd_usr = data.get('cd_usr')
        cd_usr = int(cd_usr) if cd_usr not in (None, '', 0, '0') else None
        observacao_base = (data.get('observacao') or '').strip()
        itens = data.get('itens') or []

        if not endereco:
            return jsonify({"error": "Campo obrigatório: endereco"}), 400

        if not isinstance(itens, list) or len(itens) == 0:
            return jsonify({"error": "Campo obrigatório: itens"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        base_url = request.host_url.rstrip('/')

        def _to_int(value, default=0):
            try:
                if value is None:
                    return default
                if isinstance(value, str):
                    value = value.strip().replace(',', '.')
                return int(float(value))
            except Exception:
                return default

        def _to_float(value, default=0.0):
            try:
                if value is None:
                    return default
                if isinstance(value, str):
                    value = value.strip().replace(',', '.')
                return float(value)
            except Exception:
                return default

        def _emb_dict(raw):
            raw = raw or {}
            return {
                'P': _to_int(raw.get('P') or raw.get('p')),
                'G': _to_int(raw.get('G') or raw.get('g')),
                'ENFE': _to_int(raw.get('ENFE') or raw.get('enfe')),
                'ENFR': _to_int(raw.get('ENFR') or raw.get('enfr')),
            }

        def _post_json(path, payload, timeout=20):
            resp = requests.post(
                f'{base_url}{path}',
                json=payload,
                timeout=timeout,
            )
            if resp.status_code < 200 or resp.status_code >= 300:
                raise Exception(f'Erro {resp.status_code} em {path}: {resp.text}')
            try:
                return resp.json()
            except Exception:
                return {"success": True}

        resultados = []

        for item in itens:
            cod_sku = _to_int(item.get('cod_sku'))
            detalhe = _to_int(item.get('detalhe'))
            qt_sistema = _to_float(item.get('qt_sistema'))
            qt_fisica = _to_float(item.get('qt_fisica'))

            if cod_sku <= 0:
                return jsonify({"error": "Cada item deve informar cod_sku"}), 400

            emb_sistema = _emb_dict(item.get('emb_sistema'))
            emb_fisica = _emb_dict(item.get('emb_fisica'))

            obs_item = (
                f'Auditoria palete {endereco} | SKU {cod_sku} | Det {detalhe}'
            )
            if observacao_base:
                obs_item = f'{observacao_base} | {obs_item}'

            # -----------------------------------------------------------
            # AJUSTE DE METROS
            # -----------------------------------------------------------
            delta_metros = round(qt_fisica - qt_sistema, 3)

            if delta_metros != 0:
                tp_mov = 1 if delta_metros > 0 else 2
                qt_movida = abs(delta_metros)

                _post_json('/consulta/wms/movimentar', {
                    'Endereco': endereco,
                    'CodSKU': cod_sku,
                    'TpMov': tp_mov,
                    'QtMovida': qt_movida,
                    'Detalhe': detalhe,
                    'Origem': 'AUDITORIA',
                    'Observacao': obs_item,
                })

            # -----------------------------------------------------------
            # AJUSTE DE EMBALAGEM
            # -----------------------------------------------------------
            emb_resultado = {}

            for chave in ['P', 'G', 'ENFE', 'ENFR']:
                delta_emb = emb_fisica[chave] - emb_sistema[chave]
                emb_resultado[chave] = delta_emb

                if delta_emb == 0:
                    continue

                payload_emb = {
                    'endereco': endereco,
                    'cod_sku': cod_sku,
                    'detalhe': detalhe,
                    'artigo': '',
                    'quantidade': qt_fisica,
                    'qt_caixa_p': abs(delta_emb) if chave == 'P' else 0,
                    'qt_caixa_g': abs(delta_emb) if chave == 'G' else 0,
                    'qt_enfestado': abs(delta_emb) if chave == 'ENFE' else 0,
                    'qt_enfraldado': abs(delta_emb) if chave == 'ENFR' else 0,
                    'cd_usr': cd_usr,
                    'origem': 'AUDITORIA',
                    'observacao': obs_item,
                }

                if delta_emb > 0:
                    # físico maior que sistema -> entrada de embalagem
                    _post_json('/consulta/wms/alocar_embalagem', payload_emb)
                else:
                    # físico menor que sistema -> saída de embalagem
                    _post_json('/consulta/wms/saida_embalagem', payload_emb)

            resultados.append({
                'cod_sku': cod_sku,
                'detalhe': detalhe,
                'qt_sistema': qt_sistema,
                'qt_fisica': qt_fisica,
                'delta_metros': delta_metros,
                'delta_embalagem': emb_resultado,
            })

        return jsonify({
            'success': True,
            'message': f'Auditoria do palete {endereco} concluída.',
            'endereco': endereco,
            'itens_processados': len(resultados),
            'resultados': resultados,
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()



