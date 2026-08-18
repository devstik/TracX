from flask import Blueprint, request, jsonify
from database.server import create_connection_tinturaria
from datetime import datetime

wms_autorizados_bp = Blueprint('wms_autorizados', __name__)

# ==============================================================================
# ROTA 1: GET - CONSULTA ROMANEIOS AUTORIZADOS WMS
# ==============================================================================
@wms_autorizados_bp.route('/consulta/wms/autorizado', methods=['GET'])
def consultar_autorizados():
    connection = None
    try:
        nr_romaneio = request.args.get("nr_romaneio")

        if not nr_romaneio:
            return jsonify({"error": "Parâmetro obrigatório ausente: nr_romaneio"}), 400

        try:
            nr_romaneio = int(nr_romaneio)
        except ValueError:
            return jsonify({"error": "nr_romaneio deve ser um número inteiro"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql = """
            Select
                NrRomaneio  = Fat.NrRomaneio
            ,   Pedido      = Vpd.CdVpd
            ,   NrNfe       = Ffm.NrFfm
            ,   NrDC        = RcdDc.NrRcd
            ,   Cliente     = Cli.NmCli
            ,   DtPedido    = Vpd.DtVpd
            ,   QtAtendido  = Sum(IsNull(Fat.QtFatAtend, 0))
            ,   VrAtendido  = Sum(IsNull(Fat.QtFatAtend, Fat.QtFat) * Vpo.VrVpoUnt) + IsNull(Ttv.VrRct, 0)
            ,   VrIcms      = Sum(IsNull(Fat.QtFatAtend, Fat.QtFat) * Vpo.VrVpoUnt) * 0.0333
            ,   Situacao    = Case
                                When Fat.TpSitPag = 1 Then 'Pago'
                                When Fat.TpSitPag = 2 Then 'Pendente'
                                When Fat.TpSitPag = 3 Then 'Faturar'
                              Else '' End
            ,   Entrega     = Case
                                When Fat.TpSitFat = 2  Then 'Ag.Separação'
                                When Fat.TpSitFat = 3  Then 'Separando'
                                When Fat.TpSitFat = 4  Then 'Separado/Conferido'
                                When Fat.TpSitFat = 5  Then 'Ag.Faturamento'
                                When Fat.TpSitFat = 6  Then 'Ag.Carregamento'
                                When Fat.TpSitFat = 7  Then 'Ag.Carregado'
                                When Fat.TpSitFat = 8  Then 'Entregue'
                                When Fat.TpSitFat = 11 Then 'Cancelado'
                              Else '' End
            ,   Entregou    = Case
                                When (
                                    Select Top 1 1
                                    From Stik_NfeDaEntrega Nfe1
                                    Where Nfe1.CdRcd = Rco.CdRcd
                                ) = 1 Then 'SIM'
                              Else 'NÃO' End
            From Stik_Pedido_QtdFat Fat
            left join TbVpo Vpo                 on Vpo.CdVpo = Fat.CdVpo
            left join TbRco Rco                 on Rco.CdVpo = Vpo.CdVpo
            left join TbVpd Vpd                 on Vpd.CdVpd = Vpo.CdVpd
            left join TbCli Cli                 on Cli.CdCli = Vpd.CdCli
            left join Stik_NfeDoRomaneio FatNfe on Fat.NrRomaneio = FatNfe.NrRomaneio
            -- Número da NFe
            left join tbFtr Ftr                 on Ftr.CdFat = FatNfe.CdFat
            left join TbFad Fad                 on Fad.CdFtr = Ftr.CdFtr and Fad.CdTdo = 99
            left join TbRcd Rcd                 on Rcd.CdFad = Fad.CdFad
            left join TbFfm Ffm                 on Ffm.CdFfm = Rcd.FolhaDeFormularioID_Nfe
            -- Número do Pedido DC
            left join tbFtr FtrDC               on FtrDC.CdFat = FatNfe.CdFat
            left join TbFad FadDC               on FadDC.CdFtr = FtrDC.CdFtr and FadDC.CdTdo = 98
            left join TbRcd RcdDc               on RcdDc.CdFad = FadDC.CdFad
            -- Título de venda
            left join (
                Select
                    Rcd.CdRcd
                ,   Rcd.CdCli
                ,   Rcd.NrRcd
                ,   Rct.VrRct
                From TbRct Rct
                JOIN TbRcd Rcd on Rcd.CdRcd = Rct.CdRcd
                JOIN TbCli Cli on Cli.CdCli = Rcd.CdCli
                Where Cli.CdCli = 0 or 0 = 0
            ) Ttv on Ttv.CdRcd = Rcd.CdRcd
            Where
                Fat.NrRomaneio = ?
            and Fat.TpSitFat in (2, 3, 4, 5, 6, 7)
            Group by
                Fat.NrRomaneio
            ,   Vpd.CdVpd
            ,   Ffm.NrFfm
            ,   RcdDc.NrRcd
            ,   Cli.NmCli
            ,   Vpd.DtVpd
            ,   Fat.TpSitPag
            ,   Rco.CdRcd
            ,   Ttv.VrRct
            ,   Fat.TpSitFat
        """

        cursor.execute(sql, (nr_romaneio,))
        columns = [col[0] for col in cursor.description]
        rows = cursor.fetchall()

        if not rows:
            return jsonify([]), 200

        resultado = []
        for row in rows:
            item = {}
            for i, col in enumerate(columns):
                valor = row[i]
                if isinstance(valor, datetime):
                    valor = valor.strftime("%Y-%m-%d %H:%M:%S")
                item[col] = valor
            resultado.append(item)

        return jsonify(resultado), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()