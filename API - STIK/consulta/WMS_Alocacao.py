from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 
import datetime 

# Define o Blueprint
wms_alocacao_bp = Blueprint('wMS_alocacao', __name__)

@wms_alocacao_bp.route('/consulta/wms/gerar_alocacao', methods=['POST'])
def get_wms_alocacao():
    """
    Endpoint para alocação manual via QR Code.

    Tipo:
        1 = Entrada
        2 = Saída

    Se o campo Tipo não for enviado, assume automaticamente Entrada (1).

    Campos opcionais:
        QtMaxima
        Detalhe
    """
    connection = None
    try:
        data = request.get_json()

        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        # Campos principais
        endereco_completo = data.get('Endereco')
        cod_sku = data.get('CodSKU')
        quantidade = data.get('Quantidade')

        # Tipo agora é opcional (padrão entrada)
        tipo = int(data.get('Tipo', 1))

        qt_maxima = data.get('QtMaxima')
        detalhe = data.get('Detalhe')

        # Validação básica
        if not all([endereco_completo, cod_sku, quantidade]):
            return jsonify({
                "error": "Campos obrigatórios: Endereco, CodSKU, Quantidade"
            }), 400

        # Validação da quantidade
        try:
            quantidade = int(quantidade)
        except:
            return jsonify({"error": "Quantidade inválida"}), 400

        # Validação do tipo
        if tipo not in [1, 2]:
            return jsonify({
                "error": "Tipo deve ser 1 (entrada) ou 2 (saida)"
            }), 400

        # Ajusta sinal da quantidade
        if tipo == 1:
            quantidade = abs(quantidade)
        else:
            quantidade = -abs(quantidade)

        # --- PARSING DO ENDEREÇO (PA-L1-R1-E-P1) ---
        try:
            partes = endereco_completo.split('-')

            if len(partes) < 5:
                raise ValueError("Formato inválido. Esperado: PA-L1-R1-E-P1")

            nivel = int(partes[1].replace('L', ''))
            rua = int(partes[2].replace('R', ''))
            lado = partes[3]
            palete = int(partes[4].replace('P', ''))

        except Exception as parse_error:
            return jsonify({
                "error": f"Erro ao ler QR Code: {str(parse_error)}"
            }), 400

        # --- CONEXÃO E EXECUÇÃO ---
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_query = """
            EXEC dbo.sp_Stik_WMS_RegistrarAlocacao 
            @Endereco = ?, 
            @CodSKU = ?, 
            @Quantidade = ?,
            @Nivel = ?, 
            @Rua = ?, 
            @Lado = ?, 
            @Palete = ?,
            @QtMaxima = ?, 
            @Detalhe = ?;
        """

        cursor.execute(sql_query, (
            endereco_completo,
            cod_sku,
            quantidade,
            nivel,
            rua,
            lado,
            palete,
            qt_maxima,
            detalhe
        ))

        connection.commit()

        print(f"✅ Alocação: {endereco_completo} | SKU: {cod_sku} | Qtd: {quantidade}")

        return jsonify({
            "message": "Alocação registrada com sucesso!",
            "Endereco": endereco_completo,
            "DadosGravados": {
                "SKU": cod_sku,
                "Quantidade": quantidade,
                "Tipo": tipo,
                "QtMaxima": qt_maxima,
                "Detalhe": detalhe
            }
        }), 200

    except Exception as e:
        if connection:
            connection.rollback()

        print(f"❌ Erro ao alocar: {e}")

        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@wms_alocacao_bp.route('/consulta/wms/atualizar_qtmaxima', methods=['POST'])
