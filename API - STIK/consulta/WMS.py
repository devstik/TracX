from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 
import datetime  

wms_bp = Blueprint('wms', __name__)

# ===================================================================
# ROTA DE CONSULTA DE ROMANEIO (WMS)
# ===================================================================
# ✨ MUDANÇA AQUI: A rota agora é /consulta/romaneio
@wms_bp.route('/consulta/romaneio', methods=['GET'])
def get_romaneio(): # ✨
    """
    Endpoint para consultar dados detalhados de romaneio/expedição
    com base em um período.

    Parâmetros da Query (URL):
    ?data_inicio=YYYY-MM-DD
    ?data_fim=YYYY-MM-DD
    
    Se não for fornecido, usa o ano corrente como padrão.
    """
    connection = None
    try:
        today = datetime.date.today()
        default_inicio = today.replace(month=1, day=1).strftime('%Y-%m-%d')
        default_fim = today.replace(month=12, day=31).strftime('%Y-%m-%d')

        data_inicio = request.args.get('data_inicio', default_inicio)
        data_fim = request.args.get('data_fim', default_fim)

        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        # Consulta T-SQL inteira com todas as correções (dbo. e @CdUsr = 0)
        sql_query = """
            SET NOCOUNT ON; -- Para evitar o erro 'No results' do pyodbc

            -- Declaração de parâmetros que virão do Python
            DECLARE @DtIni date = ?;
            DECLARE @DtFim date = ?;

            /* ==========================================
               Contexto / Usuário atual
            ========================================== */
            DECLARE @CdUsr int;
            SET @CdUsr = 0; -- Define o usuário como 0 (pois UserKey falhou na API)

            /* ==========================================
               Estoque (para saldo / reserva por unidade)
            ========================================== */
            IF OBJECT_ID('tempdb..#Estoque') IS NOT NULL DROP TABLE #Estoque;

            SELECT
                CdUne       = Let.CdUne,
                Let.CdObj,
                Qt          = SUM((Let.TpLetSin - 2) * Let.QtLet)
            INTO #Estoque
            FROM dbo.TbLet AS Let WITH (NOLOCK) 
            WHERE Let.CdCcs = 65
              AND Let.DtLet <= CONVERT(date, GETDATE())
            GROUP BY Let.CdUne, Let.CdObj
            HAVING SUM((Let.TpLetSin - 2) * Let.QtLet) > 0;

            /* ==========================================
               Base de Faturamento do período/condições
            ========================================== */
            IF OBJECT_ID('tempdb..#Stik_Pedido_QtdFat_Base') IS NOT NULL DROP TABLE #Stik_Pedido_QtdFat_Base;

            SELECT *
            INTO #Stik_Pedido_QtdFat_Base
            FROM dbo.Stik_Pedido_QtdFat AS Fat WITH (NOLOCK) 
            WHERE (Fat.TpSitFat = 0 OR 0 = 0)
              AND (CONVERT(date, Fat.DtExp) >= @DtIni) 
              AND (CONVERT(date, Fat.DtExp) <= @DtFim) 
              AND (Fat.CdUsrSep = 0 OR 0 = 0)
              AND (
                   (Fat.CdUsrSep IS NULL
                     OR (Fat.CdUsrSep = @CdUsr AND Fat.TpSitFat IN (2,3,4,5,6)))
                   OR @CdUsr IN (58,97,258,313,323,322,343,325,350,375,376,329,328,334,400,421,461,226,325,327,207)
                 )
              AND (CONVERT(int, Fat.NrRomaneio) = 0 OR 0 = 0);

            /* ==========================================
               Auxiliares (reservas, docs, totais, separador)
            ========================================== */

            /* Reservas por item do pedido */
            IF OBJECT_ID('tempdb..#PedRes') IS NOT NULL DROP TABLE #PedRes;
            SELECT
                Res.CdVpo,
                Res.CdObj,
                Qt = SUM(ISNULL(Res.QtReserva, Met.QtMet)) - ISNULL(EntRet.Qt, 0)
            INTO #PedRes
            FROM dbo.Stik_Pedido_Reserva AS Res WITH (NOLOCK) 
            JOIN dbo.TbMet AS Met WITH (NOLOCK) ON Met.CdMet = Res.CdMet 
            LEFT JOIN (
                SELECT
                    Res.CdVpo,
                    Res.CdObj,
                    Qt = SUM(ISNULL(Res.QtReserva, Met.QtMet))
                FROM dbo.Stik_Pedido_Reserva AS Res WITH (NOLOCK) 
                LEFT JOIN dbo.TbMet AS Met WITH (NOLOCK) ON Met.CdMet = Res.CdMet 
                WHERE Res.TpResSin = 3
                GROUP BY Res.CdVpo, Res.CdObj
            ) AS EntRet
               ON EntRet.CdObj = Res.CdObj
              AND EntRet.CdVpo = Res.CdVpo
            WHERE Res.TpResSin = 1
            GROUP BY Res.CdVpo, Res.CdObj, EntRet.Qt;

            /* Quantidade expedida via RCO (documentos) */
            IF OBJECT_ID('tempdb..#FatDoc') IS NOT NULL DROP TABLE #FatDoc;
            SELECT
                Rco.CdVpo,
                Qt = SUM(ISNULL(Rco.QtRcoExp, 0))
            INTO #FatDoc
            FROM dbo.TbRco AS Rco WITH (NOLOCK) 
            JOIN dbo.TbVpo AS Vpo WITH (NOLOCK) ON Vpo.CdVpo = Rco.CdVpo 
            WHERE Rco.TpRcoSta <> 3
              AND Rco.CdFin = 28
            GROUP BY Rco.CdVpo;

            /* Total por pedido × romaneio (se precisar em relatórios) */
            IF OBJECT_ID('tempdb..#QtTotal') IS NOT NULL DROP TABLE #QtTotal;
            SELECT
                Vpd.CdVpd,
                Fat.NrRomaneio,
                Vr = SUM(ISNULL(Fat.QtFatAtend, Fat.QtFat))
            INTO #QtTotal
            FROM #Stik_Pedido_QtdFat_Base AS Fat
            JOIN dbo.TbVpo AS Vpo WITH (NOLOCK) ON Vpo.CdVpo = Fat.CdVpo 
            JOIN dbo.TbVpd AS Vpd WITH (NOLOCK) ON Vpd.CdVpd = Vpo.CdVpd 
            GROUP BY Vpd.CdVpd, Fat.NrRomaneio;

            /* Separador do pedido */
            IF OBJECT_ID('tempdb..#UsrSep') IS NOT NULL DROP TABLE #UsrSep;
            SELECT DISTINCT
                Fat.CdUsrSep,
                Usr.NmUsr,
                Vpd.CdVpd
            INTO #UsrSep
            FROM dbo.Stik_Pedido_QtdFat AS Fat WITH (NOLOCK) 
            JOIN dbo.TbVpo AS Vpo WITH (NOLOCK) ON Vpo.CdVpo = Fat.CdVpo 
            JOIN dbo.TbVpd AS Vpd WITH (NOLOCK) ON Vpd.CdVpd = Vpo.CdVpd 
            JOIN dbo.Stik_Romaneio AS Sr WITH (NOLOCK) ON Sr.NrRomaneio = Fat.NrRomaneio 
            LEFT JOIN dbo.TbUsr AS Usr WITH (NOLOCK) ON Usr.CdUsr = Fat.CdUsrSep; 

            /* ==========================================
               SELECT ÚNICO
            ========================================== */
            SELECT
                NrRomaneio         = Fat.NrRomaneio,
                CdVpo              = Vpo.CdVpo,
                CdVpd              = Vpd.CdVpd,
                Data               = CONVERT(varchar, Fat.DtExp, 103),
                HrMovimento        =
                   SUBSTRING(CONVERT(varchar, CONVERT(date, Fat.DtIniExpSep), 103), 1, 2) + '/' +
                   SUBSTRING(CONVERT(varchar, CONVERT(date, Fat.DtIniExpSep), 103), 4, 2) + '/' +
                   SUBSTRING(CONVERT(varchar, CONVERT(date, Fat.DtIniExpSep), 103), 7, 4) + ' ' +
                   SUBSTRING(CONVERT(varchar, CONVERT(time, Fat.DtIniExpSep), 108), 1, 5),
                Descricao          = 'Romaneio :' + CONVERT(varchar, Fat.NrRomaneio) + ' Ped.:' + CONVERT(varchar, Vpd.CdVpd),
                Objeto             = Obj.NmObj,
                Detalhe            = LotAtv.NmLot,
                QtPed              = Vpo.QtVpo,
                Qt                 = Fat.QtFat,
                QtReservado        = ISNULL(PedRes.Qt, 0) + ISNULL(Vpo.QtVpoFatCan, 0) - ISNULL(FatDoc.Qt, 0),
                Atendido           = Fat.QtFatAtend,
                QtRes              = LetReserva.Qt, 
                SaldoDoArtigo      = Vpo.QtVpo + ISNULL(Vpo.QtVpoFatCan, 0) - ISNULL(Vpo.QtVpoFat, 0),
                Nfe                = Ffm.NrFfm,
                NrDC               = RcdDc.NrRcd,
                CdFat              = FatNfe.CdFat,
                CdRcd              = Rcd.CdRcd,
                Situacao           = ColFat.Descricao,
                SitFinan           = ColFin.Descricao,
                Observacao         = Obs.TtObs,
                ObservacaoID       = ISNULL(Obs.CdObs, 0),
                Motivo             = CASE
                                         WHEN Fat.TpMotivoCan = 1 THEN 'Artigo sem estoque'
                                         WHEN Fat.TpMotivoCan = 2 THEN 'Artigo não encontrado'
                                         WHEN Fat.TpMotivoCan = 3 THEN 'Solicitação do Comercial'
                                         ELSE ''
                                     END,
                Solicitante        = S.Solicitante,
                Separador          = UsrSep.NmUsr,
                IDSeparador        = UsrSep.CdUsrSep,
                UsrLogado          = (SELECT @CdUsr) 

            FROM #Stik_Pedido_QtdFat_Base AS Fat
            JOIN dbo.TbVpo  AS Vpo  WITH (NOLOCK) ON Vpo.CdVpo  = Fat.CdVpo 
            JOIN dbo.TbVpd  AS Vpd  WITH (NOLOCK) ON Vpd.CdVpd  = Vpo.CdVpd 
            LEFT JOIN dbo.TbCli  AS Cli  WITH (NOLOCK) ON Cli.CdCli = Vpd.CdCli 
            LEFT JOIN dbo.TbObj  AS Obj  WITH (NOLOCK) ON Obj.CdObj = Fat.CdObj 
            LEFT JOIN dbo.TbLot  AS LotAtv WITH (NOLOCK) ON LotAtv.CdLot = Vpo.CdLot 
            LEFT JOIN dbo.TbObj  AS ObjAtv WITH (NOLOCK) ON ObjAtv.CdObj = LotAtv.CdObj 

            /* NF-e (romaneio → fatura) */
            LEFT JOIN dbo.Stik_NfeDoRomaneio AS FatNfe WITH (NOLOCK) 
                   ON Fat.NrRomaneio = FatNfe.NrRomaneio
            LEFT JOIN dbo.TbFtr AS Ftr WITH (NOLOCK) 
                   ON Ftr.CdFat = FatNfe.CdFat
            LEFT JOIN dbo.TbFad AS Fad WITH (NOLOCK) 
                   ON Fad.CdFtr = Ftr.CdFtr
                  AND Fad.CdTdo IN (99, 206)
            LEFT JOIN dbo.TbRcd AS Rcd WITH (NOLOCK) 
                   ON Rcd.CdFad = Fad.CdFad
            LEFT JOIN dbo.TbFfm AS Ffm WITH (NOLOCK) 
                   ON Ffm.CdFfm = Rcd.FolhaDeFormularioID_Nfe

            /* DC (pedido de crédito / débito) */
            LEFT JOIN dbo.TbFtr AS FtrDC WITH (NOLOCK) 
                   ON FtrDC.CdFat = FatNfe.CdFat
            LEFT JOIN dbo.TbFad AS FadDC WITH (NOLOCK) 
                   ON FadDC.CdFtr = FtrDC.CdFtr
                  AND FadDC.CdTdo = 98
            LEFT JOIN dbo.TbRcd AS RcdDc WITH (NOLOCK) 
                   ON RcdDc.CdFad = FadDC.CdFad

            /* Domínios de status */
            LEFT JOIN dbo.Stik_columndomain AS ColFat WITH (NOLOCK) 
                   ON ColFat.colunaid = Fat.TpSitFat
                  AND ColFat.nomedatabela = 'Stik_Pedido_QtdFat'
                  AND ColFat.nomedacoluna = 'TpSitFat'
            LEFT JOIN dbo.Stik_columndomain AS ColFin WITH (NOLOCK) 
                   ON ColFin.colunaid = Fat.TpSitPag
                  AND ColFin.nomedatabela = 'Stik_Pedido_QtdFat'
                  AND ColFin.nomedacoluna = 'TpSitPag'

            /* Separador e observações */
            LEFT JOIN #UsrSep AS UsrSep
                   ON UsrSep.CdVpd = Vpd.CdVpd 
                  AND UsrSep.CdUsrSep = Fat.CdUsrSep
            LEFT JOIN dbo.TbObs AS Obs WITH (NOLOCK) 
                   ON Obs.CdObs = Vpd.CdObs
            LEFT JOIN dbo.Stik_AvaliacaoSeparacao AS A WITH (NOLOCK) 
                   ON A.NrRomaneio = Fat.NrRomaneio
                  AND A.CdVpd = Vpd.CdVpd
                  AND A.Separador = UsrSep.NmUsr

            /* Saldos / reservas / docs */
            LEFT JOIN #Estoque AS LetReserva
                   ON LetReserva.CdObj = Vpo.CdObj
                  AND LetReserva.CdUne = Vpd.CdUne
            LEFT JOIN #PedRes  AS PedRes
                   ON PedRes.CdVpo = Vpo.CdVpo
                  AND PedRes.CdObj = Vpo.CdObj
            LEFT JOIN #FatDoc  AS FatDoc
                   ON FatDoc.CdVpo = Vpo.CdVpo

            /* Solicitante de cancelamento */
            LEFT JOIN dbo.Stik_Solicitante_Canc AS S WITH (NOLOCK) 
                   ON S.CdVpo = Vpo.CdVpo

            /* Filtro de cliente/objeto/nota (mantidos como no seu script, efetivamente liberados) */
            WHERE (Vpd.CdVpd = 0 OR 0 = 0)
              AND (Vpd.CdCli = 0 OR 0 = 0)
              AND (0 = 0 OR EXISTS (
                   SELECT 1
                   FROM dbo.TbArvObj AS ArvObj WITH (NOLOCK) 
                   WHERE ArvObj.CdObjFil = Vpo.CdObj
                     AND ArvObj.CdObj    = 0
                 ))
              AND (CONVERT(int, ISNULL(Rcd.FolhaDeFormularioID_Nfe, 0)) = 0 OR 0 = 0)

            /* Ordenação para API */
            ORDER BY
                Fat.NrRomaneio,
                Vpd.CdVpd,
                Vpo.CdVpo;
        """
        
        # Executa a consulta T-SQL passando as datas como parâmetros
        cursor.execute(sql_query, (data_inicio, data_fim))

        # Converte o resultado em uma lista de dicionários
        registros = [dict(zip([column[0] for column in cursor.description], row)) for row in cursor.fetchall()]
        
        print(f"✅ Consulta de faturamento executada. Datas: {data_inicio} a {data_fim}. {len(registros)} linhas retornadas.")
        return jsonify(registros)

    except Exception as e:
        print(f"❌ Erro ao consultar faturamento detalhado: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔌 Conexão com o banco de dados fechada.")