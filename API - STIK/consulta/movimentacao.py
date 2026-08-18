from dateutil import parser 
from flask import Blueprint, jsonify, request
from database.server import create_connection, create_connection_tinturaria
from decimal import Decimal
import uuid
import datetime
import pyodbc

movimentacao_bp = Blueprint('movimentacao', __name__)

@movimentacao_bp.route('/consulta/movimentacao', methods=['GET', 'POST', 'PUT'])
def gerenciar_movimentacao():
    connection = None
    try:
        connection = create_connection()
        cursor = connection.cursor()

        if request.method == 'POST':
            data = request.get_json()
            if not data:
                return jsonify({"error": "Dados JSON não fornecidos ou invalidos"}), 400

            # Campos de STRING
            Artigo = data.get('Artigo', '')
            Cor = data.get('Cor', '')
            Conferente = data.get('Conferente', '')
            Turno = data.get('Turno', '')
            Localizacao = data.get('Localizacao', '')
            NumCorte = data.get('NumCorte', '')
            Caixa = data.get('Caixa', '')  # Correção: Extração do campo Caixa

            # Campos NUMERICOS
            try:
                NrOrdem = int(data.get('NrOrdem', 0))
            except (ValueError, TypeError):
                return jsonify({"error": "NrOrdem invalido ou ausente"}), 400

            try:
                Quantidade = int(data.get('Quantidade', 0))
            except (ValueError, TypeError):
                Quantidade = 0

            Peso = float(data.get('Peso', 0.0)) if data.get('Peso') is not None else 0.0
            Metros = float(data.get('Metros', 0.0)) if data.get('Metros') is not None else 0.0
            VolumeProg = float(data.get('VolumeProg', 0.0)) if data.get('VolumeProg') is not None else 0.0
            
            DataEntrada = data.get('DataEntrada')

            # Validação obrigatória
            if not all([NrOrdem > 0, Artigo, Cor, Conferente, Turno, Localizacao, DataEntrada]):
                return jsonify({"error": "NrOrdem, Artigo, Cor, Conferente, Turno, Localizacao e DataEntrada sao obrigatorios"}), 400

            # Execução SQL
            insert_sql = """
                INSERT INTO Pedidos (
                    NrOrdem, Artigo, Cor, Quantidade, Peso, Conferente, Turno, Metros, 
                    NumCorte, VolumeProg, Localizacao, DataEntrada, Caixa  
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)  
            """
            cursor.execute(
                insert_sql,
                (NrOrdem, Artigo, Cor, Quantidade, Peso, Conferente, Turno, Metros,
                 NumCorte, VolumeProg, Localizacao, DataEntrada, Caixa) 
            )
            connection.commit()
            return jsonify({"message": "Registro de Movimentacao criado com sucesso!"}), 201

        elif request.method == 'PUT':
            
            data = request.get_json()
            NrOrdem = data.get('NrOrdem')
            LocalizacaoNova = data.get('Localizacao')
            Conferente = data.get('Conferente')
            DataMov_str = data.get('DataSaida')
            TipoMovimentacao = data.get('TipoMovimentacao')
            LocalizacaoAnterior = data.get('LocalizacaoAnterior')
            ID_Registro = data.get('ID') or data.get('Id') or data.get('RegistroID')

            try:
                ID_Registro = int(ID_Registro) if ID_Registro not in (None, '') else None
            except (ValueError, TypeError):
                return jsonify({"error": "ID do registro invalido"}), 400
            
            MetrosMovidos = float(data.get('MetrosMovidos', 0.0)) if data.get('MetrosMovidos') is not None else 0.0

            campos_obrigatorios = [NrOrdem, LocalizacaoNova, Conferente, DataMov_str, TipoMovimentacao, LocalizacaoAnterior]
            if any(campo is None for campo in campos_obrigatorios):
                return jsonify({"error": "Campos obrigatorios para PUT ausentes"}), 400

            try:
                DataMov = parser.isoparse(DataMov_str)
            except Exception:
                return jsonify({"error": f"Data invalida: {DataMov_str}"}), 400

            # Busca o registro ATIVO e ESPECIFICO (com DataSaida IS NULL) que está sendo movido
            if ID_Registro:
                fetch_active_record_sql = """
                    SELECT 
                        ID, Artigo, Cor, Quantidade, Peso, Turno, Metros, NumCorte, VolumeProg, Localizacao, Caixa  
                    FROM Pedidos
                    WHERE ID = ? AND NrOrdem = ? AND Localizacao = ? AND DataSaida IS NULL
                """
                cursor.execute(fetch_active_record_sql, (ID_Registro, NrOrdem, LocalizacaoAnterior))
            else:
                fetch_active_record_sql = """
                    SELECT 
                        ID, Artigo, Cor, Quantidade, Peso, Turno, Metros, NumCorte, VolumeProg, Localizacao, Caixa  
                    FROM Pedidos
                    WHERE NrOrdem = ? AND Localizacao = ? AND DataSaida IS NULL
                """
                cursor.execute(fetch_active_record_sql, (NrOrdem, LocalizacaoAnterior))
            detalhes = cursor.fetchone()

            if not detalhes:
                return jsonify({"error": f"Nenhum registro ativo encontrado para OP {NrOrdem} em {LocalizacaoAnterior}"}), 404

            # Desempacota os detalhes do registro ATIVO
            ID_Origem, Artigo, Cor, Quantidade, Peso, Turno, Metros, NumCorte, VolumeProg, LocalizacaoAtual, Caixa = detalhes  
            
            LocalizacaoAnterior_DB = LocalizacaoAtual
            quantidade_hist = 0.0
            metros_a_mover = Metros 

            # --- LOGICA DE MOVIMENTACAO CONDICIONAL ---

            if TipoMovimentacao == 'PARCIAL' and MetrosMovidos > 0.0:
                
                if MetrosMovidos >= Metros:
                    return jsonify({"error": "A quantidade movida (MetrosMovidos) nao pode ser maior ou igual ao saldo atual."}), 400
                    
                # 1. ATUALIZACAO DO SALDO ORIGINAL (Origem)
                update_origem_sql = """
                    UPDATE Pedidos
                    SET 
                        Metros = Metros - ?
                    WHERE ID = ?
                """
                cursor.execute(update_origem_sql, (MetrosMovidos, ID_Origem))
                
                # 2. INSERCAO DO NOVO REGISTRO (Destino) - CRIACAO
                insert_destino_sql = """
                    INSERT INTO Pedidos (
                        NrOrdem, Artigo, Cor, Quantidade, Peso, Conferente, Turno, Metros,
                        NumCorte, VolumeProg, Localizacao, DataEntrada, Caixa 
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)  
                """
                cursor.execute(insert_destino_sql, (
                    NrOrdem, Artigo, Cor, Quantidade, Peso, Conferente, Turno, MetrosMovidos, 
                    NumCorte, VolumeProg, LocalizacaoNova, DataMov, Caixa  
                ))
                
                quantidade_hist = MetrosMovidos 

            else: # TipoMovimentacao é 'NORMAL' ou COMPLETA
                
                # PASSO 1: Tenta CONSOLIDAR o estoque na Localizacao de Destino
                fetch_target_sql = """
                    SELECT ID, Metros 
                    FROM Pedidos
                    WHERE NrOrdem = ? AND Artigo = ? AND Cor = ? AND Localizacao = ? AND DataSaida IS NULL
                """
                cursor.execute(fetch_target_sql, (NrOrdem, Artigo, Cor, LocalizacaoNova))
                registro_destino = cursor.fetchone()

                if registro_destino:
                    # Se encontrou um registro ativo: CONSOLIDACAO (SOMA)
                    ID_Destino, Metros_Destino_Atual = registro_destino
                    
                    update_destino_sql = """
                        UPDATE Pedidos
                        SET Metros = Metros + ?
                        WHERE ID = ?
                    """
                    cursor.execute(update_destino_sql, (metros_a_mover, ID_Destino))
                    
                    # 2. FECHA REGISTRO ORIGINAL (Origem)
                    update_origem_sql = """
                        UPDATE Pedidos
                        SET DataSaida = ?
                        WHERE ID = ?
                    """
                    cursor.execute(update_origem_sql, (DataMov, ID_Origem))
                    
                    quantidade_hist = metros_a_mover 
                    
                else: 
                    # Se NAO encontrou um registro ativo: CRIA NOVO REGISTRO

                    # 1. FECHA REGISTRO ORIGINAL (Origem)
                    update_sql = """
                        UPDATE Pedidos
                        SET DataSaida = ?
                        WHERE ID = ?
                    """
                    cursor.execute(update_sql, (DataMov, ID_Origem))

                    # 2. CRIA NOVO REGISTRO (Destino)
                    if LocalizacaoNova == 'Expedição':
                        insert_sql = """
                            INSERT INTO Pedidos (
                                NrOrdem, Artigo, Cor, Quantidade, Peso, Conferente, Turno, Metros,
                                NumCorte, VolumeProg, Localizacao, DataEntrada, DataSaida, Caixa  
                            )
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)  
                        """
                        cursor.execute(insert_sql, (
                            NrOrdem, Artigo, Cor, Quantidade, Peso, Conferente, Turno, Metros,
                            NumCorte, VolumeProg, LocalizacaoNova, DataMov, DataMov, Caixa  
                        ))
                    else:
                        insert_sql = """
                            INSERT INTO Pedidos (
                                NrOrdem, Artigo, Cor, Quantidade, Peso, Conferente, Turno, Metros,
                                NumCorte, VolumeProg, Localizacao, DataEntrada, Caixa  
                            )
                            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)  
                        """
                        cursor.execute(insert_sql, (
                            NrOrdem, Artigo, Cor, Quantidade, Peso, Conferente, Turno, Metros,
                            NumCorte, VolumeProg, LocalizacaoNova, DataMov, Caixa  
                        ))
                    
                    quantidade_hist = Metros
                
            # --- INSERCAO NO HISTORICO ---
            insert_hist_sql = """
                INSERT INTO HistoricoMovimentacoes (
                    NrOrdem, LocalizacaoDestino, DataMovimentacao, Conferente, TipoMovimentacao, LocalizacaoOrigem, QuantidadeMovida
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
            """
            cursor.execute(insert_hist_sql, (
                NrOrdem, LocalizacaoNova, DataMov, Conferente, TipoMovimentacao, LocalizacaoAnterior_DB, quantidade_hist
            ))

            connection.commit()
            return jsonify({"message": f"OP {NrOrdem} movida de {LocalizacaoAnterior_DB} para {LocalizacaoNova}. Tipo: {TipoMovimentacao}"}), 200

        else: # GET
            localizacao_filtro = request.args.get('localizacao')
            query = "SELECT * FROM Pedidos WHERE DataSaida IS NULL"
            params = []

            if localizacao_filtro == 'Expedição':
                query = "SELECT * FROM Pedidos WHERE Localizacao = ?"
                params = [localizacao_filtro]
            elif localizacao_filtro:
                query += " AND Localizacao = ?"
                params.append(localizacao_filtro)

            query += " ORDER BY ID DESC"
            cursor.execute(query, params)

            registros = []
            columns = [col[0] for col in cursor.description]
            for row in cursor.fetchall():
                item = dict(zip(columns, row))
                for key in ['DataEntrada', 'DataSaida']:
                    if item[key] and isinstance(item[key], datetime.datetime):
                        item[key] = item[key].isoformat() + 'Z'
                registros.append(item)

            return jsonify(registros)

    except pyodbc.Error as ex:
        sqlstate = ex.args[0]
        return jsonify({"error": f"Erro de Banco de Dados: {sqlstate}"}), 500

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