def atualizar_qtmaxima():
    """
    Atualiza a QtMaxima do palete para TODAS as linhas do endereço.
    Campos obrigatórios: Endereco, QtMaxima
    """
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        endereco_completo = data.get('Endereco')
        qt_maxima = data.get('QtMaxima')

        if not all([endereco_completo, qt_maxima]):
            return jsonify({
                "error": "Campos 'Endereco' e 'QtMaxima' são obrigatórios."
            }), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_query = """
            UPDATE stik_WMS_ALOCACAO
            SET QtMaxima = ?, DataAtualizacao = GETDATE()
            WHERE Endereco = ?;
        """
        cursor.execute(sql_query, (qt_maxima, endereco_completo))

        if cursor.rowcount == 0:
            return jsonify({"error": "Nenhum registro encontrado para o endereço."}), 404

        connection.commit()

        return jsonify({
            "message": "QtMaxima atualizada com sucesso!",
            "Endereco": endereco_completo,
            "QtMaxima": qt_maxima
        }), 200

    except Exception as e:
        if connection: connection.rollback()
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@wms_alocacao_bp.route(
    '/consulta/wms/alocacao_atualizar/<string:endereco>/<int:cod_sku>/<int:detalhe>',
    methods=['PUT']
)
def atualizar_quantidade(endereco, cod_sku, detalhe):
    """
    Atualiza a quantidade de um SKU específico em um endereço e lote específico.
    Substitui totalmente o valor (não soma).
    """

    connection = None
    try:
        data = request.get_json()

        if not data or 'Quantidade' not in data:
            return jsonify({
                "error": "Campo 'Quantidade' é obrigatório."
            }), 400

        try:
            nova_qt = int(data.get('Quantidade'))
        except:
            return jsonify({
                "error": "Quantidade deve ser um número inteiro."
            }), 400

        if nova_qt < 0:
            return jsonify({
                "error": "Quantidade não pode ser negativa."
            }), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        # 🔎 Verifica existência
        sql_check = """
            SELECT QtAlocada
            FROM Stik_WMS_Alocacao
            WHERE Endereco = ?
              AND CodSKU = ?
              AND Detalhe = ?
        """
        cursor.execute(sql_check, (endereco, cod_sku, detalhe))
        registro = cursor.fetchone()

        if not registro:
            return jsonify({
                "error": "Registro não encontrado."
            }), 404

        quantidade_anterior = registro[0]

        # 🔄 Atualiza substituindo valor
        sql_update = """
            UPDATE Stik_WMS_Alocacao
            SET QtAlocada = ?,
                DataAtualizacao = GETDATE()
            WHERE Endereco = ?
              AND CodSKU = ?
              AND Detalhe = ?
        """

        cursor.execute(sql_update, (nova_qt, endereco, cod_sku, detalhe))
        connection.commit()

        return jsonify({
            "message": "Quantidade atualizada com sucesso.",
            "Endereco": endereco,
            "CodSKU": cod_sku,
            "Detalhe": detalhe,
            "QuantidadeAnterior": quantidade_anterior,
            "NovaQuantidade": nova_qt
        }), 200

    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@wms_alocacao_bp.route(
    '/consulta/wms/alocacao_deletar/<string:endereco>/<int:cod_sku>/<int:detalhe>',
    methods=['DELETE']
)
def deletar_material(endereco, cod_sku, detalhe):
    """
    Remove completamente um SKU específico de um endereço e lote específico.
    """

    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        # 🔎 Verifica existência
        sql_check = """
            SELECT ID
            FROM Stik_WMS_Alocacao
            WHERE Endereco = ?
              AND CodSKU = ?
              AND Detalhe = ?
        """
        cursor.execute(sql_check, (endereco, cod_sku, detalhe))
        registro = cursor.fetchone()

        if not registro:
            return jsonify({
                "error": "Registro não encontrado."
            }), 404

        # 🗑 Deleta
        sql_delete = """
            DELETE FROM Stik_WMS_Alocacao
            WHERE Endereco = ?
              AND CodSKU = ?
              AND Detalhe = ?
        """

        cursor.execute(sql_delete, (endereco, cod_sku, detalhe))
        connection.commit()

        return jsonify({
            "message": "Material removido com sucesso.",
            "Endereco": endereco,
            "CodSKU": cod_sku,
            "Detalhe": detalhe
        }), 200

    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


def _to_int_backend(value):
    if value is None:
        return 0
    try:
        if isinstance(value, str):
            value = value.strip().replace(',', '.')
        return int(float(value))
    except Exception:
        return 0


def _to_float_backend(value):
    if value is None:
        return 0.0
    try:
        if isinstance(value, str):
            value = value.strip().replace(',', '.')
        return float(value)
    except Exception:
        return 0.0


def _normalize_endereco_backend(value):
    return (value or '').strip().upper()


def _normalize_texto_backend(value):
    return (value or '').strip().upper()


def _format_data_backend(value):
    if value is None:
        return None
    try:
        return value.strftime('%d/%m/%Y %H:%M')
    except Exception:
        return str(value)


def _build_key_backend(endereco, cod_sku, detalhe_id):
    return f"{_normalize_endereco_backend(endereco)}|{_to_int_backend(cod_sku)}|{_to_int_backend(detalhe_id)}"


