from flask import Blueprint, request, jsonify
from database.server import create_connection_tinturaria 
from datetime import datetime, timedelta

wms_faturamento_bp = Blueprint('wms_faturamento', __name__)

# ==============================================================================
# ROTA 1: POST - INCLUIR NA FILA DE FATURAMENTO
# ==============================================================================
@wms_faturamento_bp.route('/consulta/wms/fila/faturar', methods=['POST'])
def incluir_na_fila():
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "JSON inválido"}), 400

        # Recupera dados do JSON
        cd_vpd      = data.get("cd_vpd")
        cd_vpo      = data.get("cd_vpo")
        quantidade  = data.get("quantidade")
        nr_romaneio = data.get("nr_romaneio")
        cd_usr      = data.get("cd_usr")  # Pode ser None

        # Validação básica
        if not all([cd_vpd, quantidade, nr_romaneio]):
            return jsonify({"error": "Campos obrigatórios: cd_vpd, quantidade, nr_romaneio"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        # Insere e retorna o ID gerado (SCOPE_IDENTITY)
        # sql = """
        #     INSERT INTO Stik_WMS_Faturamento_Fila (
        #         Status, CdVpd, CdVpo, Quantidade, NrRomaneio, CdUsr, Origem, DtInclusao
        #     ) VALUES (
        #         'PENDENTE', ?, ?, ?, ?, ?, 'API', GETDATE()
        #     );
            
        #     SELECT SCOPE_IDENTITY();
        # """

        sql = """
            SET NOCOUNT ON;

            INSERT INTO Stik_WMS_Faturamento_Fila (
                Status, CdVpd, CdVpo, Quantidade, NrRomaneio, CdUsr, Origem, DtInclusao
            ) VALUES (
                'PENDENTE', ?, ?, ?, ?, ?, 'API', GETDATE()
            );

            SELECT SCOPE_IDENTITY();
        """
        
        cursor.execute(sql, (cd_vpd, cd_vpo, quantidade, nr_romaneio, cd_usr))
        row = cursor.fetchone()
        connection.commit()

        if row and row[0]:
            id_fila = int(row[0])
            return jsonify({
                "message": "Enviado para fila com sucesso",
                "id_fila": id_fila,
                "status": "PENDENTE"
            }), 201
        else:
            return jsonify({"error": "Falha ao gerar ID da fila"}), 500

    except Exception as e:
        if connection: connection.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        if connection: connection.close()

# ==============================================================================
# ROTA 2: GET - CONSULTAR STATUS DO PROCESSAMENTO
# ==============================================================================
@wms_faturamento_bp.route('/consulta/wms/fila/faturar/<int:id_fila>', methods=['GET'])
def consultar_status(id_fila):
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql = """
            SELECT Status, MsgErro, CdFat, DtInclusao, DtInicioProc, DtFimProc
            FROM Stik_WMS_Faturamento_Fila
            WHERE IDFila = ?
        """
        cursor.execute(sql, (id_fila,))
        row = cursor.fetchone()

        if not row:
            return jsonify({"error": "IDFila não encontrado"}), 404

        # 0:Status, 1:MsgErro, 2:CdFat, 3:DtInclusao, 4:DtInicioProc, 5:DtFimProc
        status_atual = row[0]
        msg_erro = row[1]
        cd_fat = row[2]
        dt_inclusao = row[3]
        dt_inicio = row[4]
        dt_fim = row[5]

        return jsonify({
            "id_fila": id_fila,
            "status": status_atual,
            "msg_erro": msg_erro,
            "cd_fat": cd_fat,
            "dt_inclusao": dt_inclusao.isoformat() if dt_inclusao else None,
            "dt_inicio_proc": dt_inicio.isoformat() if dt_inicio else None,
            "dt_fim_proc": dt_fim.isoformat() if dt_fim else None,
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection: connection.close()



# ==============================================================================
# ROTA 3: GET - CONSULTAR NOTAS CANCELADAS POR PERÍODO
# ==============================================================================

@wms_faturamento_bp.route('/consulta/wms/notas_canceladas/<data_inicial>/<data_final>', methods=['GET'])
def consultar_notas_canceladas(data_inicial, data_final):
    connection = None
    try:
        cliente = request.args.get("cliente")
        sku = request.args.get("sku")
        lote = request.args.get("lote")

        try:
            dt_ini = datetime.strptime(data_inicial, '%Y-%m-%d')
            dt_fim = datetime.strptime(data_final, '%Y-%m-%d') + timedelta(days=1)
        except ValueError:
            return jsonify({
                "error": "Datas inválidas. Use o formato YYYY-MM-DD."
            }), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql = """
        SELECT DISTINCT
            DOC             = Rcd.CdRcd,
            Pedido          = Vpd.CdVpd,
            Data            = Rcd.DtRcdEmi,
            Empresa         = Une.NmUne,
            Situacao        = Rcd.TpRcdSta,
            TipoDeOperacao  = Top1.NmTop,
            TipoDeDocumento = Tdo.NmTdo,
            NrNfe           = Ffm.NrFfm,
            NrDC            = Rcd.NrRcd,
            FormaDePagto    = Fpg.NmFpg,
            Cliente         = Cli.NmCli,
            Cod_SKU         = Rco.CdObj,
            SKU             = Obj.NmObj,
            CdLot           = Rco.CdLot,
            Lote            = Lot.NmLot,
            QtRco           = Rco.QtRco
        FROM TbRcd Rcd
        LEFT JOIN TbRco Rco ON Rco.CdRcd = Rcd.CdRcd
        LEFT JOIN TbVpo Vpo ON Vpo.CdVpo = Rco.CdVpo
        LEFT JOIN TbVpd Vpd ON Vpd.CdVpd = Vpo.CdVpd
        JOIN TbUne Une ON Une.CdUne = Rcd.CdUne
        JOIN TbCli Cli ON Cli.CdCli = Rcd.CdCli
        JOIN TbTop Top1 ON Top1.CdTop = Rcd.CdTop
        JOIN TbTdo Tdo ON Tdo.CdTdo = Rcd.CdTdo
        LEFT JOIN TbFfm Ffm ON Ffm.CdFfm = Rcd.FolhaDeFormularioID_Nfe
        LEFT JOIN TbFrn FrnTrp ON FrnTrp.CdFrn = Rcd.CdFrnTrp
        LEFT JOIN TbFpg Fpg ON Fpg.CdFpg = Rcd.CdFpg
        JOIN TbObj Obj ON Obj.CdObj = Rco.CdObj
        JOIN TbLot Lot ON Lot.CdLot = Rco.CdLot
        WHERE
            Rcd.DtRcdEmi >= ?
            AND Rcd.DtRcdEmi < ?
            AND (
                    Rcd.TpRcdSta = 3
                    OR (Rcd.CdTop = 98 AND Rcd.TpRcdSta = 2)
            )
            AND Rcd.CdTop IN (97,98,378,391,598)
        """

        params = [dt_ini, dt_fim]

        if cliente:
            sql += " AND Cli.CdCli = ?"
            params.append(cliente)

        if sku:
            sql += " AND Rco.CdObj = ?"
            params.append(int(sku))

        if lote:
            sql += " AND Rco.CdLot = ?"
            params.append(int(lote))

        cursor.execute(sql, params)

        columns = [col[0] for col in cursor.description]
        dados = [dict(zip(columns, row)) for row in cursor.fetchall()]

        return jsonify(dados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ==============================================================================
# ROTA 4: GET - CONSULTAR FATURAMENTOS DISPONÍVEIS PARA EMISSÃO NFE
# ==============================================================================
@wms_faturamento_bp.route('/consulta/wms/faturamento/disponiveis-nfe', methods=['GET'])
def consultar_faturamentos_disponiveis_nfe():
    connection = None
    try:
        nr_romaneio = request.args.get("nr_romaneio")
        cd_fat = request.args.get("cd_fat")
        status_pos = request.args.get("status_pos")

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql = """
            SELECT
                Fila.CdFat,
                Fila.NrRomaneio,
                QtdeItens = COUNT(DISTINCT Fila.CdVpo),
                QtdePedidos = COUNT(DISTINCT Fila.CdVpd),
                QuantidadeTotal = SUM(Fila.Quantidade),
                PrimeiroEnvio = MIN(Fila.DtInclusao),
                UltimoProcessamento = MAX(Fila.DtFimProc),

                StatusPosProcesso = ISNULL(Pos.Status, 'NAO_ENVIADO'),
                Pos.IDPosProcesso,
                Pos.CodigoVeiculo,
                Pos.DescricaoVeiculo,
                Pos.Motorista,
                Pos.CdLocVei,
                Pos.CdTdr,
                Pos.CdFtr,
                Pos.CdFve,
                Pos.CdFro,
                Pos.PesoTotal,
                Pos.VolumeTotal,
                Pos.MsgErro,
                Pos.Tentativas,
                Pos.DtInclusao AS DtInclusaoPos,
                Pos.DtInicioProc AS DtInicioProcPos,
                Pos.DtFimProc AS DtFimProcPos
            FROM Stik_WMS_Faturamento_Fila Fila WITH (NOLOCK)
            LEFT JOIN Stik_WMS_Faturamento_PosProcesso Pos WITH (NOLOCK)
                   ON Pos.CdFat = Fila.CdFat
            WHERE Fila.Status = 'CONCLUIDO'
              AND Fila.CdFat IS NOT NULL
        """

        params = []

        if nr_romaneio:
            sql += " AND Fila.NrRomaneio = ?"
            params.append(int(nr_romaneio))

        if cd_fat:
            sql += " AND Fila.CdFat = ?"
            params.append(int(cd_fat))

        if status_pos:
            if status_pos.upper() == "NAO_ENVIADO":
                sql += " AND Pos.IDPosProcesso IS NULL"
            else:
                sql += " AND Pos.Status = ?"
                params.append(status_pos.upper())

        sql += """
            GROUP BY
                Fila.CdFat,
                Fila.NrRomaneio,
                Pos.IDPosProcesso,
                Pos.Status,
                Pos.CodigoVeiculo,
                Pos.DescricaoVeiculo,
                Pos.Motorista,
                Pos.CdLocVei,
                Pos.CdTdr,
                Pos.CdFtr,
                Pos.CdFve,
                Pos.CdFro,
                Pos.PesoTotal,
                Pos.VolumeTotal,
                Pos.MsgErro,
                Pos.Tentativas,
                Pos.DtInclusao,
                Pos.DtInicioProc,
                Pos.DtFimProc
            ORDER BY
                MAX(Fila.DtFimProc) DESC,
                Fila.NrRomaneio DESC,
                Fila.CdFat DESC
        """

        cursor.execute(sql, params)

        columns = [col[0] for col in cursor.description]
        dados = []

        for row in cursor.fetchall():
            item = dict(zip(columns, row))

            for campo in [
                "PrimeiroEnvio",
                "UltimoProcessamento",
                "DtInclusaoPos",
                "DtInicioProcPos",
                "DtFimProcPos"
            ]:
                if item.get(campo):
                    item[campo] = item[campo].isoformat()

            dados.append(item)

        return jsonify(dados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

# ==============================================================================
# ROTA 5: POST - EMISSÃO NFE
# ==============================================================================
@wms_faturamento_bp.route('/consulta/wms/faturamento/emitir-nfe', methods=['POST'])
def incluir_pos_processo_nfe():
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "JSON inválido"}), 400

        cd_fat = data.get("cd_fat")
        nr_romaneio = data.get("nr_romaneio")
        codigo_veiculo = data.get("codigo_veiculo")
        descricao_veiculo = data.get("descricao_veiculo")
        motorista = data.get("motorista")
        cd_loc_vei = data.get("cd_loc_vei", 3)

        if not cd_fat:
            return jsonify({"error": "Campo obrigatório: cd_fat"}), 400

        if not codigo_veiculo:
            return jsonify({"error": "Campo obrigatório: codigo_veiculo"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql = """
            SET NOCOUNT ON;

            IF EXISTS (
                SELECT 1
                FROM Stik_WMS_Faturamento_PosProcesso
                WHERE CdFat = ?
            )
            BEGIN
                UPDATE Stik_WMS_Faturamento_PosProcesso
                   SET NrRomaneio = ?,
                       CodigoVeiculo = ?,
                       DescricaoVeiculo = ?,
                       Motorista = ?,
                       CdLocVei = ?,
                       Status = CASE
                                    WHEN Status IN ('CONCLUIDO', 'PROCESSANDO') THEN Status
                                    ELSE 'PENDENTE'
                                END,
                       MsgErro = CASE
                                    WHEN Status IN ('CONCLUIDO', 'PROCESSANDO') THEN MsgErro
                                    ELSE NULL
                                 END
                 WHERE CdFat = ?;

                SELECT IDPosProcesso, Status
                FROM Stik_WMS_Faturamento_PosProcesso
                WHERE CdFat = ?;
            END
            ELSE
            BEGIN
                INSERT INTO Stik_WMS_Faturamento_PosProcesso (
                    CdFat,
                    NrRomaneio,
                    CodigoVeiculo,
                    DescricaoVeiculo,
                    Motorista,
                    CdLocVei,
                    Status,
                    Tentativas,
                    DtInclusao
                ) VALUES (
                    ?, ?, ?, ?, ?, ?, 'PENDENTE', 0, GETDATE()
                );

                SELECT IDPosProcesso, Status
                FROM Stik_WMS_Faturamento_PosProcesso
                WHERE IDPosProcesso = SCOPE_IDENTITY();
            END
        """

        params = (
            cd_fat,
            nr_romaneio,
            codigo_veiculo,
            descricao_veiculo,
            motorista,
            cd_loc_vei,
            cd_fat,
            cd_fat,
            cd_fat,
            nr_romaneio,
            codigo_veiculo,
            descricao_veiculo,
            motorista,
            cd_loc_vei
        )

        cursor.execute(sql, params)
        row = cursor.fetchone()
        connection.commit()

        if not row:
            return jsonify({"error": "Falha ao gravar pós-processo da NFe"}), 500

        return jsonify({
            "message": "Enviado para emissão/pós-processo com sucesso",
            "id_pos_processo": int(row[0]),
            "cd_fat": cd_fat,
            "status": row[1]
        }), 201

    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()