movimentacao_historico_bp = Blueprint('movimentacao_historico', __name__)

@movimentacao_historico_bp.route('/consulta/movimentacao_historico', methods=['GET'])
def buscar_historico():
    """Busca TODO o histórico de movimentações, IGNORANDO qualquer filtro de nrOrdem."""
    connection = None
    try:
        # A leitura de nrOrdem (request.args.get('nrOrdem')) AGORA É IGNORADA.
        
        connection = create_connection()
        cursor = connection.cursor()
        
        # A QUERY É MONTADA SEM O WHERE para buscar todos os registros
        query = """
            SELECT 
                ID,
                NrOrdem,
                LocalizacaoOrigem,
                LocalizacaoDestino,
                DataMovimentacao,
                Conferente,
                TipoMovimentacao
            FROM HistoricoMovimentacoes
            ORDER BY DataMovimentacao DESC
        """
        
        # Executa a query, que agora sempre busca TUDO
        cursor.execute(query)
        
        historico = []
        columns = [col[0] for col in cursor.description]
        
        for row in cursor.fetchall():
            item = dict(zip(columns, row))
            
            # Conversão de datetime
            if item.get('DataMovimentacao') and isinstance(item['DataMovimentacao'], datetime.datetime):
                item['DataMovimentacao'] = item['DataMovimentacao'].isoformat() + 'Z'
            
            historico.append(item)
        
        return jsonify(historico), 200
        
    except pyodbc.Error as ex:
        # ... (tratamento de erro)
        return jsonify({"error": f"Erro de Banco de Dados: {ex.args[0]}"}), 500
    
    except Exception as e:
        # ... (tratamento de erro)
        return jsonify({"error": str(e)}), 500
    
    finally:
        if connection:
            connection.close()


