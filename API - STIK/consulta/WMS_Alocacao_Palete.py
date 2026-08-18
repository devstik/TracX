from datetime import datetime
from flask import jsonify, request

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
    if isinstance(value, datetime):
        return value.strftime('%d/%m/%Y %H:%M')
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
        return detalhe_zero

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

    if not movimentos_por_chave:
        resultados = []
        for entry in alocacoes:
            saldo_inicial = _to_int_backend(entry.get('QtAlocada'))
            resultados.append({
                'ID': entry.get('ID'),
                'Endereco': _normalize_endereco_backend(entry.get('Endereco')),
                'CodSKU': _to_int_backend(entry.get('CodSKU')),
                'Produto': (entry.get('Produto') or '').strip(),
                'QtAlocada': saldo_inicial,
                'QtSaldoInicial': saldo_inicial,
                'QtMovEntrada': 0,
                'QtMovRetorno': 0,
                'QtMovSaida': 0,
                'QtSaldoFinal': saldo_inicial,
                'QtMaxima': _to_int_backend(entry.get('QtMaxima')),
                'CdLot': _to_int_backend(entry.get('CdLot')),
                'NmLot': (entry.get('NmLot') or '').strip(),
                'QtCaixaP': _to_int_backend(entry.get('QtCaixaP')),
                'QtCaixaG': _to_int_backend(entry.get('QtCaixaG')),
                'QtEnfestado': _to_int_backend(entry.get('QtEnfestado')),
                'QtEnfraldado': _to_int_backend(entry.get('QtEnfraldado')),
                'DataAtualizacao': _format_data_backend(entry.get('DataAtualizacao')),
                'DataAtualizacaoRaw': entry.get('DataAtualizacao'),
            })
        return resultados

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
        saldo_final = (
            saldo_inicial
            + totais['entradas']
            + totais['retornos']
            - totais['saidas']
        )

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
            'DataAtualizacaoRaw': entry.get('DataAtualizacao'),
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
            'DataAtualizacaoRaw': None,
        })

    merged.sort(
        key=lambda x: (
            x.get('DataAtualizacaoRaw') is None,
            x.get('DataAtualizacaoRaw') or datetime.min,
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

        if (
            termo_norm in produto
            or termo_norm in nm_lot
            or termo_norm in cod_sku
        ):
            filtrados.append(row)

    return filtrados

@wms_bp.route('/consulta/wms/palete/relatorio', methods=['GET'])
def relatorio_palete():
    connection = None
    try:
        endereco = (request.args.get('endereco') or '').strip().upper()
        if not endereco:
            return jsonify({"error": "Parâmetro obrigatório: endereco"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"error": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        sql = """
            WITH Base AS (
                SELECT
                    Endereco = UPPER(LTRIM(RTRIM(A.Endereco))),
                    A.CodSKU,
                    CdLot = ISNULL(A.Detalhe, 0),
                    QtSaldoInicial = ISNULL(A.QtAlocada, 0),
                    QtMaxima = ISNULL(A.QtMaxima, 0),
                    A.DataAtualizacao
                FROM dbo.Stik_WMS_Alocacao A WITH (NOLOCK)
                WHERE UPPER(LTRIM(RTRIM(A.Endereco))) = ?
            ),
            Mov AS (
                SELECT
                    Endereco = UPPER(LTRIM(RTRIM(M.Endereco))),
                    M.CodSKU,
                    CdLot = ISNULL(M.Detalhe, 0),
                    QtMovEntrada = SUM(CASE WHEN M.TpMov = 1 THEN ISNULL(M.QtMovida, 0) ELSE 0 END),
                    QtMovSaida = SUM(CASE WHEN M.TpMov = 2 THEN ISNULL(M.QtMovida, 0) ELSE 0 END),
                    QtMovRetorno = SUM(CASE WHEN M.TpMov = 3 THEN ISNULL(M.QtMovida, 0) ELSE 0 END)
                FROM dbo.Stik_WMS_Movimento M WITH (NOLOCK)
                WHERE UPPER(LTRIM(RTRIM(M.Endereco))) = ?
                GROUP BY
                    UPPER(LTRIM(RTRIM(M.Endereco))),
                    M.CodSKU,
                    ISNULL(M.Detalhe, 0)
            ),
            EmbAtual AS (
                SELECT
                    Endereco = UPPER(LTRIM(RTRIM(E.Endereco))),
                    E.CodSKU,
                    CdLot = ISNULL(E.Detalhe, 0),
                    QtCaixaP = ISNULL(E.QtCaixaP, 0),
                    QtCaixaG = ISNULL(E.QtCaixaG, 0),
                    QtEnfestado = ISNULL(E.QtEnfestado, 0),
                    QtEnfraldado = ISNULL(E.QtEnfraldado, 0)
                FROM dbo.Stik_WMS_Alocacao_Embalagem E WITH (NOLOCK)
                WHERE UPPER(LTRIM(RTRIM(E.Endereco))) = ?
            ),
            EmbMov AS (
                SELECT
                    CodSKU = M.CodSKU,
                    CdLot = ISNULL(M.Detalhe, 0),
                    QtCaixaP = SUM(
                        CASE
                            WHEN M.TpMov = 4
                                 AND UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN ISNULL(M.QtCaixaP, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaP, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaP, 0)
                            ELSE 0
                        END
                    ),
                    QtCaixaG = SUM(
                        CASE
                            WHEN M.TpMov = 4
                                 AND UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN ISNULL(M.QtCaixaG, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaG, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaG, 0)
                            ELSE 0
                        END
                    ),
                    QtEnfestado = SUM(
                        CASE
                            WHEN M.TpMov = 4
                                 AND UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN ISNULL(M.QtEnfestado, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtEnfestado, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtEnfestado, 0)
                            ELSE 0
                        END
                    ),
                    QtEnfraldado = SUM(
                        CASE
                            WHEN M.TpMov = 4
                                 AND UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN ISNULL(M.QtEnfraldado, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtEnfraldado, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtEnfraldado, 0)
                            ELSE 0
                        END
                    )
                FROM dbo.Stik_WMS_Movimento_Embalagem M WITH (NOLOCK)
                WHERE (
                    UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ?
                    OR UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ?
                )
                GROUP BY
                    M.CodSKU,
                    ISNULL(M.Detalhe, 0)
            ),
            Chaves AS (
                SELECT CodSKU, CdLot FROM Base
                UNION
                SELECT CodSKU, CdLot FROM Mov
                UNION
                SELECT CodSKU, CdLot FROM EmbAtual
                UNION
                SELECT CodSKU, CdLot FROM EmbMov
            )
            SELECT
                Endereco = ?,
                C.CodSKU,
                CdLot = C.CdLot,
                Produto = ISNULL(Obj.NmObj, 'Produto não identificado'),
                NmLot = ISNULL(Lot.NmLot, ''),
                QtAlocada = ISNULL(B.QtSaldoInicial, 0),
                QtMovEntrada = ISNULL(M.QtMovEntrada, 0),
                QtMovSaida = ISNULL(M.QtMovSaida, 0),
                QtMovRetorno = ISNULL(M.QtMovRetorno, 0),
                QtSaldoFinal = ISNULL(B.QtSaldoInicial, 0)
                               + ISNULL(M.QtMovEntrada, 0)
                               + ISNULL(M.QtMovRetorno, 0)
                               - ISNULL(M.QtMovSaida, 0),
                QtMaxima = ISNULL(B.QtMaxima, 0),
                QtCaixaP = CASE
                    WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaP, 0)
                    ELSE ISNULL(EM.QtCaixaP, 0)
                END,
                QtCaixaG = CASE
                    WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaG, 0)
                    ELSE ISNULL(EM.QtCaixaG, 0)
                END,
                QtEnfestado = CASE
                    WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfestado, 0)
                    ELSE ISNULL(EM.QtEnfestado, 0)
                END,
                QtEnfraldado = CASE
                    WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfraldado, 0)
                    ELSE ISNULL(EM.QtEnfraldado, 0)
                END,
                DataAtualizacao = B.DataAtualizacao
            FROM Chaves C
            LEFT JOIN Base B
                ON B.CodSKU = C.CodSKU
               AND B.CdLot = C.CdLot
            LEFT JOIN Mov M
                ON M.CodSKU = C.CodSKU
               AND M.CdLot = C.CdLot
            LEFT JOIN EmbAtual EA
                ON EA.CodSKU = C.CodSKU
               AND EA.CdLot = C.CdLot
            LEFT JOIN EmbMov EM
                ON EM.CodSKU = C.CodSKU
               AND EM.CdLot = C.CdLot
            LEFT JOIN dbo.TbObj Obj WITH (NOLOCK)
                ON Obj.CdObj = C.CodSKU
            LEFT JOIN dbo.TbLot Lot WITH (NOLOCK)
                ON Lot.CdLot = C.CdLot
            WHERE
                (
                    ISNULL(B.QtSaldoInicial, 0)
                    + ISNULL(M.QtMovEntrada, 0)
                    + ISNULL(M.QtMovRetorno, 0)
                    - ISNULL(M.QtMovSaida, 0)
                ) > 0
                OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaP, 0) ELSE ISNULL(EM.QtCaixaP, 0) END > 0
                OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaG, 0) ELSE ISNULL(EM.QtCaixaG, 0) END > 0
                OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfestado, 0) ELSE ISNULL(EM.QtEnfestado, 0) END > 0
                OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfraldado, 0) ELSE ISNULL(EM.QtEnfraldado, 0) END > 0
            ORDER BY Produto, NmLot, C.CdLot
        """

        cursor.execute(sql, (
            endereco,
            endereco,
            endereco,
            endereco, endereco, endereco,
            endereco, endereco, endereco,
            endereco, endereco, endereco,
            endereco, endereco, endereco,
            endereco, endereco,
            endereco,
        ))

        colunas = [col[0] for col in cursor.description]
        resultados = [dict(zip(colunas, row)) for row in cursor.fetchall()]
        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()
# @wms_alocacao_bp.route('/consulta/wms/palete/relatorio', methods=['GET'])
# def relatorio_palete():
#     connection = None
#     try:
#         endereco = (request.args.get('endereco') or '').strip().upper()
#         if not endereco:
#             return jsonify({"error": "Campo obrigatório: endereco"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({
#                 "status": "SQL_ERROR",
#                 "details": "Falha ao conectar ao banco."
#             }), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON;")

#         resultados = _consolidar_alocacoes_com_movimentos_backend(
#             cursor,
#             endereco=endereco,
#         )

#         resultados = [
#             {
#                 k: v
#                 for k, v in row.items()
#                 if k != 'DataAtualizacaoRaw'
#             }
#             for row in resultados
#             if _to_int_backend(row.get('QtSaldoFinal')) > 0
#             or _to_int_backend(row.get('QtCaixaP')) > 0
#             or _to_int_backend(row.get('QtCaixaG')) > 0
#             or _to_int_backend(row.get('QtEnfestado')) > 0
#             or _to_int_backend(row.get('QtEnfraldado')) > 0
#         ]

#         print(f"✅ Relatório do palete {endereco}: {len(resultados)} itens retornados.")
#         return jsonify(resultados), 200

#     except Exception as e:
#         print(f"❌ Erro ao consultar relatório do palete: {e}")
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


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
            {
                k: v
                for k, v in row.items()
                if k != 'DataAtualizacaoRaw'
            }
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