def _build_endereco_sku_key_backend(endereco, cod_sku):
    return f"{_normalize_endereco_backend(endereco)}|{_to_int_backend(cod_sku)}"


def _resolver_movimentos_da_entrada_backend(
    entry,
    key,
    movimentos_por_chave,
    movimentos_por_endereco_sku,
):
    exatos = movimentos_por_chave.get(key)
    if exatos:
        return exatos

    endereco_sku_key = _build_endereco_sku_key_backend(
        entry['Endereco'],
        entry['CodSKU'],
    )
    candidatos = movimentos_por_endereco_sku.get(endereco_sku_key)
    if not candidatos:
        return []

    if _to_int_backend(entry['CdLot']) > 0:
        detalhe_zero = [m for m in candidatos if _to_int_backend(m['DetalheId']) == 0]
        if detalhe_zero:
            return detalhe_zero
        return []

    detalhe_unico = {
        _to_int_backend(m['DetalheId'])
        for m in candidatos
        if _to_int_backend(m['DetalheId']) > 0
    }
    if len(detalhe_unico) == 1:
        return candidatos

    return []


def _filtrar_movimentos_apos_data_base_backend(movimentos, data_base):
    if data_base is None:
        return movimentos

    filtrados = []
    for mov in movimentos:
        data_mov = mov.get('DataMovimentoRaw')
        if data_mov is None:
            continue
        try:
            if data_mov > data_base:
                filtrados.append(mov)
        except Exception:
            continue
    return filtrados


def _somar_movimentos_backend(movimentos):
    entradas = 0.0
    retornos = 0.0
    saidas = 0.0

    for mov in movimentos:
        tp_mov = _to_int_backend(mov.get('TpMov'))
        qt_movida = _to_float_backend(mov.get('QtMovida'))
        if tp_mov == 1:
            entradas += qt_movida
        elif tp_mov == 3:
            retornos += qt_movida
        elif tp_mov == 2:
            saidas += qt_movida

    return {
        'entradas': entradas,
        'retornos': retornos,
        'saidas': saidas,
    }


def _carregar_alocacoes_base_backend(cursor, endereco=None):
    sql = """
        SELECT
            A.ID,
            A.Endereco,
            A.CodSKU,
            ISNULL(Obj.NmObj, 'Produto não identificado') AS Produto,
            ISNULL(A.QtAlocada, 0) AS QtAlocada,
            ISNULL(A.QtMaxima, 0) AS QtMaxima,
            ISNULL(A.Detalhe, 0) AS CdLot,
            ISNULL(Lot.NmLot, '') AS NmLot,
            ISNULL(E.QtCaixaP, 0) AS QtCaixaP,
            ISNULL(E.QtCaixaG, 0) AS QtCaixaG,
            ISNULL(E.QtEnfestado, 0) AS QtEnfestado,
            ISNULL(E.QtEnfraldado, 0) AS QtEnfraldado,
            A.DataAtualizacao
        FROM dbo.Stik_WMS_Alocacao A
        LEFT JOIN dbo.Stik_WMS_Alocacao_Embalagem E
            ON E.Endereco = A.Endereco
           AND E.CodSKU = A.CodSKU
           AND ISNULL(E.Detalhe, 0) = ISNULL(A.Detalhe, 0)
        LEFT JOIN dbo.TbObj Obj
            ON Obj.CdObj = A.CodSKU
        LEFT JOIN dbo.TbLot Lot
            ON Lot.CdLot = A.Detalhe
    """
    params = []

    if endereco:
        sql += " WHERE UPPER(LTRIM(RTRIM(A.Endereco))) = ?"
        params.append(_normalize_endereco_backend(endereco))

    sql += " ORDER BY A.DataAtualizacao DESC"

    cursor.execute(sql, params)
    colunas = [c[0] for c in cursor.description]
    return [dict(zip(colunas, row)) for row in cursor.fetchall()]


