from flask import Blueprint, jsonify, request
from datetime import datetime, date
from decimal import Decimal
from database.server import create_connection_tinturaria, create_connection_ordens, create_connection_EAN

tracx_ApontamentoPost_bp = Blueprint('tracx_ApontamentoPost', __name__)

def obter_turno_id():
    hora_atual = datetime.now().hour
    if 8 <= hora_atual < 14:
        return 3
    elif 14 <= hora_atual < 22:
        return 4
    else:
        return 2

def serializar_linha(cols, row):
    linha = {}
    for col, valor in zip(cols, row):
        if isinstance(valor, (date, datetime)):
            linha[col] = valor.isoformat()
        elif isinstance(valor, Decimal):
            linha[col] = float(valor)
        else:
            linha[col] = valor
    return linha
    
# ==========================================================
# ENDPOINTS DE POST (SALVAR)
# ==========================================================

@tracx_ApontamentoPost_bp.route('/apontamento/tipoA', methods=['POST'])
def salvar_tipo_a():
    data_json = request.get_json()
    hoje = datetime.now().strftime('%Y-%m-%d')
    turno_id = obter_turno_id()

    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_insert = """
            INSERT INTO Stik_ApontamentoTipoA 
            (Data, Turno, Setor, Maq, Operador, Qtde, Artigo, Detalhe, TpMovimento)
            VALUES (CAST(? AS DATE), ?, ?, ?, ?, ?, ?, ?, ?)
        """

        valores = (
            hoje,
            turno_id,
            data_json.get('Setor'),
            data_json.get('Maq'),
            data_json.get('Operador'),
            data_json.get('Qtde'),
            data_json.get('Artigo'),
            data_json.get('Detalhe'),
            data_json.get('TpMovimento') 
        )

        cursor.execute(sql_insert, valores)
        connection.commit()

        return jsonify({"message": "Sucesso Tipo A"}), 201

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@tracx_ApontamentoPost_bp.route('/apontamento/tipoB', methods=['POST'])
def salvar_tipo_b():
    data_json = request.get_json()
    hoje = datetime.now().strftime('%Y-%m-%d')
    turno_id = obter_turno_id()

    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_insert = """
            INSERT INTO Stik_ApontamentoTipoB 
            (data, turno, Setor, Maq, Operador, Artigo, Detalhe, Defeito, Qtde)
            VALUES (CAST(? AS DATE), ?, ?, ?, ?, ?, ?, ?, ?)
        """

        valores = (
            hoje,
            turno_id,
            data_json.get('Setor'),
            data_json.get('Maq'),
            data_json.get('Operador'),
            data_json.get('Artigo'),
            data_json.get('Detalhe'),
            data_json.get('Defeito'),
            data_json.get('Qtde')
        )

        cursor.execute(sql_insert, valores)
        connection.commit()

        return jsonify({"message": "Sucesso Tipo B"}), 201

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@tracx_ApontamentoPost_bp.route('/apontamento/mapa-eficiencia-emb', methods=['POST'])
def salvar_mapa_eficiencia_emb():
    data_json = request.get_json()
    agora = datetime.now()
    data_apontamento = data_json.get('Data') or agora.strftime('%Y-%m-%d %H:%M:%S')
    turno_id = data_json.get('CdTur') or obter_turno_id()

    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_insert = """
            INSERT INTO Stik_MapaEficienciaEmb
            (
                Data,
                CdTur,
                SetorID,
                MaquinaID,
                CdUsrOper,
                CdObj,
                Qtd,
                DefeitoID,
                CdMppite,
                CdVpd,
                TpMovimento
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        valores = (
            data_apontamento,
            turno_id,
            data_json.get('Setor'),
            data_json.get('Maq'),
            data_json.get('Operador'),
            data_json.get('Artigo'),
            data_json.get('Qtde'),
            data_json.get('Defeito'),
            data_json.get('CdMppite'),
            data_json.get('CdVpd'),
            data_json.get('TpMovimento')
        )

        cursor.execute(sql_insert, valores)
        connection.commit()

        return jsonify({"message": "Sucesso Mapa Eficiência Emb"}), 201

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@tracx_ApontamentoPost_bp.route('/consultar/falha-tipo-b', methods=['GET'])
def listar_falha_tipo_b():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        cursor.execute("""
            SELECT
                ID = Tp.ID,
                NmFalaTipoB = Tp.NmFalaTipoB
            FROM Stik_Falha_Tipo_B Tp
            ORDER BY Tp.ID
        """)

        colunas = [column[0] for column in cursor.description]
        resultados = [dict(zip(colunas, row)) for row in cursor.fetchall()]

        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

# ==========================================================
# ENDPOINT DE PUT (ATUALIZAR / CORRIGIR)
# ==========================================================

@tracx_ApontamentoPost_bp.route('/apontamento/<tipo>/<int:registro_id>', methods=['PATCH'])
def atualizar_apontamento(tipo, registro_id):
    data_json = request.get_json()

    if not data_json:
        return jsonify({"error": "Nenhum dado enviado para atualização"}), 400

    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        configuracao = {
            "tipoA": {
                "tabela": "Stik_ApontamentoTipoA",
                "id_coluna": "Id",
                "campos_permitidos": {
                    "Data": "Data",
                    "Turno": "Turno",
                    "Setor": "Setor",
                    "Maq": "Maq",
                    "Operador": "Operador",
                    "Qtde": "Qtde",
                    "Artigo": "Artigo",
                    "Detalhe": "Detalhe"
                }
            },
            "tipoB": {
                "tabela": "Stik_ApontamentoTipoB",
                "id_coluna": "Id",
                "campos_permitidos": {
                    "Data": "data",
                    "Turno": "turno",
                    "Setor": "Setor",
                    "Maq": "Maq",
                    "Operador": "Operador",
                    "Artigo": "Artigo",
                    "Detalhe": "Detalhe",
                    "Defeito": "Defeito",
                    "Qtde": "Qtde"
                }
            },
            "mapa-eficiencia-emb": {
                "tabela": "Stik_MapaEficienciaEmb",
                "id_coluna": "Id",
                "campos_permitidos": {
                    "Data": "Data",
                    "CdTur": "CdTur",
                    "Setor": "SetorID",
                    "Maq": "MaquinaID",
                    "Operador": "CdUsrOper",
                    "Artigo": "CdObj",
                    "Qtde": "Qtd",
                    "Defeito": "DefeitoID",
                    "CdMppite": "CdMppite",
                    "CdVpd": "CdVpd"
                }
            }
        }

        if tipo not in configuracao:
            return jsonify({
                "error": "Tipo inválido. Use: tipoA, tipoB ou mapa-eficiencia-emb"
            }), 400

        tabela = configuracao[tipo]["tabela"]
        id_coluna = configuracao[tipo]["id_coluna"]
        campos_permitidos = configuracao[tipo]["campos_permitidos"]

        campos_update = []
        valores = []
        campos_atualizados = []

        for campo_json, valor in data_json.items():
            if campo_json in campos_permitidos:
                nome_coluna = campos_permitidos[campo_json]
                campos_update.append(f"{nome_coluna} = ?")
                valores.append(valor)
                campos_atualizados.append(campo_json)

        if not campos_update:
            return jsonify({
                "error": "Nenhum campo válido enviado para atualização"
            }), 400

        sql_check = f"SELECT 1 FROM {tabela} WHERE {id_coluna} = ?"
        cursor.execute(sql_check, (registro_id,))
        existe = cursor.fetchone()

        if not existe:
            return jsonify({"error": "Registro não encontrado"}), 404

        sql_update = f"""
            UPDATE {tabela}
            SET {', '.join(campos_update)}
            WHERE {id_coluna} = ?
        """

        valores.append(registro_id)

        cursor.execute(sql_update, tuple(valores))
        connection.commit()

        return jsonify({
            "message": "Registro atualizado com sucesso",
            "tipo": tipo,
            "id": registro_id,
            "campos_atualizados": campos_atualizados
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

# ==========================================================
# ENDPOINTS DE GET (CONSULTAR)
# ==========================================================

@tracx_ApontamentoPost_bp.route('/apontamento/tipoA', methods=['GET'])
def listar_tipo_a():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        cursor.execute("""
            SELECT 
                Id,
                CONVERT(VARCHAR(10), Data, 120) AS Data,
                Turno,
                Setor,
                Maq,
                Operador,
                Qtde,
                Artigo,
                Detalhe
            FROM Stik_ApontamentoTipoA
            ORDER BY Id DESC
        """)

        colunas = [column[0] for column in cursor.description]
        resultados = [dict(zip(colunas, row)) for row in cursor.fetchall()]

        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@tracx_ApontamentoPost_bp.route('/apontamento/tipoB', methods=['GET'])
def listar_tipo_b():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        cursor.execute("""
            SELECT 
                Id,
                CONVERT(VARCHAR(10), data, 120) as data,
                turno,
                Setor,
                Maq,
                Operador,
                Artigo,
                Detalhe,
                Defeito,
                Qtde
            FROM Stik_ApontamentoTipoB
            ORDER BY Id DESC
        """)

        colunas = [column[0] for column in cursor.description]
        resultados = [dict(zip(colunas, row)) for row in cursor.fetchall()]

        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@tracx_ApontamentoPost_bp.route('/produto/<codigo>', methods=['GET'])
def buscar_produto(codigo):
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        
        sql_query = """
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
            WHERE (Obj.CdObj = ? OR dbo.UFN_GeraCodigoEAN(CaoEan13.NrCao) = ?)
        """
        
        cursor.execute(sql_query, (codigo, codigo))
        row = cursor.fetchone()
        
        if row:
            colunas = [column[0] for column in cursor.description]
            resultado = dict(zip(colunas, row))
            return jsonify(resultado), 200
        else:
            return jsonify({"error": "Produto não encontrado"}), 404

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()

@tracx_ApontamentoPost_bp.route('/consultar/usuarios', methods=['GET'])
def listar_usuarios():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        cursor.execute("""
            SELECT Id, CdUser, NmUser, Setorid
            FROM Stik_Embalagem_Usuarios
            ORDER BY Id DESC
        """)

        colunas = [column[0] for column in cursor.description]
        resultados = [dict(zip(colunas, row)) for row in cursor.fetchall()]

        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@tracx_ApontamentoPost_bp.route('/consultar/artigos', methods=['GET'])
def consultar_artigos():
    connection = None
    try:
        codigo = request.args.get("codigo")

        if not codigo:
            return jsonify({"error": "Informe o parâmetro 'codigo'"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_query = """
        SELECT
            Obj.CdObj,
            NmObj = UPPER(Obj.NmObj),

            QrCode =
                '{"CdObj":'
                + CONVERT(VARCHAR(20), Obj.CdObj)
                + ',"Detalhe":'
                + CONVERT(VARCHAR(20), Lot.CdLot)
                + '}',

            Detalhe   = Lot.NmLot,
            Descricao = Obj.TtObj,

            Ean13 = dbo.UFN_GeraCodigoEAN(CaoEan13.NrCao),

            Metragem =
                CASE
                    WHEN Carretel.NmOpc = 'ENF' THEN 'ENF - Enfestado'
                    WHEN Carretel.NmOpc = 'ENFRALDADO' THEN 'ENFRALDADO'
                    ELSE CONVERT(VARCHAR, Carretel.NmOpc) + ' Mts'
                END

        FROM TbObj Obj

        LEFT JOIN TbLot Lot
               ON Lot.CdObj = Obj.CdObj
              AND Lot.CdLot = 0

        LEFT JOIN TbCao CaoEan13
               ON CaoEan13.CdObj = Obj.CdObj
              AND CaoEan13.CdTca = 2

        LEFT JOIN (
            SELECT
                Opo.CdObj,
                NmOpc = Opc.NmOpc
            FROM TbOpo Opo
            JOIN TbCrc Crc ON Crc.CdCrc = Opo.CdCrc
            LEFT JOIN TbOpc Opc ON Opc.CdOpc = Opo.CdOpc
            WHERE Crc.CdCrc = 96
        ) Carretel
            ON Carretel.CdObj = Obj.CdObj

        WHERE
            Obj.CdObj = ?
            OR dbo.UFN_GeraCodigoEAN(CaoEan13.NrCao) = ?
        """

        cursor.execute(sql_query, (codigo, codigo))

        colunas = [column[0] for column in cursor.description]
        resultados = [dict(zip(colunas, row)) for row in cursor.fetchall()]

        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@tracx_ApontamentoPost_bp.route('/consultar/apontamentos', methods=['GET'])
def consultar_apontamentos():
    connection = None
    try:
        data_inicio = request.args.get('DataInicio')  # formato: YYYY-MM-DD
        data_fim = request.args.get('DataFim')         # formato: YYYY-MM-DD
        artigo = request.args.get('Artigo')             # CdObj
        turno = request.args.get('Turno')                # CdTur
        usuario = request.args.get('Usuario')             # CdUser
        setor = request.args.get('Setor')                  # SetorID

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_query = """
            Select distinct
                Query.Artigo
            ,   Query.Defeito
            ,   Query.Operador
            ,   Query.Qtd
            ,   Query.Setor
            ,   Query.DtMapa
            ,   Query.Turno
            ,   Query.Funcionario
            From (
                Select
                    Turno = Tur.NmTur
                ,   DtMapa = Convert(date,Em.Data)
                ,   Funcionario = IIF(Opp.TtOpp IS NOT NULL AND Opp.TtOpp <> '', 
                                LEFT(Opp.TtOpp, 3), 
                                ISNULL(CAST(E.CdUser AS VARCHAR(50)), ''))
                ,   Und = Und.SgUnd
                ,   Artigo = Obj.NmObj
                ,   Defeito = CASE WHEN Fb.NmFalaTipoB IS NOT NULL AND Fb.NmFalaTipoB <> '' THEN Fb.NmFalaTipoB
                                ELSE 'Sem defeito' END
                ,   Operador = CASE 
                            WHEN Convert(date, Em.Data) <= '20251231' THEN Pes.NmPes
                            WHEN Convert(date, Em.Data) >= '20260101' THEN 
                                CASE 
                                    WHEN E.NmUser IS NOT NULL AND E.NmUser <> '' THEN E.NmUser
                                    ELSE Pes.NmPes
                                END
                            ELSE Pes.NmPes
                        END
                ,   Qtd = Sum(Em.Qtd)
                ,   Setor  = CASE
                         WHEN Stik_Setor.ID = 1 Then 'ENROL. MAQUINA'
                         WHEN Stik_Setor.ID = 2 Then 'ENROL. MESA'
                         WHEN Stik_Setor.ID = 3 Then 'ENFRALDAMENTO'
                         WHEN Stik_Setor.ID = 4 Then 'ENFESTAMENTO'
                         WHEN Stik_Setor.ID = 5 Then 'ENROL. DISCO'
                         WHEN Stik_Setor.ID = 6 Then 'TECELAGEM'
                         WHEN Stik_Setor.ID = 7 Then 'TINTURARIA'
                         WHEN Stik_Setor.ID = 10 Then 'REVISAO'
                         Else 'Maquina' End
                From Stik_MapaEficienciaEmb Em
                left join   TbTur Tur on Tur.CdTur = Em.CdTur
                left join   TbMppIte MppIte on MppIte.CdMppite = Em.CdMppite
                join    TbObj Obj on Obj.CdObj = Em.CdObj
                left join   TbUnd Und on Und.CdUnd = Obj.CdUnd
                left join   Stik_Embalagem_Usuarios E on E.CdUser = Em.CdUsrOper
                left join   TbPes Pes on Pes.CdPes = Em.CdUsrOper
                left join   TbOpp Opp on Opp.CdPes = Pes.CdPes and Opp.CdCrc = 164
                Left join   Stik_Falha_Tipo_B Fb on Fb.ID = Em.DefeitoID
                left join Stik_Setor Stik_Setor on Stik_Setor.ID = Em.SetorID
                Where
                    (Convert(smalldatetime,Convert(date,Em.Data)) >= Convert(smalldatetime, ?) or ? IS NULL)
                and (Convert(smalldatetime,Convert(date,Em.Data)) <= Convert(smalldatetime, ?) or ? IS NULL)
                and (Obj.CdObj = ? or ? IS NULL)
                and (Tur.CdTur = ? or ? IS NULL)
                and (E.CdUser = ? or ? IS NULL)
                and (Em.SetorID = ? or ? IS NULL)
                Group by
                    Tur.NmTur
                ,   Convert(date,Em.Data)
                ,   Und.SgUnd
                ,   Obj.NmObj
                ,   Opp.TtOpp
                ,   Fb.NmFalaTipoB
                ,   Pes.NmPes
                ,   Stik_Setor.ID
                ,   E.CdUser
                ,   E.NmUser
            ) Query
            Order by
                Query.DtMapa
            ,   Query.Turno
            ,   Query.Funcionario
        """

        valores = (
            data_inicio, data_inicio,
            data_fim, data_fim,
            artigo, artigo,
            turno, turno,
            usuario, usuario,
            setor, setor
        )

        cursor.execute(sql_query, valores)

        colunas = [column[0] for column in cursor.description]
        resultados = [dict(zip(colunas, row)) for row in cursor.fetchall()]

        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@tracx_ApontamentoPost_bp.route('/buffer_expedicao_ordem', methods=['GET'])
def obter_buffer_expedicao_ordem():
    conn = None
    try:
        filtros = {
            "production_family": request.args.get("production_family"),
            "plant": request.args.get("plant"),
            "sku_name": request.args.get("sku_name"),
        }
        query = """
            SELECT P.WOID, PP.Pedido AS SalesOrderID, P.SKUName AS SKUCode, P.SKUName, P.Plant, P.Quantity, P.OrderType, P.ProductionFamily,
                   M.SKUDescription, M.UOM, M.StockLocationName, 
                   DATEFROMPARTS(P.DueDateYear, P.DueDateMonth, P.DuaDateDay) AS DueDate,
                   DATEFROMPARTS(P.ReleaseDateYear, P.ReleaseDateMonth, P.ReleaseDateDay) AS ReleaseDate,
                   A.Alvo, S.InventoryAtHand AS LocalStock
            FROM TOC_NEW_PRODUCTION AS P
            LEFT JOIN MTSSKUS M ON P.SKUName = M.SKUName
            LEFT JOIN AlvosMTA A ON P.SKUName = A.SKUName
            LEFT JOIN STATUS S ON P.SKUName = S.SKUName
            LEFT JOIN (SELECT NrOrdem, Objeto, MAX(Pedido) AS Pedido, SUM(Qt) AS Qt, SUM(QtRes) AS QtRes FROM Tb_PedidosPendentes WHERE NrOrdem IS NOT NULL AND NrOrdem <> '' GROUP BY NrOrdem, Objeto) PP 
                ON CAST(P.WOID AS VARCHAR) LIKE CAST(PP.NrOrdem AS VARCHAR) + '%' AND M.SKUDescription = PP.Objeto
        """
        conditions, params = [], []
        if filtros["production_family"]:
            conditions.append("P.ProductionFamily = ?")
            params.append(filtros["production_family"])
        if filtros["plant"]:
            conditions.append("P.Plant = ?")
            params.append(filtros["plant"])
        if filtros["sku_name"]:
            conditions.append("P.SKUName = ?")
            params.append(filtros["sku_name"])
        if conditions:
            query += " WHERE " + " AND ".join(conditions)
        conn = create_connection_ordens()
        cursor = conn.cursor()
        cursor.execute(query, tuple(params))
        cols = [c[0] for c in cursor.description]
        res = [serializar_linha(cols, r) for r in cursor.fetchall()]
        return jsonify(res), 200
    except Exception as e:
        return jsonify({"erro": str(e)}), 500
    finally:
        if conn:
            conn.close()

@tracx_ApontamentoPost_bp.route('/consultar/planejamento-tinturaria', methods=['GET'])
def consultar_planejamento_tinturaria():
    connection = None
    try:
        def inteiro_opcional(nome):
            valor = request.args.get(nome)
            if valor is None or valor.strip() == '':
                return None
            return int(valor)

        cd_une = inteiro_opcional('CdUne')
        cd_vpd = inteiro_opcional('CdVpd')
        cd_cli = inteiro_opcional('CdCli')
        data_inicio = request.args.get('DataInicio') or None
        data_fim = request.args.get('DataFim') or None
        cd_obj = inteiro_opcional('CdObj')
        nome_artigo = request.args.get('NmObj')
        somente_atrasados = inteiro_opcional('SomenteAtrasados')
        cd_obj_lin = inteiro_opcional('CdObjLin')
        somente_pendentes = inteiro_opcional('SomentePendentes')

        if somente_atrasados is None:
            somente_atrasados = 0

        if somente_pendentes is None:
            somente_pendentes = 0

        nome_artigo_like = f"%{nome_artigo.strip()}%" if nome_artigo and nome_artigo.strip() else None

        query = r"""SET NOCOUNT ON;