# CHECKIN TAMBORES

def _checkin_tambores_json_value(value):
    if isinstance(value, datetime.datetime):
        return value.isoformat()
    if isinstance(value, datetime.date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    if isinstance(value, uuid.UUID):
        return str(value)
    return value


def _checkin_tambores_row_to_dict(cursor, row):
    columns = [col[0] for col in cursor.description]
    return {
        column: _checkin_tambores_json_value(value)
        for column, value in zip(columns, row)
    }


def _buscar_checkin_tambores_por_idempotency_key(cursor, idempotency_key):
    if not idempotency_key:
        return None

    cursor.execute(
        """
        SELECT
            id_checkin_tambores,
            idempotency_key,
            quantidade_tambores,
            volume_total,
            checkin_inicial_em,
            checkin_final_em,
            status,
            criado_em,
            atualizado_em
        FROM dbo.checkin_tambores
        WHERE idempotency_key = ?
        """,
        (idempotency_key,)
    )
    row = cursor.fetchone()
    if not row:
        return None
    return _checkin_tambores_row_to_dict(cursor, row)


@movimentacao_bp.route('/consulta/wms/checkin-tambores', methods=['GET'])
def listar_checkin_tambores():
    connection = None
    try:
        status = (request.args.get('status') or '').strip().upper()
        limite_raw = request.args.get('limite', '100')

        try:
            limite = int(limite_raw)
        except (ValueError, TypeError):
            limite = 100

        if limite <= 0:
            limite = 100
        if limite > 500:
            limite = 500

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        params = []
        where = ''
        if status:
            if status not in ('EM_ANDAMENTO', 'FINALIZADO'):
                return jsonify({"error": "Status invalido"}), 400
            where = 'WHERE status = ?'
            params.append(status)

        query = f"""
            SELECT TOP ({limite})
                id_checkin_tambores,
                idempotency_key,
                quantidade_tambores,
                volume_total,
                checkin_inicial_em,
                checkin_final_em,
                status,
                criado_em,
                atualizado_em
            FROM dbo.checkin_tambores
            {where}
            ORDER BY checkin_inicial_em DESC, id_checkin_tambores DESC
        """
        cursor.execute(query, params)

        registros = [
            _checkin_tambores_row_to_dict(cursor, row)
            for row in cursor.fetchall()
        ]
        return jsonify(registros), 200

    except pyodbc.Error as ex:
        return jsonify({"error": f"Erro de Banco de Dados: {ex.args[0]}"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@movimentacao_bp.route('/consulta/wms/checkin-tambores/aberto', methods=['GET'])
def buscar_checkin_tambores_aberto():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        cursor.execute(
            """
            SELECT TOP 1
                id_checkin_tambores,
                idempotency_key,
                quantidade_tambores,
                volume_total,
                checkin_inicial_em,
                checkin_final_em,
                status,
                criado_em,
                atualizado_em
            FROM dbo.checkin_tambores
            WHERE status = 'EM_ANDAMENTO'
            ORDER BY checkin_inicial_em DESC, id_checkin_tambores DESC
            """
        )
        row = cursor.fetchone()
        if not row:
            return jsonify(None), 200

        return jsonify(_checkin_tambores_row_to_dict(cursor, row)), 200

    except pyodbc.Error as ex:
        return jsonify({"error": f"Erro de Banco de Dados: {ex.args[0]}"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@movimentacao_bp.route('/consulta/wms/checkin-tambores/inicial', methods=['POST'])
def criar_checkin_tambores_inicial():
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON nao fornecidos ou invalidos"}), 400

        itens = data.get('itens') or []
        if not isinstance(itens, list):
            return jsonify({"error": "itens deve ser uma lista"}), 400
        if len(itens) <= 0:
            return jsonify({"error": "Bipe pelo menos um tambor antes do check-in"}), 400

        itens_por_grupo = {}

        for index, item in enumerate(itens, start=1):
            if not isinstance(item, dict):
                return jsonify({"error": f"Item {index} invalido"}), 400

            codigo_tambor = str(item.get('codigo_tambor') or '').strip()
            ordem_producao = str(item.get('ordem_producao') or item.get('Ordem') or '').strip()
            artigo = str(item.get('artigo') or item.get('Artigo') or '').strip()

            try:
                volume = float(item.get('volume', item.get('VolumeProg', 0)) or 0)
            except (ValueError, TypeError):
                return jsonify({"error": f"volume invalido no item {index}"}), 400

            try:
                quantidade_item = int(item.get('quantidade_tambores', 1) or 1)
            except (ValueError, TypeError):
                return jsonify({"error": f"quantidade_tambores invalida no item {index}"}), 400

            if not codigo_tambor:
                return jsonify({"error": f"codigo_tambor e obrigatorio no item {index}"}), 400
            if not ordem_producao:
                return jsonify({"error": f"ordem_producao e obrigatoria no item {index}"}), 400
            if not artigo:
                return jsonify({"error": f"artigo e obrigatorio no item {index}"}), 400
            if volume < 0:
                return jsonify({"error": f"volume nao pode ser negativo no item {index}"}), 400
            if quantidade_item <= 0:
                return jsonify({"error": f"quantidade_tambores deve ser maior que zero no item {index}"}), 400

            chave = (ordem_producao, artigo)

            if chave in itens_por_grupo:
                itens_por_grupo[chave]["quantidade_tambores"] += quantidade_item
                itens_por_grupo[chave]["codigo_tambor"] = codigo_tambor
            else:
                itens_por_grupo[chave] = {
                    "codigo_tambor": codigo_tambor,
                    "ordem_producao": ordem_producao,
                    "artigo": artigo,
                    "volume": volume,
                    "quantidade_tambores": quantidade_item,
                }

        itens_normalizados = list(itens_por_grupo.values())
        quantidade_total_itens = sum(item["quantidade_tambores"] for item in itens_normalizados)
        volume_total_itens = sum(item["volume"] for item in itens_normalizados)

        try:
            quantidade_tambores = int(data.get('quantidade_tambores', quantidade_total_itens))
        except (ValueError, TypeError):
            return jsonify({"error": "quantidade_tambores invalida"}), 400

        if quantidade_tambores <= 0:
            return jsonify({"error": "quantidade_tambores deve ser maior que zero"}), 400
        if quantidade_tambores != quantidade_total_itens:
            return jsonify({
                "error": "quantidade_tambores deve ser igual ao total de tambores bipados"
            }), 400

        volume_total = volume_total_itens

        idempotency_key = (
            data.get('idempotency_key')
            or request.headers.get('Idempotency-Key')
            or str(uuid.uuid4())
        )

        try:
            idempotency_key = str(uuid.UUID(str(idempotency_key).strip()))
        except (ValueError, TypeError):
            return jsonify({"error": "idempotency_key invalida"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        existente = _buscar_checkin_tambores_por_idempotency_key(
            cursor,
            idempotency_key,
        )
        if existente:
            return jsonify(existente), 200

        cursor.execute(
            """
            SELECT TOP 1
                id_checkin_tambores,
                idempotency_key,
                quantidade_tambores,
                volume_total,
                checkin_inicial_em,
                checkin_final_em,
                status,
                criado_em,
                atualizado_em
            FROM dbo.checkin_tambores
            WHERE status = 'EM_ANDAMENTO'
            ORDER BY checkin_inicial_em DESC, id_checkin_tambores DESC
            """
        )
        aberto = cursor.fetchone()
        if aberto:
            return jsonify({
                "error": "Ja existe um check-in em andamento. Finalize antes de iniciar outro.",
                "registro": _checkin_tambores_row_to_dict(cursor, aberto),
            }), 409

        cursor.execute(
            """
            INSERT INTO dbo.checkin_tambores (
                idempotency_key,
                quantidade_tambores,
                volume_total,
                checkin_inicial_em,
                status,
                criado_em
            )
            OUTPUT
                INSERTED.id_checkin_tambores,
                INSERTED.idempotency_key,
                INSERTED.quantidade_tambores,
                INSERTED.volume_total,
                INSERTED.checkin_inicial_em,
                INSERTED.checkin_final_em,
                INSERTED.status,
                INSERTED.criado_em,
                INSERTED.atualizado_em
            VALUES (
                ?,
                ?,
                ?,
                SYSDATETIME(),
                'EM_ANDAMENTO',
                SYSDATETIME()
            )
            """,
            (idempotency_key, quantidade_tambores, volume_total)
        )
        row = cursor.fetchone()
        registro = _checkin_tambores_row_to_dict(cursor, row)
        id_checkin_tambores = registro["id_checkin_tambores"]

        for item in itens_normalizados:
            cursor.execute(
                """
                UPDATE dbo.checkin_tambores_itens
                SET
                    quantidade_tambores = quantidade_tambores + ?,
                    bipado_em = SYSDATETIME()
                WHERE
                    id_checkin_tambores = ?
                    AND ordem_producao = ?
                    AND artigo = ?
                """,
                (
                    item["quantidade_tambores"],
                    id_checkin_tambores,
                    item["ordem_producao"],
                    item["artigo"],
                )
            )

            if cursor.rowcount == 0:
                cursor.execute(
                    """
                    INSERT INTO dbo.checkin_tambores_itens (
                        id_checkin_tambores,
                        codigo_tambor,
                        volume,
                        ordem_producao,
                        artigo,
                        quantidade_tambores
                    )
                    VALUES (?, ?, ?, ?, ?, ?)
                    """,
                    (
                        id_checkin_tambores,
                        item["codigo_tambor"],
                        item["volume"],
                        item["ordem_producao"],
                        item["artigo"],
                        item["quantidade_tambores"],
                    )
                )

        registro_atualizado = _recalcular_totais_checkin_tambores(
            cursor,
            id_checkin_tambores,
        )
        connection.commit()

        return jsonify(registro_atualizado), 201

    except pyodbc.IntegrityError as ex:
        if connection:
            connection.rollback()
        return jsonify({
            "error": "Dados duplicados ou violacao de restricao no check-in.",
            "details": str(ex)
        }), 409
    except pyodbc.Error as ex:
        if connection:
            connection.rollback()
        return jsonify({
            "error": f"Erro de Banco de Dados: {ex.args[0]}",
            "details": str(ex)
        }), 500
    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@movimentacao_bp.route('/consulta/wms/checkin-tambores/<int:id_checkin_tambores>/final', methods=['POST', 'PUT'])
def finalizar_checkin_tambores(id_checkin_tambores):
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        cursor.execute(
            """
            UPDATE dbo.checkin_tambores
            SET
                checkin_final_em = SYSDATETIME(),
                status = 'FINALIZADO',
                atualizado_em = SYSDATETIME()
            OUTPUT
                INSERTED.id_checkin_tambores,
                INSERTED.idempotency_key,
                INSERTED.quantidade_tambores,
                INSERTED.volume_total,
                INSERTED.checkin_inicial_em,
                INSERTED.checkin_final_em,
                INSERTED.status,
                INSERTED.criado_em,
                INSERTED.atualizado_em
            WHERE
                id_checkin_tambores = ?
                AND status = 'EM_ANDAMENTO'
                AND checkin_final_em IS NULL
            """,
            (id_checkin_tambores,)
        )
        row = cursor.fetchone()

        if not row:
            connection.rollback()
            cursor.execute(
                """
                SELECT
                    id_checkin_tambores,
                    idempotency_key,
                    quantidade_tambores,
                    volume_total,
                    checkin_inicial_em,
                    checkin_final_em,
                    status,
                    criado_em,
                    atualizado_em
                FROM dbo.checkin_tambores
                WHERE id_checkin_tambores = ?
                """,
                (id_checkin_tambores,)
            )
            existente = cursor.fetchone()
            if not existente:
                return jsonify({"error": "Check-in nao encontrado"}), 404
            return jsonify({
                "error": "Check-in ja esta finalizado ou nao esta em andamento",
                "registro": _checkin_tambores_row_to_dict(cursor, existente),
            }), 409

        registro = _checkin_tambores_row_to_dict(cursor, row)
        connection.commit()
        return jsonify(registro), 200

    except pyodbc.Error as ex:
        if connection:
            connection.rollback()
        return jsonify({"error": f"Erro de Banco de Dados: {ex.args[0]}"}), 500
    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()

# ----------------------------------------------------------------------
# Check-in Tambores - Itens bipados
# ----------------------------------------------------------------------

def _checkin_tambores_item_row_to_dict(cursor, row):
    if not row:
        return None
    columns = [col[0] for col in cursor.description]
    return {
        column: _checkin_tambores_json_value(value)
        for column, value in zip(columns, row)
    }


def _buscar_checkin_tambores_por_id(cursor, id_checkin_tambores):
    cursor.execute(
        """
        SELECT
            id_checkin_tambores,
            idempotency_key,
            quantidade_tambores,
            volume_total,
            checkin_inicial_em,
            checkin_final_em,
            status,
            criado_em,
            atualizado_em
        FROM dbo.checkin_tambores
        WHERE id_checkin_tambores = ?
        """,
        (id_checkin_tambores,)
    )
    row = cursor.fetchone()
    if not row:
        return None
    return _checkin_tambores_row_to_dict(cursor, row)


def _recalcular_totais_checkin_tambores(cursor, id_checkin_tambores):
    cursor.execute(
        """
        UPDATE c
        SET
            quantidade_tambores = x.quantidade_tambores,
            volume_total = x.volume_total,
            atualizado_em = SYSDATETIME()
        OUTPUT
            INSERTED.id_checkin_tambores,
            INSERTED.idempotency_key,
            INSERTED.quantidade_tambores,
            INSERTED.volume_total,
            INSERTED.checkin_inicial_em,
            INSERTED.checkin_final_em,
            INSERTED.status,
            INSERTED.criado_em,
            INSERTED.atualizado_em
        FROM dbo.checkin_tambores c
        CROSS APPLY (
            SELECT
                ISNULL(SUM(i.quantidade_tambores), 0) AS quantidade_tambores,
                ISNULL(SUM(i.volume), 0) AS volume_total
            FROM dbo.checkin_tambores_itens i
            WHERE i.id_checkin_tambores = c.id_checkin_tambores
        ) x
        WHERE c.id_checkin_tambores = ?
        """,
        (id_checkin_tambores,)
    )
    row = cursor.fetchone()
    if not row:
        return None
    return _checkin_tambores_row_to_dict(cursor, row)

@movimentacao_bp.route('/consulta/wms/checkin-tambores/<int:id_checkin_tambores>/itens', methods=['GET'])
def listar_checkin_tambores_itens(id_checkin_tambores):
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        checkin = _buscar_checkin_tambores_por_id(cursor, id_checkin_tambores)
        if not checkin:
            return jsonify({"error": "Check-in nao encontrado"}), 404

        cursor.execute(
            """
            SELECT
                id_checkin_tambores_item,
                id_checkin_tambores,
                codigo_tambor,
                volume,
                bipado_em,
                ordem_producao,
                artigo,
                quantidade_tambores
            FROM dbo.checkin_tambores_itens
            WHERE id_checkin_tambores = ?
            ORDER BY bipado_em ASC, id_checkin_tambores_item ASC
            """,
            (id_checkin_tambores,)
        )

        itens = [
            _checkin_tambores_item_row_to_dict(cursor, row)
            for row in cursor.fetchall()
        ]
        return jsonify({
            "checkin": checkin,
            "itens": itens,
        }), 200

    except pyodbc.Error as ex:
        return jsonify({"error": f"Erro de Banco de Dados: {ex.args[0]}"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@movimentacao_bp.route('/consulta/wms/checkin-tambores/<int:id_checkin_tambores>/itens', methods=['POST'])
def adicionar_checkin_tambores_item(id_checkin_tambores):
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON nao fornecidos ou invalidos"}), 400

        codigo_tambor = str(data.get('codigo_tambor') or '').strip()
        ordem_producao = str(data.get('ordem_producao') or data.get('Ordem') or '').strip()
        artigo = str(data.get('artigo') or data.get('Artigo') or '').strip()

        try:
            volume = float(data.get('volume', data.get('VolumeProg', 0)) or 0)
        except (ValueError, TypeError):
            return jsonify({"error": "volume invalido"}), 400

        try:
            quantidade_item = int(data.get('quantidade_tambores', 1) or 1)
        except (ValueError, TypeError):
            return jsonify({"error": "quantidade_tambores invalida"}), 400

        if not codigo_tambor:
            return jsonify({"error": "codigo_tambor e obrigatorio"}), 400
        if not ordem_producao:
            return jsonify({"error": "ordem_producao e obrigatoria"}), 400
        if not artigo:
            return jsonify({"error": "artigo e obrigatorio"}), 400
        if volume < 0:
            return jsonify({"error": "volume nao pode ser negativo"}), 400
        if quantidade_item <= 0:
            return jsonify({"error": "quantidade_tambores deve ser maior que zero"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        checkin = _buscar_checkin_tambores_por_id(cursor, id_checkin_tambores)
        if not checkin:
            return jsonify({"error": "Check-in nao encontrado"}), 404
        if checkin.get('status') != 'EM_ANDAMENTO':
            return jsonify({"error": "Nao e possivel adicionar tambor em check-in finalizado"}), 409

        cursor.execute(
            """
            UPDATE dbo.checkin_tambores_itens
            SET
                quantidade_tambores = quantidade_tambores + ?,
                bipado_em = SYSDATETIME()
            WHERE
                id_checkin_tambores = ?
                AND ordem_producao = ?
                AND artigo = ?
            """,
            (
                quantidade_item,
                id_checkin_tambores,
                ordem_producao,
                artigo,
            )
        )

        if cursor.rowcount == 0:
            cursor.execute(
                """
                INSERT INTO dbo.checkin_tambores_itens (
                    id_checkin_tambores,
                    codigo_tambor,
                    volume,
                    ordem_producao,
                    artigo,
                    quantidade_tambores
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    id_checkin_tambores,
                    codigo_tambor,
                    volume,
                    ordem_producao,
                    artigo,
                    quantidade_item,
                )
            )

        cursor.execute(
            """
            SELECT TOP 1
                id_checkin_tambores_item,
                id_checkin_tambores,
                codigo_tambor,
                volume,
                bipado_em,
                ordem_producao,
                artigo,
                quantidade_tambores
            FROM dbo.checkin_tambores_itens
            WHERE
                id_checkin_tambores = ?
                AND ordem_producao = ?
                AND artigo = ?
            """,
            (id_checkin_tambores, ordem_producao, artigo)
        )
        item_row = cursor.fetchone()
        item = _checkin_tambores_item_row_to_dict(cursor, item_row)

        checkin_atualizado = _recalcular_totais_checkin_tambores(
            cursor,
            id_checkin_tambores,
        )

        connection.commit()
        return jsonify({
            "item": item,
            "checkin": checkin_atualizado,
        }), 201

    except pyodbc.IntegrityError as ex:
        if connection:
            connection.rollback()
        return jsonify({
            "error": "Dados duplicados ou violacao de restricao no check-in.",
            "details": str(ex),
        }), 409
    except pyodbc.Error as ex:
        if connection:
            connection.rollback()
        return jsonify({"error": f"Erro de Banco de Dados: {ex.args[0]}"}), 500
    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@movimentacao_bp.route('/consulta/wms/checkin-tambores/<int:id_checkin_tambores>/itens/resumo', methods=['GET'])
def listar_checkin_tambores_itens_resumo(id_checkin_tambores):
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        checkin = _buscar_checkin_tambores_por_id(cursor, id_checkin_tambores)
        if not checkin:
            return jsonify({"error": "Check-in nao encontrado"}), 404

        cursor.execute(
            """
            SELECT
                ordem_producao,
                artigo,
                quantidade_tambores = ISNULL(SUM(quantidade_tambores), 0),
                volume_total = ISNULL(SUM(volume), 0)
            FROM dbo.checkin_tambores_itens
            WHERE id_checkin_tambores = ?
            GROUP BY
                ordem_producao,
                artigo
            ORDER BY
                ordem_producao,
                artigo
            """,
            (id_checkin_tambores,)
        )

        resumo = [
            _checkin_tambores_item_row_to_dict(cursor, row)
            for row in cursor.fetchall()
        ]
        return jsonify({
            "checkin": checkin,
            "resumo": resumo,
        }), 200

    except pyodbc.Error as ex:
        return jsonify({"error": f"Erro de Banco de Dados: {ex.args[0]}"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()


@movimentacao_bp.route('/consulta/wms/checkin-tambores/<int:id_checkin_tambores>/itens/<int:id_checkin_tambores_item>', methods=['DELETE'])
def remover_checkin_tambores_item(id_checkin_tambores, id_checkin_tambores_item):
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        checkin = _buscar_checkin_tambores_por_id(cursor, id_checkin_tambores)
        if not checkin:
            return jsonify({"error": "Check-in nao encontrado"}), 404
        if checkin.get('status') != 'EM_ANDAMENTO':
            return jsonify({"error": "Nao e possivel remover tambor de check-in finalizado"}), 409

        cursor.execute(
            """
            DELETE FROM dbo.checkin_tambores_itens
            WHERE
                id_checkin_tambores = ?
                AND id_checkin_tambores_item = ?
            """,
            (id_checkin_tambores, id_checkin_tambores_item)
        )

        if cursor.rowcount <= 0:
            connection.rollback()
            return jsonify({"error": "Item nao encontrado"}), 404

        checkin_atualizado = _recalcular_totais_checkin_tambores(
            cursor,
            id_checkin_tambores,
        )
        connection.commit()
        return jsonify({
            "success": True,
            "checkin": checkin_atualizado,
        }), 200

    except pyodbc.Error as ex:
        if connection:
            connection.rollback()
        return jsonify({"error": f"Erro de Banco de Dados: {ex.args[0]}"}), 500
    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()