def _carregar_movimentos_base_backend(cursor, endereco=None):
    sql = """
        SELECT
            M.Endereco,
            M.CodSKU,
            ISNULL(M.Detalhe, 0) AS DetalheId,
            M.TpMov,
            ISNULL(M.QtMovida, 0) AS QtMovida,
            M.DataMovimento AS DataMovimentoRaw,
            ISNULL(Obj.NmObj, '') AS Produto,
            ISNULL(Lot.NmLot, '') AS NmLot
        FROM dbo.Stik_WMS_Movimento M WITH (NOLOCK)
        LEFT JOIN dbo.TbObj Obj
            ON Obj.CdObj = M.CodSKU
        LEFT JOIN dbo.TbLot Lot
            ON Lot.CdLot = M.Detalhe
        WHERE M.TpMov IN (1, 2, 3)
    """
    params = []

    if endereco:
        sql += " AND UPPER(LTRIM(RTRIM(M.Endereco))) = ?"
        params.append(_normalize_endereco_backend(endereco))

    cursor.execute(sql, params)
    colunas = [c[0] for c in cursor.description]
    return [dict(zip(colunas, row)) for row in cursor.fetchall()]


def _consolidar_alocacoes_com_movimentos_backend(cursor, endereco=None):
    alocacoes = _carregar_alocacoes_base_backend(cursor, endereco=endereco)
    movimentos = _carregar_movimentos_base_backend(cursor, endereco=endereco)

    movimentos_por_chave = {}
    movimentos_por_endereco_sku = {}
    info_por_chave = {}

    for mov in movimentos:
        mov_endereco = _normalize_endereco_backend(mov.get('Endereco'))
        cod_sku = _to_int_backend(mov.get('CodSKU'))
        detalhe_id = _to_int_backend(mov.get('DetalheId'))
        tp_mov = _to_int_backend(mov.get('TpMov'))

        if not mov_endereco or cod_sku <= 0:
            continue
        if tp_mov not in (1, 2, 3):
            continue

        key = _build_key_backend(mov_endereco, cod_sku, detalhe_id)
        endereco_sku_key = _build_endereco_sku_key_backend(mov_endereco, cod_sku)

        movimentos_por_chave.setdefault(key, []).append(mov)
        movimentos_por_endereco_sku.setdefault(endereco_sku_key, []).append(mov)

        if key not in info_por_chave:
            info_por_chave[key] = {
                'Endereco': mov_endereco,
                'CodSKU': cod_sku,
                'DetalheId': detalhe_id,
                'Produto': (mov.get('Produto') or '').strip(),
                'NmLot': (mov.get('NmLot') or '').strip(),
            }

    base_por_chave = {
        _build_key_backend(
            entry.get('Endereco'),
            entry.get('CodSKU'),
            entry.get('CdLot'),
        ): entry
        for entry in alocacoes
    }

    merged = []

    for entry in alocacoes:
        key = _build_key_backend(
            entry.get('Endereco'),
            entry.get('CodSKU'),
            entry.get('CdLot'),
        )

        movimentos_da_chave = _resolver_movimentos_da_entrada_backend(
            entry={
                'Endereco': entry.get('Endereco'),
                'CodSKU': entry.get('CodSKU'),
                'CdLot': entry.get('CdLot'),
            },
            key=key,
            movimentos_por_chave=movimentos_por_chave,
            movimentos_por_endereco_sku=movimentos_por_endereco_sku,
        )

        movimentos_ajuste = _filtrar_movimentos_apos_data_base_backend(
            movimentos_da_chave,
            entry.get('DataAtualizacao'),
        )
        totais = _somar_movimentos_backend(movimentos_ajuste)

        saldo_inicial = _to_int_backend(entry.get('QtAlocada'))
        saldo_final = saldo_inicial + totais['entradas'] + totais['retornos'] - totais['saidas']

        merged.append({
            'ID': entry.get('ID'),
            'Endereco': _normalize_endereco_backend(entry.get('Endereco')),
            'CodSKU': _to_int_backend(entry.get('CodSKU')),
            'Produto': (entry.get('Produto') or '').strip(),
            'QtAlocada': int(round(saldo_final)),
            'QtSaldoInicial': saldo_inicial,
            'QtMovEntrada': int(round(totais['entradas'])),
            'QtMovRetorno': int(round(totais['retornos'])),
            'QtMovSaida': int(round(totais['saidas'])),
            'QtSaldoFinal': int(round(saldo_final)),
            'QtMaxima': _to_int_backend(entry.get('QtMaxima')),
            'CdLot': _to_int_backend(entry.get('CdLot')),
            'NmLot': (entry.get('NmLot') or '').strip(),
            'QtCaixaP': _to_int_backend(entry.get('QtCaixaP')),
            'QtCaixaG': _to_int_backend(entry.get('QtCaixaG')),
            'QtEnfestado': _to_int_backend(entry.get('QtEnfestado')),
            'QtEnfraldado': _to_int_backend(entry.get('QtEnfraldado')),
            'DataAtualizacao': _format_data_backend(entry.get('DataAtualizacao')),
            'SortData': entry.get('DataAtualizacao'),
        })

    for key, movs in movimentos_por_chave.items():
        if key in base_por_chave:
            continue

        info = info_por_chave.get(key)
        if not info:
            continue

        totais = _somar_movimentos_backend(movs)
        saldo_final = totais['entradas'] + totais['retornos'] - totais['saidas']

        merged.append({
            'ID': None,
            'Endereco': _normalize_endereco_backend(info.get('Endereco')),
            'CodSKU': _to_int_backend(info.get('CodSKU')),
            'Produto': (info.get('Produto') or '').strip() or f"SKU {_to_int_backend(info.get('CodSKU'))}",
            'QtAlocada': int(round(saldo_final)),
            'QtSaldoInicial': 0,
            'QtMovEntrada': int(round(totais['entradas'])),
            'QtMovRetorno': int(round(totais['retornos'])),
            'QtMovSaida': int(round(totais['saidas'])),
            'QtSaldoFinal': int(round(saldo_final)),
            'QtMaxima': 0,
            'CdLot': _to_int_backend(info.get('DetalheId')),
            'NmLot': (info.get('NmLot') or '').strip(),
            'QtCaixaP': 0,
            'QtCaixaG': 0,
            'QtEnfestado': 0,
            'QtEnfraldado': 0,
            'DataAtualizacao': None,
            'SortData': None,
        })

    merged.sort(
        key=lambda x: (
            x.get('SortData') is None,
            str(x.get('SortData') or ''),
            x.get('CodSKU') or 0,
            x.get('CdLot') or 0,
        ),
        reverse=True,
    )

    return merged