Select
     NrDiasDtPrevisao
 Into #Stik_ParamTint
 From Stik_ParamTint

 Select
     Vpo.CdVpo, Vpo.CdObj, Vpo.QtVpo, Vpo.QtVpoFatCan, Obj.NmObj, Vpd.CdUne, Vpd.CdVpd, Vpd.DtVpdInc, Cli.NmCli, LotVen.CdLot, LotVen.NmLot, Vpo.DtVpoEnt, VendedorPrioritario = IsNull(Opl.FlOpl, 0),
 OcDoCliente = (Select Top 1 VpdCrc.TtVpdcrc from TbVpdcrc VpdCrc where VpdCrc.CdVpd = Vpd.CdVpd and VpdCrc.CdCrc= 155),
 Detalhe = LotDet.NmLot, Setor = Obj.CdObjLin, Obs = Obs.TtObs, Res.QtReserva, DtVpdAutFat = L.DtVpdAutFat
,DtLeadTime =
     CAST(
         CASE
             WHEN Vpo.DtVpoEnt IS NOT NULL
              AND CAST(Vpo.DtVpoEnt AS DATE) > Calc.LeadTimeCalculado
                 THEN CAST(Vpo.DtVpoEnt AS DATE)
             ELSE Calc.LeadTimeCalculado
         END AS DATE
     )
 into #Vpo
 From TbVpo Vpo
 join   TbVpd Vpd on Vpd.CdVpd = Vpo.CdVpd
 join   TbObj Obj on Obj.CdObj = Vpo.CdObj
 join    TbCli Cli on Cli.CdCli = Vpd.CdCli
LEFT JOIN TbPes Pes WITH (NOLOCK)
  ON Pes.CdPes = Cli.CdPes

LEFT JOIN TbLoc Loc WITH (NOLOCK)
  ON Loc.CdLoc = Pes.CdLoc

LEFT JOIN TbLoc Regiao WITH (NOLOCK)
  ON Regiao.CdLoc = Loc.CdLoc002
 left join TbLot LotVen on LotVen.CdLot = Vpo.CdLotVen
 left join TbLot LotDet on LotDet.CdLot = Vpo.CdLot
 LEFT JOIN TbOpl Opl on Opl.CdLot = LotVen.CdLot and Opl.CdCrc = 174
 left join    TbObs Obs on Obs.CdObs = Vpd.CdObs
 left join (
     Select
         Res.CdObj
     ,   Res.CdVpo
     ,   Res.CdLot
     ,   QtReserva =
             Sum(
                 Case
                     When Res.TpResSin = 1 Then  IsNull(Res.QtReserva, IsNull(Met.QtMet, 0))
                     When Res.TpResSin = 3 Then -IsNull(Res.QtReserva, IsNull(Met.QtMet, 0))
                     Else 0
                 End
             )
     From Stik_Pedido_Reserva Res (nolock)
     left join TbMet Met (nolock) on Met.CdMet = Res.CdMet
     Where Res.TpResSin in (1,3)
     Group by
         Res.CdObj
     ,   Res.CdVpo
     ,   Res.CdLot
 ) Res on Res.CdObj = Vpo.CdObj and Res.CdVpo = Vpo.CdVpo and Res.CdLot = Vpo.CdLot
 left join (Select  Let.CdUne
 ,       Let.CdObj
 ,       Let.CdCcs
 ,       Let.CdLotAtv
 ,       Qt = Sum((Let.TpLetSin - 2) * Let.QtLet)
 From   TbLet Let (nolock)
 Where Let.DtLet <= GetDate()
 and Let.CdCcs = 13

 and    Let.CdLotAtv=2026

 Group by
         Let.CdUne
 ,       Let.CdObj
 ,       Let.CdCcs
 ,       Let.CdLotAtv) Let on Let.CdObj = Vpo.CdObj