def _filtrar_por_termo_backend(rows, termo):
    termo_norm = _normalize_texto_backend(termo)
    if not termo_norm:
        return rows

    filtrados = []
    for row in rows:
        produto = _normalize_texto_backend(row.get('Produto'))
        nm_lot = _normalize_texto_backend(row.get('NmLot'))
        cod_sku = str(_to_int_backend(row.get('CodSKU')))

        if termo_norm in produto or termo_norm in nm_lot or termo_norm in cod_sku:
            filtrados.append(row)

    return filtrados


@wms_alocacao_bp.route('/consulta/wms/palete/relatorio', methods=['GET'])
def relatorio_palete():
    connection = None
    try:
        endereco = (request.args.get('endereco') or '').strip().upper()
        if not endereco:
            return jsonify({"error": "Campo obrigatório: endereco"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        resultados = _consolidar_alocacoes_com_movimentos_backend(
            cursor,
            endereco=endereco,
        )

        resultados = [
            {k: v for k, v in row.items() if k != 'SortData'}
            for row in resultados
            if _to_int_backend(row.get('QtSaldoFinal')) > 0
            or _to_int_backend(row.get('QtCaixaP')) > 0
            or _to_int_backend(row.get('QtCaixaG')) > 0
            or _to_int_backend(row.get('QtEnfestado')) > 0
            or _to_int_backend(row.get('QtEnfraldado')) > 0
        ]

        print(f"✅ Relatório do palete {endereco}: {len(resultados)} itens retornados.")
        return jsonify(resultados), 200

    except Exception as e:
        print(f"❌ Erro ao consultar relatório do palete: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@wms_alocacao_bp.route('/consulta/wms/palete/busca_artigo', methods=['GET'])
def buscar_artigo_em_paletes():
    connection = None
    try:
        termo = (request.args.get('q') or '').strip()
        if not termo:
            return jsonify({"error": "Campo obrigatório: q"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        resultados = _consolidar_alocacoes_com_movimentos_backend(cursor)
        resultados = _filtrar_por_termo_backend(resultados, termo)

        resultados = [
            {k: v for k, v in row.items() if k != 'SortData'}
            for row in resultados
            if _to_int_backend(row.get('QtSaldoFinal')) > 0
            or _to_int_backend(row.get('QtCaixaP')) > 0
            or _to_int_backend(row.get('QtCaixaG')) > 0
            or _to_int_backend(row.get('QtEnfestado')) > 0
            or _to_int_backend(row.get('QtEnfraldado')) > 0
        ]

        print(f"✅ Busca de artigo '{termo}': {len(resultados)} itens retornados.")
        return jsonify(resultados), 200

    except Exception as e:
        print(f"❌ Erro ao buscar artigo em paletes: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()