left join Stik_VpdLeadTime L on L.CdVpd = Vpd.CdVpd
CROSS APPLY
(
    SELECT LeadTimeCalculado = CAST(
        DATEADD(
            DAY,
            CASE
                WHEN LTRIM(RTRIM(ISNULL(Regiao.NmLoc, ''))) COLLATE Latin1_General_CI_AI = 'Nordeste'
                    THEN 30
                ELSE 20
            END,
            L.DtVpdAutFat
        ) AS DATE
    )
) Calc

 Where
     (? IS NULL OR ? = 0 OR Exists(
          Select 1
          From TbArvUne ArvUne
          Where ArvUne.CdUneFil = Vpd.CdUne
            And ArvUne.CdUne = ?
     ))
 And (Vpd.CdVpd = ? OR ? IS NULL)
 And (Vpd.CdCli = ? OR ? IS NULL)
 And (Vpd.DtVpdInc >= ? OR ? IS NULL)
 And (Vpd.DtVpdInc < DATEADD(DAY, 1, CAST(? AS DATE)) OR ? IS NULL)
 And Vpd.TpVpdSta = 1
 And Vpd.FlVpdFec = 1
 And Vpd.FlVpdAutFat = 1
 And Vpo.CdFin IN (2, 28)
 And (Vpo.CdObj = ? OR ? IS NULL)
 And Vpo.TpVpoSta = 1
 And (Obj.NmObj LIKE ? OR ? IS NULL)
 And (? = 0 OR CONVERT(INT, DATEDIFF(DAY, Vpd.DtVpdInc, GETDATE())) > 0)
 And Vpd.CdTop <> 453
 And (Obj.CdObjLin = ? OR ? IS NULL)

 Select  Let.CdUne
 ,       Let.CdObj
 ,       Let.CdLot
 ,       Let.CdCcs
 ,       Let.CdLotAtv
 ,       Qt = Sum((Let.TpLetSin - 2) * Let.QtLet)
 into #Estoque
 From   TbLet Let (nolock)
 Where Let.DtLet <= GetDate()
 and Let.CdCcs = 13

 and    Let.CdLotAtv=2026
 and Exists (Select 1 From #Vpo Where CdObj = Let.CdObj)
 Group by
         Let.CdUne
 ,       Let.CdObj
 ,       Let.CdLot
 ,       Let.CdCcs
 ,       Let.CdLotAtv

 Select
     Rco.CdVpo
 ,  Rco.CdObj
 ,  Qt = Sum(IsNull(Rco.QtRco,0))
 into #Rco
 From TbRco Rco
 join #Vpo Vpo1 on Vpo1.CdVpo = Rco.CdVpo
 join TbVpo Vpo on Vpo.CdVpo = Rco.CdVpo
               And Rco.TpRcoSta <> 3
               And Rco.CdFin in (2, 28)
 Group by Rco.CdVpo, Rco.CdObj

 Select
     Res.CdObj
 ,   Res.CdVpo
 ,   Qt =
         Sum(
             Case
                 When Res.TpResSin = 1 Then  IsNull(Res.QtReserva, IsNull(Met.QtMet, 0))
                 When Res.TpResSin = 3 Then -IsNull(Res.QtReserva, IsNull(Met.QtMet, 0))
                 Else 0
             End
         )
 Into #PedRes
 From Stik_Pedido_Reserva Res (nolock)
 left join TbMet Met (nolock) on Met.CdMet = Res.CdMet
 Where Res.TpResSin in (1,3)
 Group by
     Res.CdObj
 ,   Res.CdVpo

 Select
     Rco.CdVpo
 ,   Rco.CdObj
 ,   Qt = Sum(Rco.Qt)
 Into #FatDoc
 From #Rco Rco
 Group by
     Rco.CdVpo
 ,   Rco.CdObj

 Select
     CdVpo
 ,   CdObj
 ,   QtFatLiquidoProcessado = Max(IsNull(QtFatLiquidoProcessado, 0))
 Into #FatSyncRes
 From dbo.Stik_Pedido_Reserva_FatSync (nolock)
 Where IsNull(QtFatLiquidoProcessado, 0) > 0
 Group by
     CdVpo
 ,   CdObj

 Select
     Codigo = Vpo.CdObj
 ,      Estoque =
              IsNull(Let.Qt, 0)
            + Sum(
                  Case
                      When FatSyncRes.CdVpo Is Not Null Then
                          Case
                              When IsNull(PedRes.Qt, 0) < 0 Then 0
                              Else IsNull(PedRes.Qt, 0)
                          End
                      Else
                          Case
                              When IsNull(PedRes.Qt, 0) - IsNull(FatDoc.Qt, 0) < 0 Then 0
                              Else IsNull(PedRes.Qt, 0) - IsNull(FatDoc.Qt, 0)
                          End
                  End
              )
            - Sum(IsNull(Vpo.QtVpo, 0) - IsNull(FatDoc.Qt, 0))
 into #QtdTot
 From #Vpo Vpo

 Left Join #PedRes PedRes on PedRes.CdObj = Vpo.CdObj and PedRes.CdVpo = Vpo.CdVpo

 Left join      (
                  Select  Let.CdObj

                  ,       Qt = Sum(Let.Qt)

                  From   #Estoque Let (nolock)
                  Where   Let.CdCcs = 13
                  Group by
                          Let.CdObj) Let on Let.CdObj = Vpo.CdObj

 Left Join #FatDoc FatDoc on FatDoc.CdVpo = Vpo.CdVpo and FatDoc.CdObj = Vpo.CdObj

 Left Join #FatSyncRes FatSyncRes on FatSyncRes.CdVpo = Vpo.CdVpo and FatSyncRes.CdObj = Vpo.CdObj

 group by
     Vpo.CdObj
 ,  Let.Qt

 Having
              IsNull(Let.Qt, 0)
            + Sum(
                  Case
                      When FatSyncRes.CdVpo Is Not Null Then
                          Case
                              When IsNull(PedRes.Qt, 0) < 0 Then 0
                              Else IsNull(PedRes.Qt, 0)
                          End
                      Else
                          Case
                              When IsNull(PedRes.Qt, 0) - IsNull(FatDoc.Qt, 0) < 0 Then 0
                              Else IsNull(PedRes.Qt, 0) - IsNull(FatDoc.Qt, 0)
                          End
                  End
              )
            - Sum(IsNull(Vpo.QtVpo, 0) - IsNull(FatDoc.Qt, 0)) <= 0

 Select
    Codigo = 1
 ,  Descricao = 'Total Negativo -->'
 ,  Detalhe = null
 ,  OcDoCliente = null
 ,  Cliente = null
 ,  Vendedor = null
 ,  DtPedido = null
 ,  DtEntrega = null
 ,  DtLeadTime = null
 ,  DiaEmAtrazo = null
 ,  Estoque = (Select Sum(Tot.Estoque) From #QtdTot Tot)
 ,  QtReserva = NULL
 ,  Maquina = null
 ,  Mae = null
 ,  Nivel = 1
 ,  Ordem1 = 1
 ,  Ordem2 = null
 ,  Ordem3 = null
 ,  Ordem4 = null
 ,  Marcar = 0
 ,  NrOrdem = null
 ,  PedidoEspecial = null
 ,  StaOrdem = null
 ,  DtOrdem = null
 ,  DtOrdIni = null
 ,  DtPrevisao = null
 ,  DtPrevMargem = null
 ,  DtPrevTin = null
 ,  DtPrevEmb = null
 ,  CdVpo = null
 ,  CdObj = null
 ,  ID = null
 ,  Ordenar = null
 ,  Ativo = null
 ,  FlPriorizar = 0
 ,  VendedorPrioritario = 0
 ,  Setor = NULL
 ,  CdVpd = NULL
 ,  Obs = NULL
 into #Result

 Union

 Select Distinct
    Codigo = Vpo.CdObj
 ,  Descricao = Vpo.NmObj
 ,  Detalhe = null
 ,  OcDoCliente = null
 ,  Cliente = null
 ,  Vendedor = null
 ,  DtPedido = null
 ,  DtEntrega = null
 ,  DtLeadTime = null
 ,  DiaEmAtrazo = null

 ,  Estoque = IsNull(Let.Qt,0)
 ,  QtReserva = NULL
 ,  Maquina = null
 ,  Mae = 1
 ,  Nivel = 2
 ,  Ordem1 = 1
 ,  Ordem2 = Vpo.CdObj
 ,  Ordem3 = null
 ,  Ordem4 = null
 ,  Marcar = 0
 ,  NrOrdem = null
 ,  PedidoEspecial = null
 ,  StaOrdem = null
 ,  DtOrdem = null
 ,  DtOrdIni = null
 ,  DtPrevisao = null
 ,  DtPrevMargem = null
 ,  DtPrevTin = null
 ,  DtPrevEmb = null
 ,  CdVpo = null
 ,  CdObj = null
 ,  ID = null
 ,  Ordenar = null
 ,  Ativo = null
 ,  FlPriorizar = 0
 ,  VendedorPrioritario = 0
 ,  Setor = NULL
 ,  CdVpd = NULL
 ,  Obs = NULL
 From #Vpo Vpo

 left join  Stik_ProgTinturaria Stp on Stp.CdVpo = Vpo.CdVpo and Stp.CdObj = Vpo.CdObj

 Left join       (
                  Select  Let.CdUne
                  ,       Let.CdObj
                  ,       Qt = Sum(Let.Qt)
                  From   #Estoque Let (nolock)
                  Where   Let.CdCcs in (13)
                  Group by
                          Let.CdUne, Let.CdObj) Let on Let.CdObj = Vpo.CdObj and Let.CdUne = Vpo.CdUne

 Left Join #PedRes PedRes on PedRes.CdObj = Vpo.CdObj and PedRes.CdVpo = Vpo.CdVpo

 Left Join #FatDoc FatDoc on FatDoc.CdVpo = Vpo.CdVpo and FatDoc.CdObj = Vpo.CdObj
 left join  Stik_Maquina Maq on Maq.ID = Stp.MaquinaID

 Union

 Select
    Codigo = Vpo.CdVpd
 ,  Descricao = Convert(varchar,Vpo.CdVpd)
 ,  Detalhe = Vpo.Detalhe
 ,  OcDoCliente = Vpo.OcDoCliente
 ,  Cliente = Vpo.NmCli
 ,  Vendedor = Vpo.NmLot

 ,  DtPedido = Vpo.DtVpdAutFat
 ,  DtEntrega = Vpo.DtVpoEnt
 ,  DtLeadTime = Vpo.DtLeadTime
 ,  DiaEmAtrazo = convert(varchar,Datediff(dd,Vpo.DtVpoEnt,GETDATE()))
 ,  Estoque = IsNull(Vpo.QtVpo,0) - IsNull(FatDoc.Qt,0)

 ,  QtReserva =
        CASE

            WHEN FatSyncRes.CdVpo IS NOT NULL THEN
                CASE
                    WHEN ISNULL(PedRes.Qt, 0) < 0 THEN 0
                    ELSE ISNULL(PedRes.Qt, 0)
                END

            ELSE
                CASE
                    WHEN ISNULL(PedRes.Qt, 0) - ISNULL(FatDoc.Qt, 0) < 0 THEN 0
                    ELSE ISNULL(PedRes.Qt, 0) - ISNULL(FatDoc.Qt, 0)
                END
        END
 ,  Maquina = Maq.NmMaquina + Char(160) + Convert(varchar,Maq.ID)
 ,  Mae = Vpo.CdObj
 ,  Nivel = 3
 ,  Ordem1 = 1
 ,  Ordem2 = Vpo.CdObj
 ,  Ordem3 = Vpo.CdVpd
 ,  Ordem4 = null
 ,  Marcar = 0
 ,  NrOrdem = Stp.NrOrdem
 ,  PedidoEspecial = (SELECT CASE
                             WHEN (SELECT TOP 1 E.PedidoEspecial FROM Stik_PCP_PEDIDOESPECIAL E WHERE E.NrOrdem = Stp.NrOrdem) = 1 THEN 'Sim'
                             WHEN (SELECT TOP 1 E.PedidoEspecial FROM Stik_PCP_PEDIDOESPECIAL E WHERE E.NrOrdem = Stp.NrOrdem) = 2 THEN 'Não'
                             ELSE NULL END)
 ,  StaOrdem =  CASE
                 WHEN Stp.Incluida = 1 THEN 'Aberto'
                 WHEN Stp.Incluida = 2 THEN 'Fechado'
                ELSE NULL END
 ,  DtOrdem = Stp.DtOrdem
 ,  DtOrdIni = Stp.DtOrdIni
 ,  DtPrevisao = Stp.DtPrevisao
 ,  DtPrevMargem = Stp.DtPrevisao + (Select IsNull(NrDiasDtPrevisao,0) From #Stik_ParamTint)
 ,  DtPrevTin = Stp.DtTingimento
 ,  DtPrevEmb = Stp.DtEmbalamento
 ,  CdVpo = Vpo.CdVpo
 ,  CdObj = Vpo.CdObj
 ,  ID = IsNull(Stp.ID,0)
 ,  Ordenar = Case When Vpo.CdLot in(254160,261369,289816,261142,158255,325498,167173) Then 1 Else 2 End
 ,  Ativo = Stp.FlTintAtv
 ,  FlPriorizar = 0
 ,  VendedorPrioritario = Vpo.VendedorPrioritario
 ,  Setor = NULL
 ,  CdVpd = Vpo.CdVpd
 ,  Obs = Vpo.Obs
 From #Vpo Vpo
 left join  Stik_ProgTinturaria Stp on Stp.CdVpo = Vpo.CdVpo and Stp.CdObj = Vpo.CdObj

 Left Join #PedRes PedRes on PedRes.CdObj = Vpo.CdObj and PedRes.CdVpo = Vpo.CdVpo

LEFT JOIN #FatDoc FatDoc
       ON FatDoc.CdVpo = Vpo.CdVpo
      AND FatDoc.CdObj = Vpo.CdObj

LEFT JOIN #FatSyncRes FatSyncRes
       ON FatSyncRes.CdVpo = Vpo.CdVpo
      AND FatSyncRes.CdObj = Vpo.CdObj

 left join  Stik_Maquina Maq on Maq.ID = Stp.MaquinaID

 Union

 Select Distinct
    Codigo = -1
 ,  Descricao = null
 ,  Detalhe = null
 ,  OcDoCliente = null
 ,  Cliente = null
 ,  Vendedor = null
 ,  DtPedido = null
 ,  DtEntrega = null
 ,  DtLeadTime = null
 ,  DiaEmAtrazo = 'SALDO -->'

 ,  Estoque =
              IsNull(Let.Qt, 0)
            + Sum(
                  Case
                      When FatSyncRes.CdVpo Is Not Null Then
                          Case
                              When IsNull(PedRes.Qt, 0) < 0 Then 0
                              Else IsNull(PedRes.Qt, 0)
                          End
                      Else
                          Case
                              When IsNull(PedRes.Qt, 0) - IsNull(FatDoc.Qt, 0) < 0 Then 0
                              Else IsNull(PedRes.Qt, 0) - IsNull(FatDoc.Qt, 0)
                          End
                  End
              )
            - Sum(IsNull(Vpo.QtVpo, 0) - IsNull(FatDoc.Qt, 0))
 ,  QtReserva = NULL
 ,  Maquina = Null
 ,  Mae = Vpo.CdObj
 ,  Nivel = 3
 ,  Ordem1 = 1
 ,  Ordem2 = Vpo.CdObj
 ,  Ordem3 = 1000000
 ,  Ordem4 = null
 ,  Marcar = 0
 ,  NrOrdem = null
 ,  PedidoEspecial = null
 ,  StaOrdem = null
 ,  DtOrdem = null
 ,  DtOrdIni = null
 ,  DtPrevisao = null
 ,  DtPrevMargem = null
 ,  DtPrevTin = null
 ,  DtPrevEmb = null
 ,  CdVpo = null
 ,  CdObj = null
 ,  ID = null
 ,  Ordenar = null
 ,  Ativo = null
 ,  FlPriorizar = 0
 ,  VendedorPrioritario = 0
 ,  Setor = NULL
 ,  CdVpd = NULL
 ,  Obs = NULL
 From #Vpo Vpo

 Left Join #PedRes PedRes on PedRes.CdObj = Vpo.CdObj and PedRes.CdVpo = Vpo.CdVpo

 Left join      (
                  Select  Let.CdObj

                  ,       Qt = Sum(Let.Qt)

                  From   #Estoque Let (nolock)
                  Where   Let.CdCcs = 13
                  Group by
                          Let.CdObj) Let on Let.CdObj = Vpo.CdObj

 Left Join #FatDoc FatDoc on FatDoc.CdVpo = Vpo.CdVpo and FatDoc.CdObj = Vpo.CdObj

 Left Join #FatSyncRes FatSyncRes on FatSyncRes.CdVpo = Vpo.CdVpo and FatSyncRes.CdObj = Vpo.CdObj

 group by
    Vpo.CdObj
 ,  Let.Qt

 Order By
    Ordem1
 ,  Ordem2
 ,  Ordem3
 ,  Ordem4

 IF ? = 0
 Begin
     select * from #Result
     Order By
        Ordem1
     ,  Ordem2
     ,  Ordem3
     ,  Ordem4

 End
 Else
 Begin
     select distinct r1.*
         into #Result1
       from #Result r1
         join #Result r2 on r2.Mae = r1.Codigo and r2.Nivel = 2
       join #Result r3 on r3.Mae = r2.Codigo and r3.Nivel = 3
      where r1.Nivel = 1
          AND Exists (
              select 1
                from #Result r3x
               where r3x.Nivel = 3
                 and r3x.Mae = r2.Codigo
                 and (
                      (r3x.DiaEmAtrazo = 'SALDO -->' and r3x.Estoque < 0)
                   or (r3x.NrOrdem is null and IsNull(r3x.DiaEmAtrazo,'') <> 'SALDO -->' and IsNull(r3x.Estoque,0) > 0)
                   or r3x.DtPrevisao is not null
                 )
          )

     UNION

     select distinct r2.*
       from #Result r1
         join #Result r2 on r2.Mae = r1.Codigo and r2.Nivel = 2
       join #Result r3 on r3.Mae = r2.Codigo and r3.Nivel = 3
      where r1.Nivel = 1
          AND Exists (
              select 1
                from #Result r3x
               where r3x.Nivel = 3
                 and r3x.Mae = r2.Codigo
                 and (
                      (r3x.DiaEmAtrazo = 'SALDO -->' and r3x.Estoque < 0)
                   or (r3x.NrOrdem is null and IsNull(r3x.DiaEmAtrazo,'') <> 'SALDO -->' and IsNull(r3x.Estoque,0) > 0)
                   or r3x.DtPrevisao is not null
                 )
          )

     select distinct *
         into #ResultPendente
         from #Result1
     union
     select distinct r3.*
       from #Result1 r1
         join #Result1 r2 on r2.Mae = r1.Codigo and r2.Nivel = 2
       join #Result r3 on r3.Mae = r2.Codigo and r3.Nivel = 3
        and (
             r3.DtPrevisao is not null
          or r3.DiaEmAtrazo = 'SALDO -->'
          or (r3.NrOrdem is null and IsNull(r3.DiaEmAtrazo,'') <> 'SALDO -->' and IsNull(r3.Estoque,0) > 0)
        )
      where r1.Nivel = 1

     select * from #ResultPendente
     Order By
        Ordem1
     ,  Ordem2
     ,  Ordem3
     ,  Ordem4
 End"""

        parametros = (
            cd_une, cd_une, cd_une,
            cd_vpd, cd_vpd,
            cd_cli, cd_cli,
            data_inicio, data_inicio,
            data_fim, data_fim,
            cd_obj, cd_obj,
            nome_artigo_like, nome_artigo_like,
            somente_atrasados,
            cd_obj_lin, cd_obj_lin,
            somente_pendentes
        )

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        cursor.execute(query, parametros)

        # Percorre todos os result sets nulos gerados por criacoes de #tabelas temporarias
        while cursor.description is None:
            if not cursor.nextset():
                break

        # Se apos varrer a execucao nao restar estrutura de colunas, retorna lista vazia
        if cursor.description is None:
            return jsonify([]), 200

        colunas = [column[0] for column in cursor.description]
        resultados = [serializar_linha(colunas, row) for row in cursor.fetchall()]

        return jsonify(resultados), 200

    except ValueError:
        return jsonify({"error": "Os filtros numéricos devem conter valores inteiros"}), 400

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@tracx_ApontamentoPost_bp.route('/consultar/movimentacao-estoque', methods=['GET'])
def consultar_entrada_embalagem():
    connection = None

    try:
        cd_une = request.args.get('cdUne', default=0, type=int)
        data_inicial = request.args.get('dataInicial')
        data_final = request.args.get('dataFinal')
        cd_artigo = request.args.get('cdArtigo', default=0, type=int)
        resumo = request.args.get('resumo', default='0').lower() in ('1', 'true', 'sim')

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        if resumo:
            sql_resumo = """
                SELECT
                    total = ISNULL(SUM(Mppite.QtMppite), 0),
                    artigos = COUNT(DISTINCT ObjArtigo.CdObj)
                FROM TbMpp Mpp
                LEFT JOIN TbMppite Mppite
                    ON Mppite.CdMpp = Mpp.CdMpp
                LEFT JOIN TbObj Obj
                    ON Obj.CdObj = Mppite.CdObj
                LEFT JOIN TbObj ObjArtigo
                    ON ObjArtigo.CdObj = Obj.CdObjMae
                WHERE
                    (
                        ? = 0
                        OR EXISTS (
                            SELECT 1
                            FROM TbArvUne ArvUne
                            WHERE ArvUne.CdUneFil = Mpp.CdUne
                              AND ArvUne.CdUne = ?
                        )
                    )
                    AND (
                        ? IS NULL
                        OR Mpp.DtMpp >= CAST(? AS DATE)
                    )
                    AND (
                        ? IS NULL
                        OR Mpp.DtMpp < DATEADD(DAY, 1, CAST(? AS DATE))
                    )
                    AND (
                        ? = 0
                        OR EXISTS (
                            SELECT 1
                            FROM TbArvObj ArvObjFil
                            WHERE ArvObjFil.CdObjFil = Mppite.CdObj
                              AND ArvObjFil.CdObj = ?
                        )
                    )
                    AND Mpp.CdTop = 142
            """
            cursor.execute(
                sql_resumo,
                (
                    cd_une, cd_une,
                    data_inicial, data_inicial,
                    data_final, data_final,
                    cd_artigo, cd_artigo
                )
            )
            row = cursor.fetchone()
            total = row[0] if row else 0
            artigos = row[1] if row else 0
            return jsonify({
                "total": float(total or 0),
                "artigos": int(artigos or 0),
            }), 200

        sql_query = """
            SELECT 
                Consulta.Artigo,
                Consulta.Codigo,
                Consulta.Mae,
                Consulta.Nivel,
                Consulta.QtEntrada,
                Consulta.Ordem1,
                Consulta.Ordem2,
                Consulta.Ordem3
            FROM (
                SELECT
                    Codigo = CONVERT(VARCHAR(10), Mpp.DtMpp, 103),
                    Artigo = CONVERT(VARCHAR(10), Mpp.DtMpp, 103),
                    QtEntrada = SUM(Mppite.QtMppite),
                    Mae = NULL,
                    Nivel = 1,
                    Ordem1 = CONVERT(VARCHAR(10), Mpp.DtMpp, 103),
                    Ordem2 = NULL,
                    Ordem3 = NULL
                FROM TbMpp Mpp
                LEFT JOIN TbMppite Mppite
                    ON Mppite.CdMpp = Mpp.CdMpp
                LEFT JOIN TbObj Obj
                    ON Obj.CdObj = Mppite.CdObj
                WHERE
                    (
                        ? = 0
                        OR EXISTS (
                            SELECT 1
                            FROM TbArvUne ArvUne
                            WHERE ArvUne.CdUneFil = Mpp.CdUne
                              AND ArvUne.CdUne = ?
                        )
                    )
                    AND (
                        ? IS NULL
                        OR Mpp.DtMpp >= CAST(? AS DATE)
                    )
                    AND (
                        ? IS NULL
                        OR Mpp.DtMpp < DATEADD(DAY, 1, CAST(? AS DATE))
                    )
                    AND (
                        ? = 0
                        OR EXISTS (
                            SELECT 1
                            FROM TbArvObj ArvObjFil
                            WHERE ArvObjFil.CdObjFil = Mppite.CdObj
                              AND ArvObjFil.CdObj = ?
                        )
                    )
                    AND Mpp.CdTop = 142
                GROUP BY
                    Mpp.DtMpp

                UNION

                SELECT
                    Codigo = CONVERT(VARCHAR(20), ObjArtigo.CdObj),
                    Artigo = ObjArtigo.NmObj,
                    QtEntrada = SUM(Mppite.QtMppite),
                    Mae = CONVERT(VARCHAR(10), Mpp.DtMpp, 103),
                    Nivel = 2,
                    Ordem1 = CONVERT(VARCHAR(10), Mpp.DtMpp, 103),
                    Ordem2 = ObjArtigo.CdObj,
                    Ordem3 = NULL
                FROM TbMpp Mpp
                LEFT JOIN TbMppite Mppite
                    ON Mppite.CdMpp = Mpp.CdMpp
                LEFT JOIN TbObj Obj
                    ON Obj.CdObj = Mppite.CdObj
                LEFT JOIN TbObj ObjArtigo
                    ON ObjArtigo.CdObj = Obj.CdObjMae
                WHERE
                    (
                        ? = 0
                        OR EXISTS (
                            SELECT 1
                            FROM TbArvUne ArvUne
                            WHERE ArvUne.CdUneFil = Mpp.CdUne
                              AND ArvUne.CdUne = ?
                        )
                    )
                    AND (
                        ? IS NULL
                        OR Mpp.DtMpp >= CAST(? AS DATE)
                    )
                    AND (
                        ? IS NULL
                        OR Mpp.DtMpp < DATEADD(DAY, 1, CAST(? AS DATE))
                    )
                    AND (
                        ? = 0
                        OR EXISTS (
                            SELECT 1
                            FROM TbArvObj ArvObjFil
                            WHERE ArvObjFil.CdObjFil = Mppite.CdObj
                              AND ArvObjFil.CdObj = ?
                        )
                    )
                    AND Mpp.CdTop = 142
                GROUP BY
                    Mpp.DtMpp,
                    ObjArtigo.CdObj,
                    ObjArtigo.NmObj

                UNION

                SELECT
                    Codigo = CONVERT(VARCHAR(20), Mppite.CdObj),
                    Artigo = Obj.NmObj,
                    QtEntrada = SUM(Mppite.QtMppite),
                    Mae = CONVERT(VARCHAR(20), ObjArtigo.CdObj),
                    Nivel = 3,
                    Ordem1 = CONVERT(VARCHAR(10), Mpp.DtMpp, 103),
                    Ordem2 = ObjArtigo.CdObj,
                    Ordem3 = Mppite.CdObj
                FROM TbMpp Mpp
                LEFT JOIN TbMppite Mppite
                    ON Mppite.CdMpp = Mpp.CdMpp
                LEFT JOIN TbObj Obj
                    ON Obj.CdObj = Mppite.CdObj
                LEFT JOIN TbObj ObjArtigo
                    ON ObjArtigo.CdObj = Obj.CdObjMae
                WHERE
                    (
                        ? = 0
                        OR EXISTS (
                            SELECT 1
                            FROM TbArvUne ArvUne
                            WHERE ArvUne.CdUneFil = Mpp.CdUne
                              AND ArvUne.CdUne = ?
                        )
                    )
                    AND (
                        ? IS NULL
                        OR Mpp.DtMpp >= CAST(? AS DATE)
                    )
                    AND (
                        ? IS NULL
                        OR Mpp.DtMpp < DATEADD(DAY, 1, CAST(? AS DATE))
                    )
                    AND (
                        ? = 0
                        OR EXISTS (
                            SELECT 1
                            FROM TbArvObj ArvObjFil
                            WHERE ArvObjFil.CdObjFil = Mppite.CdObj
                              AND ArvObjFil.CdObj = ?
                        )
                    )
                    AND Mpp.CdTop = 142
                GROUP BY
                    Mpp.DtMpp,
                    Mppite.CdObj,
                    ObjArtigo.CdObj,
                    Obj.NmObj
            ) Consulta
            ORDER BY
                CONVERT(DATE, Consulta.Ordem1, 103),
                Consulta.Ordem2,
                Consulta.Ordem3
        """

        filtros = (
            cd_une, cd_une,
            data_inicial, data_inicial,
            data_final, data_final,
            cd_artigo, cd_artigo
        )

        parametros = filtros + filtros + filtros

        cursor.execute(sql_query, parametros)

        colunas = [column[0] for column in cursor.description]
        resultados = [
            serializar_linha(colunas, row)
            for row in cursor.fetchall()
        ]

        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ==========================================================
# FUNÇÕES AUXILIARES (mesmo padrão do restante do projeto)
# ==========================================================

def serializar_linha(cols, row):
    linha = {}
    for col, valor in zip(cols, row):
        if isinstance(valor, (date, datetime)):
            linha[col] = valor.isoformat()
        elif isinstance(valor, Decimal):
            linha[col] = float(valor)
        else:
            linha[col] = valor
    return linha


def obter_ultimo_codigo_ean(cursor):
    cursor.execute('SELECT TOP 1 NrCao FROM TbEan ORDER BY ID DESC')
    resultado = cursor.fetchone()
    return resultado[0] if resultado else None


def gerar_proximo_ean(ultimo_codigo):
    """
    Gera o próximo EAN-13 a partir do último código cadastrado,
    mantendo o prefixo 789 e recalculando o dígito verificador.
    """
    if ultimo_codigo is None:
        raise ValueError("Não existe nenhum EAN-13 cadastrado para gerar o próximo código.")

    ultimo_codigo = str(ultimo_codigo).strip()

    if not ultimo_codigo.isdigit() or len(ultimo_codigo) != 13:
        raise ValueError("O último código cadastrado não possui um EAN-13 válido.")

    novo_codigo_base = int(ultimo_codigo[:-1]) + 1
    novo_codigo_str = str(novo_codigo_base).zfill(12)
    novo_codigo_str = "789" + novo_codigo_str[3:]

    soma = sum(
        int(novo_codigo_str[i]) * (3 if i % 2 == 1 else 1)
        for i in range(12)
    )
    digito_verificador = (10 - (soma % 10)) % 10

    return novo_codigo_str + str(digito_verificador)


def validar_ean13(codigo):
    codigo = str(codigo).strip()
    if not codigo.isdigit() or len(codigo) != 13:
        return False

    soma = sum(
        int(codigo[i]) * (3 if i % 2 == 1 else 1)
        for i in range(12)
    )
    digito_calculado = (10 - (soma % 10)) % 10
    return digito_calculado == int(codigo[-1])


def verificar_codigo_existente(cursor, novo_ean):
    cursor.execute("SELECT COUNT(*) FROM TbEan WHERE NrCao = ?", (novo_ean,))
    return cursor.fetchone()[0] > 0


# ==========================================================
# GET /ean13
# Lista todos os registros (equivalente a obter_todos_registros)
# ==========================================================

@tracx_ApontamentoPost_bp.route('/ean13', methods=['GET'])
def listar_ean13():
    conn = None
    try:
        conn = create_connection_EAN()
        cursor = conn.cursor()
        cursor.execute("SELECT ID, CdObj, NmObj, NrCao FROM TbEan ORDER BY ID DESC")
        cols = [col[0] for col in cursor.description]
        registros = [serializar_linha(cols, row) for row in cursor.fetchall()]
        return jsonify(registros), 200
    except Exception as e:
        return jsonify({"erro": f"Erro ao listar registros: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()


# ==========================================================
# GET /ean13/proximo
# Retorna o próximo EAN-13 sem cadastrar
# (equivalente a obter_ultimo_codigo_ean + gerar_proximo_ean)
# ==========================================================

@tracx_ApontamentoPost_bp.route('/ean13/proximo', methods=['GET'])
def proximo_ean13():
    conn = None
    try:
        conn = create_connection_EAN()
        cursor = conn.cursor()
        ultimo_codigo = obter_ultimo_codigo_ean(cursor)

        if ultimo_codigo is None:
            return jsonify({"erro": "Nenhum EAN-13 cadastrado ainda."}), 404

        proximo = gerar_proximo_ean(ultimo_codigo)
        return jsonify({"ultimo_ean": ultimo_codigo, "proximo_ean": proximo}), 200
    except ValueError as e:
        return jsonify({"erro": str(e)}), 400
    except Exception as e:
        return jsonify({"erro": f"Erro ao gerar próximo EAN: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()


# ==========================================================
# GET /ean13/pesquisar?busca=...
# Pesquisa por nome, EAN ou CdObj
# (equivalente a pesquisar_por_nome + pesquisar_por_ean)
# ==========================================================

@tracx_ApontamentoPost_bp.route('/ean13/pesquisar', methods=['GET'])
def pesquisar_ean13():
    termo = request.args.get('busca', '').strip()

    if not termo:
        return jsonify({"erro": "Informe o parâmetro 'busca' para pesquisar."}), 400

    conn = None
    try:
        conn = create_connection_EAN()
        cursor = conn.cursor()
        cursor.execute(
            """
            SELECT ID, CdObj, NmObj, NrCao
            FROM TbEan
            WHERE NmObj LIKE ?
               OR NrCao LIKE ?
               OR CAST(CdObj AS VARCHAR(50)) LIKE ?
            ORDER BY ID DESC
            """,
            (f"%{termo}%", f"%{termo}%", f"%{termo}%")
        )
        cols = [col[0] for col in cursor.description]
        resultados = [serializar_linha(cols, row) for row in cursor.fetchall()]

        if not resultados:
            return jsonify({"mensagem": "Nenhum registro encontrado."}), 404

        return jsonify(resultados), 200
    except Exception as e:
        return jsonify({"erro": f"Erro ao pesquisar registros: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()


# ==========================================================
# GET /ean13/<ean>
# Consulta um registro específico pelo código EAN
# ==========================================================

@tracx_ApontamentoPost_bp.route('/ean13/<string:ean>', methods=['GET'])
def obter_por_ean(ean):
    conn = None
    try:
        conn = create_connection_EAN()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT ID, CdObj, NmObj, NrCao FROM TbEan WHERE NrCao = ?",
            (ean,)
        )
        cols = [col[0] for col in cursor.description]
        row = cursor.fetchone()

        if not row:
            return jsonify({"erro": "EAN-13 não encontrado."}), 404

        return jsonify(serializar_linha(cols, row)), 200
    except Exception as e:
        return jsonify({"erro": f"Erro ao consultar registro: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()


# ==========================================================
# GET /ean13/objeto/<cd_obj>
# Consulta registro(s) pelo código do objeto (CdObj)
# ==========================================================

@tracx_ApontamentoPost_bp.route('/ean13/objeto/<int:cd_obj>', methods=['GET'])
def obter_por_cdobj(cd_obj):
    conn = None
    try:
        conn = create_connection_EAN()
        cursor = conn.cursor()
        cursor.execute(
            "SELECT ID, CdObj, NmObj, NrCao FROM TbEan WHERE CdObj = ?",
            (cd_obj,)
        )
        cols = [col[0] for col in cursor.description]
        resultados = [serializar_linha(cols, row) for row in cursor.fetchall()]

        if not resultados:
            return jsonify({"erro": "Nenhum registro encontrado para este CdObj."}), 404

        return jsonify(resultados), 200
    except Exception as e:
        return jsonify({"erro": f"Erro ao consultar registro: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()


# ==========================================================
# GET /ean13/verificar/<ean>
# Verifica se um EAN-13 já existe
# (equivalente a verificar_codigo_existente)
# ==========================================================

@tracx_ApontamentoPost_bp.route('/ean13/verificar/<string:ean>', methods=['GET'])
def verificar_ean13(ean):
    conn = None
    try:
        conn = create_connection_EAN()
        cursor = conn.cursor()
        existe = verificar_codigo_existente(cursor, ean)
        return jsonify({"ean": ean, "existe": existe}), 200
    except Exception as e:
        return jsonify({"erro": f"Erro ao verificar EAN: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()


# ==========================================================
# POST /ean13
# Cadastra um novo EAN-13, gerando automaticamente o próximo código
# (equivalente a cadastrar_ean + cadastrar_ean_interface)
# Body esperado (JSON): { "cd_obj": 123, "nm_obj": "Nome do produto" }
# ==========================================================

@tracx_ApontamentoPost_bp.route('/ean13', methods=['POST'])
def cadastrar_ean13():
    data_json = request.get_json(silent=True) or {}
    cd_obj = data_json.get('cd_obj')
    nm_obj = str(data_json.get('nm_obj', '')).strip()

    if cd_obj is None or not nm_obj:
        return jsonify({"erro": "Os campos 'cd_obj' e 'nm_obj' são obrigatórios."}), 400

    conn = None
    try:
        conn = create_connection_EAN()
        cursor = conn.cursor()

        ultimo_codigo = obter_ultimo_codigo_ean(cursor)
        novo_ean = gerar_proximo_ean(ultimo_codigo)

        # Confere novamente antes de gravar, para evitar corrida entre requisições
        if verificar_codigo_existente(cursor, novo_ean):
            return jsonify({"erro": "Este código EAN-13 já existe no banco de dados."}), 409

        cursor.execute(
            "INSERT INTO TbEan (CdObj, NmObj, NrCao) VALUES (?, ?, ?)",
            (cd_obj, nm_obj, novo_ean)
        )
        conn.commit()

        return jsonify({
            "mensagem": "EAN-13 cadastrado com sucesso.",
            "cd_obj": cd_obj,
            "nm_obj": nm_obj,
            "novo_ean": novo_ean
        }), 201
    except ValueError as e:
        return jsonify({"erro": str(e)}), 400
    except Exception as e:
        return jsonify({"erro": f"Erro ao cadastrar EAN-13: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()


# ==========================================================
# PATCH /ean13/<ean>
# Atualiza CdObj e/ou NmObj de um registro existente
# Body esperado (JSON): { "cd_obj": 123, "nm_obj": "Novo nome" }
# ==========================================================

@tracx_ApontamentoPost_bp.route('/ean13/<string:ean>', methods=['PATCH'])
def atualizar_ean13(ean):
    data_json = request.get_json(silent=True) or {}
    cd_obj = data_json.get('cd_obj')
    nm_obj = data_json.get('nm_obj')

    if cd_obj is None and nm_obj is None:
        return jsonify({"erro": "Informe ao menos um campo para atualizar ('cd_obj' ou 'nm_obj')."}), 400

    conn = None
    try:
        conn = create_connection_EAN()
        cursor = conn.cursor()

        cursor.execute("SELECT COUNT(*) FROM TbEan WHERE NrCao = ?", (ean,))
        if cursor.fetchone()[0] == 0:
            return jsonify({"erro": "EAN-13 não encontrado."}), 404

        campos = []
        valores = []

        if cd_obj is not None:
            campos.append("CdObj = ?")
            valores.append(cd_obj)

        if nm_obj is not None:
            campos.append("NmObj = ?")
            valores.append(str(nm_obj).strip())

        valores.append(ean)

        query = f"UPDATE TbEan SET {', '.join(campos)} WHERE NrCao = ?"
        cursor.execute(query, tuple(valores))
        conn.commit()

        return jsonify({"mensagem": "Registro atualizado com sucesso.", "ean": ean}), 200
    except Exception as e:
        return jsonify({"erro": f"Erro ao atualizar registro: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()


# ==========================================================
# DELETE /ean13/<ean>
# Remove um cadastro de EAN-13
# ==========================================================

@tracx_ApontamentoPost_bp.route('/ean13/<string:ean>', methods=['DELETE'])
def excluir_ean13(ean):
    conn = None
    try:
        conn = create_connection_EAN()
        cursor = conn.cursor()

        cursor.execute("SELECT COUNT(*) FROM TbEan WHERE NrCao = ?", (ean,))
        if cursor.fetchone()[0] == 0:
            return jsonify({"erro": "EAN-13 não encontrado."}), 404

        cursor.execute("DELETE FROM TbEan WHERE NrCao = ?", (ean,))
        conn.commit()

        return jsonify({"mensagem": "Registro excluído com sucesso.", "ean": ean}), 200
    except Exception as e:
        return jsonify({"erro": f"Erro ao excluir registro: {str(e)}"}), 500
    finally:
        if conn:
            conn.close()


@tracx_ApontamentoPost_bp.route(
    '/consultar/pedidos-pendentes-tinturaria',
    methods=['GET']
)
def consultar_pedidos_pendentes_tinturaria():
    connection = None

    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;

            SELECT
                NrDiasDtPrevisao
            INTO #Stik_ParamTint
            FROM Stik_ParamTint;


            -- PEDIDOS
            SELECT
                Vpo.CdVpo,
                Vpo.CdObj,
                Vpo.QtVpo,
                Vpo.QtVpoFatCan,
                Obj.NmObj,
                Vpd.CdUne,
                Vpd.CdVpd,
                Vpd.DtVpdInc,
                Cli.NmCli,
                LotVen.CdLot,
                LotVen.NmLot,
                Vpo.DtVpoEnt,
                VendedorPrioritario = ISNULL(Opl.FlOpl, 0),
                OcDoCliente = (
                    SELECT TOP 1 VpdCrc.TtVpdcrc
                    FROM TbVpdcrc VpdCrc
                    WHERE VpdCrc.CdVpd = Vpd.CdVpd
                      AND VpdCrc.CdCrc = 155
                ),
                Detalhe = LotDet.NmLot,
                Setor = Obj.CdObjLin,
                Obs = Obs.TtObs,
                DtVpdAutFat = Vpd.DtVpdAutFat,
                Res.QtReserva
            INTO #Vpo
            FROM TbVpo Vpo
            INNER JOIN TbVpd Vpd
                ON Vpd.CdVpd = Vpo.CdVpd
            INNER JOIN TbObj Obj
                ON Obj.CdObj = Vpo.CdObj
            INNER JOIN TbCli Cli
                ON Cli.CdCli = Vpd.CdCli
            LEFT JOIN TbLot LotVen
                ON LotVen.CdLot = Vpo.CdLotVen
            LEFT JOIN TbLot LotDet
                ON LotDet.CdLot = Vpo.CdLot
            LEFT JOIN TbOpl Opl
                ON Opl.CdLot = LotVen.CdLot
               AND Opl.CdCrc = 174
            LEFT JOIN TbObs Obs
                ON Obs.CdObs = Vpd.CdObs
            LEFT JOIN Stik_Pedido_Reserva Res
                ON Res.CdObj = Vpo.CdObj
               AND Res.CdVpo = Vpo.CdVpo
               AND Res.CdLot = Vpo.CdLot
            LEFT JOIN (
                SELECT
                    Let.CdUne,
                    Let.CdObj,
                    Let.CdCcs,
                    Let.CdLotAtv,
                    Qt = SUM((Let.TpLetSin - 2) * Let.QtLet)
                FROM TbLet Let WITH (NOLOCK)
                WHERE Let.DtLet <= GETDATE()
                  AND Let.CdCcs = 13
                  AND Let.CdLotAtv = 2026
                GROUP BY
                    Let.CdUne,
                    Let.CdObj,
                    Let.CdCcs,
                    Let.CdLotAtv
            ) Let
                ON Let.CdObj = Vpo.CdObj
            WHERE
                (
                    2 = 0
                    OR EXISTS (
                        SELECT 1
                        FROM TbArvUne ArvUne
                        WHERE ArvUne.CdUneFil = Vpd.CdUne
                          AND ArvUne.CdUne = 2
                    )
                )
                AND Vpd.TpVpdSta = 1
                AND Vpd.FlVpdFec = 1
                AND Vpd.FlVpdAutFat = 1
                AND Vpo.CdFin IN (2, 28)
                AND (Vpo.CdObj = 0 OR 0 = 0)
                AND Vpo.TpVpoSta = 1
                AND (Obj.NmObj LIKE '%%' OR '%%' = '')
                AND (
                    1 = 0
                    OR CONVERT(INT, DATEDIFF(DAY, Vpd.DtVpdInc, GETDATE())) > 0
                )
                AND Vpd.CdTop <> 453
                AND (Obj.CdObjLin = 0 OR 0 = 0);


            -- ESTOQUE
            SELECT
                Let.CdUne,
                Let.CdObj,
                Let.CdLot,
                Let.CdCcs,
                Let.CdLotAtv,
                Qt = SUM((Let.TpLetSin - 2) * Let.QtLet)
            INTO #Estoque
            FROM TbLet Let WITH (NOLOCK)
            WHERE Let.DtLet <= GETDATE()
              AND Let.CdCcs = 13
              AND Let.CdLotAtv = 2026
              AND EXISTS (
                  SELECT 1
                  FROM #Vpo
                  WHERE CdObj = Let.CdObj
              )
            GROUP BY
                Let.CdUne,
                Let.CdObj,
                Let.CdLot,
                Let.CdCcs,
                Let.CdLotAtv;


            -- FATURAMENTO
            SELECT
                Rco.CdVpo,
                Rco.CdObj,
                Qt = SUM(ISNULL(Rco.QtRcoExp, 0))
            INTO #Rco
            FROM TbRco Rco
            INNER JOIN #Vpo Vpo1
                ON Vpo1.CdVpo = Rco.CdVpo
            INNER JOIN TbVpo Vpo
                ON Vpo.CdVpo = Rco.CdVpo
               AND Rco.TpRcoSta <> 3
               AND Rco.CdFin = 28
            GROUP BY
                Rco.CdVpo,
                Rco.CdObj;


            -- NÍVEL 1: ARTIGO
            SELECT DISTINCT
                Codigo = Vpo.CdObj,
                Descricao = Vpo.NmObj,
                Detalhe = CONVERT(VARCHAR, NULL),
                PedidoEspecial = CAST(NULL AS VARCHAR(10)),
                NrOrdem = NULL,
                DtPrevMargem = Stp.DtPrevisao + (
                    SELECT ISNULL(NrDiasDtPrevisao, 0)
                    FROM #Stik_ParamTint
                ),
                QtPedido = NULL,
                QtReserva = NULL,
                QtAcabado = NULL,
                SaldoPendente = NULL,
                Setor = Vpo.Setor,
                Nivel = 1,
                Mae = NULL,
                Ord1 = Vpo.NmObj,
                Ord2 = NULL,
                Ord3 = NULL,
                Situacao = CONVERT(VARCHAR, NULL),
                Marcar = NULL,
                Rn = NULL
            INTO #Vpo1
            FROM #Vpo Vpo
            LEFT JOIN Stik_ProgTinturaria Stp
                ON Stp.CdVpo = Vpo.CdVpo
               AND Stp.CdObj = Vpo.CdObj
            LEFT JOIN (
                SELECT
                    Res.CdObj,
                    Vpo.CdVpo,
                    Qt = SUM(ISNULL(Res.QtReserva, Met.QtMet))
                         - ISNULL(EntRet.Qt, 0)
                FROM Stik_Pedido_Reserva Res WITH (NOLOCK)
                INNER JOIN TbVpo Vpo WITH (NOLOCK)
                    ON Vpo.CdVpo = Res.CdVpo
                INNER JOIN TbMet Met WITH (NOLOCK)
                    ON Met.CdMet = Res.CdMet
                LEFT JOIN (
                    SELECT
                        Res.CdObj,
                        Res.CdVpo,
                        Qt = SUM(ISNULL(Res.QtReserva, Met.QtMet))
                    FROM Stik_Pedido_Reserva Res WITH (NOLOCK)
                    LEFT JOIN TbMet Met WITH (NOLOCK)
                        ON Met.CdMet = Res.CdMet
                    WHERE Res.TpResSin = 3
                    GROUP BY
                        Res.CdObj,
                        Res.CdVpo
                ) EntRet
                    ON EntRet.CdObj = Res.CdObj
                   AND EntRet.CdVpo = Res.CdVpo
                WHERE Res.TpResSin = 1
                GROUP BY
                    Res.CdObj,
                    Vpo.CdVpo,
                    EntRet.Qt
            ) PedRes
                ON PedRes.CdObj = Vpo.CdObj
               AND PedRes.CdVpo = Vpo.CdVpo
            LEFT JOIN (
                SELECT
                    Let.CdObj,
                    Qt = SUM(Let.Qt)
                FROM #Estoque Let WITH (NOLOCK)
                WHERE Let.CdCcs = 13
                GROUP BY Let.CdObj
            ) Let
                ON Let.CdObj = Vpo.CdObj
            LEFT JOIN (
                SELECT
                    Rco.CdVpo,
                    Qt = SUM(Rco.Qt)
                FROM #Rco Rco
                GROUP BY Rco.CdVpo
            ) FatDoc
                ON FatDoc.CdVpo = Vpo.CdVpo
            GROUP BY
                Vpo.CdObj,
                Vpo.NmObj,
                Let.Qt,
                PedRes.Qt,
                QtVpoFatCan,
                FatDoc.Qt,
                Vpo.QtVpo,
                Stp.DtPrevisao,
                Vpo.Setor
            HAVING
                (
                    ISNULL(Vpo.QtVpo, 0)
                    - ISNULL(FatDoc.Qt, 0)
                    + ISNULL(Vpo.QtVpoFatCan, 0)
                )
                - (
                    ISNULL(PedRes.Qt, 0)
                    + ISNULL(QtVpoFatCan, 0)
                    - ISNULL(FatDoc.Qt, 0)
                )
                - ISNULL(Let.Qt, 0) > 0;


            -- NÍVEL 2: PEDIDO
            SELECT
                Codigo = Vpo.CdVpo,
                Descricao = Vpo.NmCli,
                Detalhe = Vpo.Detalhe,
                PedidoEspecial = (
                    SELECT TOP 1
                        CASE E.PedidoEspecial
                            WHEN 1 THEN 'Sim'
                            WHEN 2 THEN 'Não'
                            ELSE NULL
                        END
                    FROM Stik_PCP_PEDIDOESPECIAL E
                    WHERE E.NrOrdem = Stp.NrOrdem
                ),
                NrOrdem = Stp.NrOrdem,
                DtPrevMargem = Stp.DtPrevisao + (
                    SELECT ISNULL(NrDiasDtPrevisao, 0)
                    FROM #Stik_ParamTint
                ),
                QtPedido =
                    ISNULL(Vpo.QtVpo, 0)
                    - ISNULL(FatDoc.Qt, 0)
                    + ISNULL(Vpo.QtVpoFatCan, 0),
                QtReserva =
                    ISNULL(PedRes.Qt, 0)
                    + ISNULL(QtVpoFatCan, 0)
                    - ISNULL(FatDoc.Qt, 0),
                QtAcabado = ISNULL(Let.Qt, 0),
                SaldoPendente =
                    (
                        ISNULL(Vpo.QtVpo, 0)
                        - ISNULL(FatDoc.Qt, 0)
                        + ISNULL(Vpo.QtVpoFatCan, 0)
                    )
                    - (
                        ISNULL(PedRes.Qt, 0)
                        + ISNULL(QtVpoFatCan, 0)
                        - ISNULL(FatDoc.Qt, 0)
                    )
                    - ISNULL(Let.Qt, 0),
                Setor = Vpo.Setor,
                Nivel = 2,
                Mae = NULL,
                Ord1 = Vpo.NmObj,
                Ord2 = Vpo.CdVpo,
                Ord3 = NULL,
                Situacao =
                    CASE
                        WHEN S.TpStatus = 1 THEN 'NA FILA'
                        WHEN S.TpStatus = 2 THEN 'REVISÃO'
                        WHEN S.TpStatus = 3 THEN 'EM PROCESSO DE EMBALAGEM'
                        WHEN S.TpStatus = 4 THEN 'FILA DO TUNEL'
                        WHEN S.TpStatus = 5
                            THEN 'TUNEL PARA ENTRAR NA EXPEDIÇÃO'
                    END,
                Marcar = NULL
            INTO #Vpo2
            FROM #Vpo Vpo
            LEFT JOIN Stik_ProgTinturaria Stp
                ON Stp.CdVpo = Vpo.CdVpo
               AND Stp.CdObj = Vpo.CdObj
            LEFT JOIN (
                SELECT
                    Res.CdObj,
                    Vpo.CdVpo,
                    Qt = SUM(ISNULL(Res.QtReserva, Met.QtMet))
                         - ISNULL(EntRet.Qt, 0)
                FROM Stik_Pedido_Reserva Res WITH (NOLOCK)
                INNER JOIN TbVpo Vpo WITH (NOLOCK)
                    ON Vpo.CdVpo = Res.CdVpo
                INNER JOIN TbMet Met WITH (NOLOCK)
                    ON Met.CdMet = Res.CdMet
                LEFT JOIN (
                    SELECT
                        Res.CdObj,
                        Res.CdVpo,
                        Qt = SUM(ISNULL(Res.QtReserva, Met.QtMet))
                    FROM Stik_Pedido_Reserva Res WITH (NOLOCK)
                    LEFT JOIN TbMet Met WITH (NOLOCK)
                        ON Met.CdMet = Res.CdMet
                    WHERE Res.TpResSin = 3
                    GROUP BY
                        Res.CdObj,
                        Res.CdVpo
                ) EntRet
                    ON EntRet.CdObj = Res.CdObj
                   AND EntRet.CdVpo = Res.CdVpo
                WHERE Res.TpResSin = 1
                GROUP BY
                    Res.CdObj,
                    Vpo.CdVpo,
                    EntRet.Qt
            ) PedRes
                ON PedRes.CdObj = Vpo.CdObj
               AND PedRes.CdVpo = Vpo.CdVpo
            LEFT JOIN (
                SELECT
                    Let.CdObj,
                    Qt = SUM(Let.Qt)
                FROM #Estoque Let WITH (NOLOCK)
                WHERE Let.CdCcs = 13
                GROUP BY Let.CdObj
            ) Let
                ON Let.CdObj = Vpo.CdObj
            LEFT JOIN (
                SELECT
                    Rco.CdVpo,
                    Qt = SUM(Rco.Qt)
                FROM #Rco Rco
                GROUP BY Rco.CdVpo
            ) FatDoc
                ON FatDoc.CdVpo = Vpo.CdVpo
            LEFT JOIN Stik_Embalagem_Status S
                ON S.CdVpo = Vpo.CdVpo
            GROUP BY
                Vpo.NmObj,
                Let.Qt,
                Vpo.CdVpo,
                Vpo.NmCli,
                Vpo.Detalhe,
                Stp.NrOrdem,
                Stp.DtPrevisao,
                PedRes.Qt,
                QtVpoFatCan,
                FatDoc.Qt,
                Vpo.Setor,
                Vpo.QtVpo,
                S.TpStatus
            HAVING
                (
                    ISNULL(Vpo.QtVpo, 0)
                    - ISNULL(FatDoc.Qt, 0)
                    + ISNULL(Vpo.QtVpoFatCan, 0)
                )
                - (
                    ISNULL(PedRes.Qt, 0)
                    + ISNULL(QtVpoFatCan, 0)
                    - ISNULL(FatDoc.Qt, 0)
                )
                - ISNULL(Let.Qt, 0) > 0;


            SELECT
                *,
                Rn = ROW_NUMBER() OVER (
                    PARTITION BY Ord1
                    ORDER BY Ord1, Ord2, Ord3
                )
            INTO #TmpVpo2
            FROM #Vpo2;


            UPDATE #TmpVpo2
            SET
                QtAcabado = 0,
                SaldoPendente = QtPedido - QtReserva
            WHERE Nivel = 2
              AND Rn > 1;


            -- NÍVEL 3: TOTAL
            SELECT DISTINCT
                Codigo = MAX(Codigo),
                Descricao = 'TOTAL',
                Detalhe = CONVERT(VARCHAR, NULL),
                PedidoEspecial = CAST(NULL AS VARCHAR(10)),
                NrOrdem = NULL,
                DtPrevMargem = DtPrevMargem,
                QtPedido = SUM(QtPedido),
                QtReserva = SUM(QtReserva),
                QtAcabado = SUM(QtAcabado),
                SaldoPendente = SUM(SaldoPendente),
                Setor = Vpo.Setor,
                Nivel = 3,
                Mae = NULL,
                Ord1 = Ord1,
                Ord2 = MAX(Codigo),
                Ord3 = 100000000,
                Situacao = CONVERT(VARCHAR, NULL),
                Marcar = NULL,
                Rn = NULL
            INTO #Vpo3
            FROM #TmpVpo2 Vpo
            GROUP BY
                Ord1,
                DtPrevMargem,
                Vpo.Setor;


            -- RESULTADO FINAL
            SELECT
                Codigo,
                Descricao,
                Detalhe,
                PedidoEspecial,
                NrOrdem,
                DtPrevMargem = NULL,
                QtPedido,
                QtReserva,
                QtAcabado,
                SaldoPendente,
                Setor = NULL,
                Nivel,
                Mae,
                Ord1,
                Ord2,
                Ord3,
                Situacao,
                Marcar,
                Rn
            FROM #Vpo1 Vpo
            WHERE Vpo.Setor = 0 OR 0 = 0

            UNION

            SELECT
                Codigo,
                Descricao,
                Detalhe,
                PedidoEspecial,
                NrOrdem,
                DtPrevMargem,
                QtPedido,
                QtReserva,
                QtAcabado,
                SaldoPendente,
                Setor =
                    CASE
                        WHEN Vpo.Setor = 36554 THEN 'Tecelagem'
                        WHEN Vpo.Setor = 10180 THEN 'Jacquard'
                    END,
                Nivel,
                Mae,
                Ord1,
                Ord2,
                Ord3,
                Situacao,
                Marcar,
                Rn
            FROM #TmpVpo2 Vpo
            WHERE Vpo.Setor = 0 OR 0 = 0

            UNION

            SELECT
                Codigo,
                Descricao,
                Detalhe,
                PedidoEspecial,
                NrOrdem,
                DtPrevMargem = NULL,
                QtPedido,
                QtReserva,
                QtAcabado,
                SaldoPendente,
                Setor = NULL,
                Nivel,
                Mae,
                Ord1,
                Ord2,
                Ord3,
                Situacao,
                Marcar,
                Rn
            FROM #Vpo3 Vpo
            WHERE Vpo.Setor = 0 OR 0 = 0

            ORDER BY Ord1, Ord2, Ord3;
        """

        cursor.execute(sql_query)

        # Localiza o SELECT final do lote SQL.
        while cursor.description is None:
            if not cursor.nextset():
                return jsonify({
                    "error": "A consulta não retornou resultados"
                }), 500

        colunas = [column[0] for column in cursor.description]

        resultados = [
            serializar_linha(colunas, row)
            for row in cursor.fetchall()
        ]

        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({
            "error": str(e)
        }), 500

    finally:
        if connection:
            try:
                cursor = connection.cursor()

                cursor.execute("""
                    DROP TABLE IF EXISTS #Stik_ParamTint;
                    DROP TABLE IF EXISTS #Estoque;
                    DROP TABLE IF EXISTS #Vpo;
                    DROP TABLE IF EXISTS #Rco;
                    DROP TABLE IF EXISTS #Vpo1;
                    DROP TABLE IF EXISTS #Vpo2;
                    DROP TABLE IF EXISTS #TmpVpo2;
                    DROP TABLE IF EXISTS #Vpo3;
                """)

                connection.commit()

            except Exception:
                pass

            connection.close()
