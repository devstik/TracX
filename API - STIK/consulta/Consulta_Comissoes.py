from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 
from datetime import datetime

# Define o Blueprint
comissoes_bp = Blueprint('comissoes', __name__)

# ==============================================================================
# 1. QUERY SQL COMPLETA 
# ==============================================================================
RAW_SQL_COMISSOES = """
    SET NOCOUNT ON;

    IF OBJECT_ID('tempdb..#Mch') IS NOT NULL DROP TABLE #Mch;
    IF OBJECT_ID('tempdb..#TitulosDeCheque') IS NOT NULL DROP TABLE #TitulosDeCheque;
    IF OBJECT_ID('tempdb..#Titulos') IS NOT NULL DROP TABLE #Titulos;
    IF OBJECT_ID('tempdb..#Devolucoes') IS NOT NULL DROP TABLE #Devolucoes;
    IF OBJECT_ID('tempdb..#Tmp') IS NOT NULL DROP TABLE #Tmp;

    /* ========================= CHEQUES  ========================= */
    SELECT Mch1.CdChq, Mch1.CdMch, Mch1.DtMch
      INTO #Mch
      FROM TbMch Mch1
      JOIN TbTop Top2 on Top2.CdTop = Mch1.CdTop and Top2.TpTopCtg = 5110
     WHERE Mch1.DtMch between ? and ?;

    SELECT Tch.CdRct
         , DtMch = Max(Mch.DtMch)
         , Valor = Sum(Tch.VrTch)
      INTO #TitulosDeCheque
      FROM TbTch Tch
      JOIN TbMch Mch on Mch.CdMch = (SELECT Top 1 Mch1.CdMch
                                     FROM #Mch Mch1
                                    WHERE Mch1.CdChq = Tch.CdChq
                                    ORDER BY Mch1.DtMch)
    GROUP BY Tch.CdRct;

    /* ========================= TITULOS (parte 1) ========================= */
    SELECT Rcm.CdRcm, Rcm.CdEmd, Rct.CdRct, Rcd.CdUne, Rcd.CdLotVen, Rcd.CdRcd,
           Rcd.DtRcdEmi, Rct.DtRctVen,
           DataRecebimento = Case When Mpg.TpMpg = 3 Then Tch.DtMch Else Rcm.DtRcmMov End,
           Tch.DtMch, Tch.Valor, Rcd.CdCli, Rcd.CdFpg, Rcd.VrRcd, Rcd.NrRcd, Rct.NrRctOrd,
           Rcm.DtRcmMov, Mpg.TpMpg, Mpg.NmMpg, Rco.VrRco, Rco.CdFvo, Rco.CdObj, Rco.CdRco
      INTO #Titulos
      FROM TbRcm Rcm
      JOIN TbRct Rct on Rct.CdRct = Rcm.CdRct
      JOIN TbRco Rco on Rco.CdRcd = Rct.CdRcd
      JOIN TbRcd Rcd on Rcd.CdRcd = Rct.CdRcd
      JOIN TbUne Une on Une.CdUne = Rcd.CdUne
      JOIN TbEmd Emd on Emd.CdEmd = Rcm.CdEmd
      JOIN TbMde Mde on Mde.CdMde = Emd.CdMde
      JOIN TbMpg Mpg on Mpg.CdMpg = Mde.CdMpg
      LEFT JOIN #TitulosDeCheque Tch on Tch.CdRct = Rct.CdRct
     WHERE Rcm.CdEmd is not null
       AND Case When Mpg.TpMpg = 3 Then Tch.DtMch Else Rcm.DtRcmMov End between ? and ?
       AND (0 = 0 or Rcd.CdlotVen = 0)
       AND (0 = 0 or Rcd.CdRcd = 0)
       AND (0 = 0 or Exists (Select 1 From TbArvCli Where CdCliFil = Rcd.CdCli and CdCli = 0));

    /* ========================= TITULOS (parte 2 - com RcdRel) ========================= */
    INSERT INTO #Titulos
    SELECT Rcm.CdRcm, Rcm.CdEmd, Rct.CdRct, Rcd.CdUne, RcdRel.CdLotVen, Rcd.CdRcd,
           Rcd.DtRcdEmi, Rct.DtRctVen,
           DataRecebimento = Case When Mpg.TpMpg = 3 Then Tch.DtMch Else Rcm.DtRcmMov End,
           Tch.DtMch, Tch.Valor, Rcd.CdCli, Rcd.CdFpg, Rcd.VrRcd, Rcd.NrRcd, Rct.NrRctOrd,
           Rcm.DtRcmMov, Mpg.TpMpg, Mpg.NmMpg, Rco.VrRco, Rco.CdFvo, Rco.CdObj, Rco.CdRco
      FROM TbRcm Rcm
      JOIN TbRct Rct on Rct.CdRct = Rcm.CdRct
      JOIN TbRcr Rcr on Rcr.CdRcd = Rct.CdRcd
      JOIN TbRcd RcdRel on RcdRel.CdRcd = Rcr.CdRcdRel
      JOIN TbRco Rco on Rco.CdRcd = Rcr.CdRcdRel
      JOIN TbRcd Rcd on Rcd.CdRcd = Rct.CdRcd
      JOIN TbUne Une on Une.CdUne = Rcd.CdUne
      JOIN TbEmd Emd on Emd.CdEmd = Rcm.CdEmd
      JOIN TbMde Mde on Mde.CdMde = Emd.CdMde
      JOIN TbMpg Mpg on Mpg.CdMpg = Mde.CdMpg
      LEFT JOIN #TitulosDeCheque Tch on Tch.CdRct = Rct.CdRct
     WHERE Rcm.CdEmd is not null
       AND Case When Mpg.TpMpg = 3 Then Tch.DtMch Else Rcm.DtRcmMov End between ? and ?
       AND (0 = 0 or RcdRel.CdlotVen = 0)
       AND (0 = 0 or Rcd.CdRcd = 0)
       AND (0 = 0 or Exists (Select 1 From TbArvCli Where CdCliFil = Rcd.CdCli and CdCli = 0));

    /* ========================= DEVOLUÇÕES ========================= */
    SELECT Rcd.CdRcd, Obj.CdObjMae, Obj.CdObjLin, CdLotVen = RcdRef.CdLotven,
           Rcd.CdCli, Rcd.DtRcdEmi,
           Valor = -Sum(Tuc.VrTuc * Rco.VrRco / Rcd.VrRcd)
      INTO #Devolucoes
      FROM TbTuc Tuc
      JOIN TbRcd Rcd on Rcd.CdRcd = Tuc.CdRcd
      JOIN TbTop Top1 on Top1.CdTop = Rcd.CdTop and Top1.TpTopCtg = 3205
      JOIN TbRco Rco on Rco.CdRcd = Rcd.CdRcd
      JOIN TbRco RcoRef on RcoRef.CdRco = Rco.CdRcoRef
      JOIN TbRcd RcdRef on RcdRef.CdRcd = RcoRef.CdRcd
      JOIN TbObj Obj on obj.CdObj = Rco.CdObj
     WHERE (0 = 0 or RcdRef.CdLotven = 0)
       AND (0 = 0 or Rcd.CdRcd = 0)
       AND (0 = 0 or Exists (Select 1 From TbArvCli Where CdCliFil = Rcd.CdCli and CdCli = 0))
       AND Rcd.DtRcdEmi between ? and ?
    GROUP BY Rcd.CdRcd, Obj.CdObjMae, Obj.CdObjLin, RcdRef.CdLotven, Rcd.CdCli, Rcd.DtRcdEmi;

    /* ========================= Consolidação em #Tmp ========================= */
    SELECT CdRct = 0, LotVen.CdLot, LotVen.NmLot, Doc = d.CdRcd, Titulo = '',
           Cliente = Pes.NmPes, CdObjMae = Mae.CdObj, Artigo = Mae.NmObj, Recebido = d.Valor,
           ICMSST = d.Valor, Frete = 0,
           RecebimentoLiquido = d.Valor,
           DataEmissao = d.DtRcdEmi, DataVencimento = d.DtRcdEmi, DataRecebimento = d.DtRcdEmi,
           PrazoMedio = 0, PrecoMedio = 0, MeioPagamento = 'Devolução',
           Linha = Lin.NmObj, UF = Loc.SgLoc
      Into #Tmp
      FROM #Devolucoes d
      JOIN TbLot Lotven on Lotven.CdLot = d.CdLotVen
      JOIN TbCli Cli on Cli.CdCli = d.CdCli
      JOIN TbPes Pes on Pes.CdPes = Cli.CdPes
      JOIN TbObj Mae on Mae.CdObj = d.CdObjMae
      JOIN TbObj Lin on Lin.CdObj = d.CdObjLin
      LEFT JOIN TbArvLoc ArvLoc on ArvLoc.CdLocFil = Pes.CdLoc
      JOIN TbLoc Loc on Loc.CdLoc = ArvLoc.CdLoc and Loc.TpLoc = 3

    UNION ALL

    -- Títulos (partes 1 e 2)
    SELECT Rcm.CdRct, LotVen.CdLot, LotVen.NmLot, Doc = Rcm.CdRcd,
           Titulo = Une.SgUne + '.' + Rcm.NrRcd + '/' + Convert(varchar, Rcm.NrRctOrd),
           Cliente = Pes.NmPes, CdObjMae = Mae.CdObj, Artigo = Mae.NmObj,
           Recebido = (Case When Rcm.TpMpg = 3 Then Sum(Rcm.Valor * (Rcm.VrRco / Rcm.VrRcd))
                            Else Sum(Rcn.VrRcn * (Rcm.VrRco / Rcm.VrRcd)) End),
           ICMSST = IsNull(
                   Sum(RcsICMSST.VrRcs) *
                   ((Case When Rcm.TpMpg = 3 Then Sum(Rcm.Valor * (Rcm.VrRco / Rcm.VrRcd))
                             Else Sum(Rcn.VrRcn * (Rcm.VrRco / Rcm.VrRcd)) End) / Sum(Rcm.VrRco)), 0),
           Frete = IsNull(
                   Sum(RcsFrete.VrRcs) *
                   ((Case When Rcm.TpMpg = 3 Then Sum(Rcm.Valor * (Rcm.VrRco / Rcm.VrRcd))
                             Else Sum(Rcn.VrRcn * (Rcm.VrRco / Rcm.VrRcd)) End) / Sum(Rcm.VrRco)), 0),
           RecebimentoLiquido =
               (Case When Rcm.TpMpg = 3 Then Sum(Rcm.Valor * (Rcm.VrRco / Rcm.VrRcd))
                     Else Sum(Rcn.VrRcn * (Rcm.VrRco / Rcm.VrRcd)) End)
             - IsNull(
                 Sum(RcsICMSST.VrRcs) *
                 ((Case When Rcm.TpMpg = 3 Then Sum(Rcm.Valor * (Rcm.VrRco / Rcm.VrRcd))
                        Else Sum(Rcn.VrRcn * (Rcm.VrRco / Rcm.VrRcd)) End) / Sum(Rcm.VrRco)), 0)
             - IsNull(
                 Sum(RcsFrete.VrRcs) *
                 ((Case When Rcm.TpMpg = 3 Then Sum(Rcm.Valor * (Rcm.VrRco / Rcm.VrRcd))
                        Else Sum(Rcn.VrRcn * (Rcm.VrRco / Rcm.VrRcd)) End) / Sum(Rcm.VrRco)), 0),
           DataEmissao = Rcm.DtRcdEmi, DataVencimento = Rcm.DtRctVen, DataRecebimento = Rcm.DataRecebimento,
           PrazoMedio = Fpg.QtFpgPrzMed, PrecoMedio = Sum(PM.ValorLiq) / Nullif(Sum(PM.Quantidade), 0),
           MeioPagamento = Rcm.NmMpg, Linha = Lin.NmObj, UF = Loc.SgLoc
      FROM TbRcn Rcn
      JOIN #Titulos Rcm on Rcm.CdRcm = Rcn.CdRcm
      LEFT JOIN TbFvo Fvo on Fvo.CdFvo = Rcm.CdFvo
      LEFT JOIN TbVpo Vpo on Vpo.CdVpo = Fvo.CdVpo
      JOIN TbUne Une on Une.CdUne = Rcm.CdUne
      JOIN TbLot LotVen on LotVen.CdLot = Rcm.CdLotVen
      JOIN TbObj Obj on Obj.CdObj = Rcm.CdObj
      JOIN TbObj Mae on Mae.CdObj = Obj.CdObjMae
      LEFT JOIN (
            SELECT Vpo.CdVpd, Mae.CdObj,
                   Valor = Sum(Vpo.VrVpo), ValorLiq = Sum(VrVpoMerLiq), Quantidade = Sum(Vpo.QtVpo)
              FROM TbVpo Vpo
              JOIN TbObj Obj on Obj.CdObj = Vpo.CdObj
              JOIN TbObj Mae on Mae.CdObj = Obj.CdObjMae
            GROUP BY Vpo.CdVpd, Mae.CdObj
      ) PM on PM.CdVpd = Vpo.CdVpd and PM.CdObj = Mae.CdObj
      JOIN TbOes Oes on Oes.CdOes = Rcn.CdOes and Oes.TpOesVal = 21
      JOIN TbCli Cli on Cli.CdCli = Rcm.CdCli
      JOIN TbPes Pes on Pes.CdPes = Cli.CdPes
      LEFT JOIN TbFpg Fpg on Fpg.CdFpg = Rcm.CdFpg
      LEFT JOIN TbRcs RcsICMSST on RcsICMSST.CdRco = Rcm.CdRco and RcsICMSST.CdOes = 365
      LEFT JOIN TbRcs RcsFrete on RcsFrete.CdRco = Rcm.CdRco and RcsFrete.CdOes = 57
      JOIN TbObj Lin on Lin.CdObj = Obj.CdObjLin
      LEFT JOIN TbArvLoc ArvLoc on ArvLoc.CdLocFil = Pes.CdLoc
      JOIN TbLoc Loc on Loc.CdLoc = ArvLoc.CdLoc and Loc.TpLoc = 3
      GROUP BY Rcm.CdRct, LotVen.CdLot, LotVen.NmLot, Rcm.CdRcd, Pes.NmPes, Mae.NmObj,
               Fpg.QtFpgPrzMed, Rcm.NmMpg, Rcm.DtRcdEmi, Rcm.DtRctVen,
               Rcm.TpMpg, Case When Rcm.TpMpg = 3 Then Rcm.DtMch Else Rcm.DtRcmMov End,
               Une.SgUne + '.' + Rcm.NrRcd + '/' + Convert(varchar, Rcm.NrRctOrd), Rcm.DataRecebimento,
               Lin.NmObj, Loc.SgLoc, Mae.CdObj

    UNION ALL

    -- Baixa com saldo
    SELECT Rcm.CdRct, LotVen.CdLot, LotVen.NmLot, Doc = Rcd.CdRcd,
           Titulo = Une.SgUne + '.' + Rcd.NrRcd + '/' + Convert(varchar, Rct.NrRctOrd),
           Cliente = Pes.NmPes, CdObjMae = Mae.CdObj, Artigo = Mae.NmObj,
           Recebido = Sum(Rcn.VrRcn * (Rco.VrRco / Rcd.VrRcd)),
           ICMSST = IsNull(Sum(RcsICMSST.VrRcs) * ( Sum(Rcn.VrRcn * (Rco.VrRco / Rcd.VrRcd)) / Sum(Rco.VrRco) ), 0),
           Frete   = IsNull(Sum(RcsFrete.VrRcs)  * ( Sum(Rcn.VrRcn * (Rco.VrRco / Rcd.VrRcd)) / Sum(Rco.VrRco) ), 0),
           RecebimentoLiquido =
               Sum(Rcn.VrRcn * (Rco.VrRco / Rcd.VrRcd))
             - IsNull(Sum(RcsICMSST.VrRcs) * ( Sum(Rcn.VrRcn * (Rco.VrRco / Rcd.VrRcd)) / Sum(Rco.VrRco) ), 0)
             - IsNull(Sum(RcsFrete.VrRcs)  * ( Sum(Rcn.VrRcn * (Rco.VrRco / Rcd.VrRcd)) / Sum(Rco.VrRco) ), 0),
           DataEmissao = Rcd.DtRcdEmi, DataVencimento = Rct.DtRctVen, DataRecebimento = Rcm.DtRcmMov,
           PrazoMedio = Fpg.QtFpgPrzMed, PrecoMedio = Sum(PM.ValorLiq) / Nullif(Sum(PM.Quantidade), 0),
           MeioPagamento = 'Baixa com Saldo', Linha = Lin.NmObj, UF = Loc.SgLoc
      FROM TbRcn Rcn
      JOIN TbRcm Rcm on Rcm.CdRcm = Rcn.CdRcm
      JOIN TbTuc Tuc on Tuc.CdRcm = Rcm.CdRcm
      JOIN TbRct Rct on Rct.CdRct = Rcm.CdRct
      JOIN TbRco Rco on Rco.CdRcd = Rct.CdRcd
      JOIN TbRcd Rcd on Rcd.CdRcd = Rct.CdRcd
      JOIN TbUne Une on Une.CdUne = Rcd.CdUne
      JOIN TbLot LotVen on LotVen.CdLot = Rcd.CdLotVen
      JOIN TbObj Obj on Obj.CdObj = Rco.CdObj
      JOIN TbObj Mae on Mae.CdObj = Obj.CdObjMae
      JOIN TbOes Oes on Oes.CdOes = Rcn.CdOes and Oes.TpOesVal = 21
      JOIN TbCli Cli on Cli.CdCli = Rcd.CdCli
      JOIN TbPes Pes on Pes.CdPes = Cli.CdPes
      LEFT JOIN TbFpg Fpg on Fpg.CdFpg = Rcd.CdFpg
      LEFT JOIN TbFvo Fvo on Fvo.CdFvo = Rco.CdFvo
      LEFT JOIN TbVpo Vpo on Vpo.CdVpo = Fvo.CdVpo
      LEFT JOIN (
            SELECT Vpo.CdVpd, Mae.CdObj,
                   Valor = Sum(Vpo.VrVpo), ValorLiq = Sum(VrVpoMerLiq), Quantidade = Sum(Vpo.QtVpo)
              FROM TbVpo Vpo
              JOIN TbObj Obj on Obj.CdObj = Vpo.CdObj
              JOIN TbObj Mae on Mae.CdObj = Obj.CdObjMae
            GROUP BY Vpo.CdVpd, Mae.CdObj
      ) PM on PM.CdVpd = Vpo.CdVpd and PM.CdObj = Mae.CdObj
      LEFT JOIN TbRcs RcsICMSST on RcsICMSST.CdRco = Rco.CdRco and RcsICMSST.CdOes = 365
      LEFT JOIN TbRcs RcsFrete on RcsFrete.CdRco = Rco.CdRco and RcsFrete.CdOes = 57
      JOIN TbObj Lin on Lin.CdObj = Obj.CdObjLin
      LEFT JOIN TbArvLoc ArvLoc on ArvLoc.CdLocFil = Pes.CdLoc
      JOIN TbLoc Loc on Loc.CdLoc = ArvLoc.CdLoc and Loc.TpLoc = 3
     WHERE Tuc.CdRcm is not null
       AND Rcm.DtRcmMov between ? and ?
       AND (0 = 0 or Rcd.CdlotVen = 0)
       AND (0 = 0 or Rcd.CdRcd = 0)
       AND (0 = 0 or Exists (Select 1 From TbArvCli Where CdCliFil = Rcd.CdCli and CdCli = 0))
     GROUP BY Rcm.CdRct, LotVen.CdLot, LotVen.NmLot, Rcd.CdRcd,
              Une.SgUne + '.' + Rcd.NrRcd + '/' + Convert(varchar, Rct.NrRctOrd),
              Pes.NmPes, Mae.NmObj, Rcd.DtRcdEmi, Rct.DtRctVen, Rcm.DtRcmMov,
              Fpg.QtFpgPrzMed, Lin.NmObj, Loc.SgLoc, Mae.CdObj

    -- ===== FILTRO FINAL (usa uma OU outra data) =====
    SELECT
          ID             = R.Doc,
          VendedorID     = R.CdLot,
          Vendedor       = R.NmLot,
          Titulo         = R.Titulo,
          Cliente        = R.Cliente,
          UF             = R.UF,
          CdObjMae       = R.CdObjMae,
          Artigo         = R.Artigo,
          Linha          = R.Linha,
          Recebido       = ISNULL(R.Recebido, 0),
          ICMSST         = ISNULL(R.ICMSST, 0),
          Frete          = ISNULL(R.Frete, 0),
          Rec_Liquido    = ISNULL(R.RecebimentoLiquido, 0),
          Prazo_Medio    = ISNULL(R.PrazoMedio, 0),
          Preco_Medio    = ISNULL(R.PrecoMedio, 0),
          Preco_Venda    = COALESCE(X.VrVenda, R.PrecoMedio, 0),
          M_Pagamento    = R.MeioPagamento,
          Emissao        = R.DataEmissao,
          Vencimento     = R.DataVencimento,
          Recebimento    = R.DataRecebimento,
          Percentual_Comissao = CASE
                                    WHEN X.VrVenda > 0 AND Comissao.Percentual IS NOT NULL THEN Comissao.Percentual
                                    WHEN X.VrVenda > 0 THEN 0.01
                                    ELSE 0.01
                                 END
    FROM #Tmp R
    OUTER APPLY (
        SELECT VrVenda = CAST(
                        SUM(CAST(Rco.VrRcoBru AS DECIMAL(38,10))) /
                        NULLIF(SUM(CAST(Rco.QtRco   AS DECIMAL(38,10))), 0)
                      AS DECIMAL(19,4))
        FROM TbRco Rco
        JOIN TbObj Obj ON Obj.CdObj = Rco.CdObj
        JOIN TbObj Mae ON Mae.CdObj = Obj.CdObjMae
        WHERE Rco.CdRcd = R.Doc
          AND Mae.NmObj = R.Artigo
    ) X
    OUTER APPLY (
        SELECT TOP 1 C.Percentual
        FROM STIK_COMERCIAL_TabelaRateada C
        WHERE 
            C.CdObjMae = R.CdObjMae
            AND C.Min <> 0.0000 AND C.Max <> 0.0000
            AND X.VrVenda BETWEEN C.Min AND (C.Max + 0.0001)
            AND (
                (C.IDTb = 1 AND R.UF IN ('BAHIA', 'ALAGOAS', 'SERGIPE', 'PARAIBA', 'RIO GRANDE DO NORTE', 'PIAUI', 'MARANHAO')) OR
                (C.IDTb = 2 AND R.UF IN ('Santa Catarina', 'Rio Grande do Sul')) OR
                (C.IDTb = 3 AND R.UF IN ('Rio de Janeiro', 'Goiás', 'SP', 'Minas Gerais')) OR
                (C.IDTb = 4 AND R.UF = 'PE') OR
                (C.IDTb = 5 AND R.UF = 'CE')
            )
    ) Comissao
    WHERE R.DataRecebimento BETWEEN ? AND ?
      {nm_lot_filter_sql};

    DROP TABLE #Mch; DROP TABLE #Titulos; DROP TABLE #TitulosDeCheque; DROP TABLE #Devolucoes; DROP TABLE #Tmp;
"""

# ==============================================================================
# 2. ROTA GET: CALCULADORA 
# ==============================================================================
@comissoes_bp.route('/consulta/comissoes/calcular', methods=['GET'])
def calcular_comissoes():
    connection = None
    try:
        dt_ini = request.args.get('data_inicial')
        dt_fim = request.args.get('data_final')
        vendedor = request.args.get('vendedor') 

        if not dt_ini or not dt_fim:
            return jsonify({'error': 'Datas inicial e final são obrigatórias'}), 400

        filter_clause = f"AND R.NmLot = '{vendedor}'" if vendedor else ""
        final_sql = RAW_SQL_COMISSOES.format(nm_lot_filter_sql=filter_clause)

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        params = [dt_ini, dt_fim] * 6
        cursor.execute(final_sql, params)

        colunas = [column[0] for column in cursor.description]
        resultados = [dict(zip(colunas, row)) for row in cursor.fetchall()]

        return jsonify(resultados), 200
    except Exception as e:
        return jsonify({'error': str(e)}), 500
    finally:
        if connection: connection.close()


# ==============================================================================
# 3. ROTA POST: SALVAR NO EXTRATO 
# ==============================================================================
@comissoes_bp.route('/consulta/comissoes/extrato', methods=['POST'])
def salvar_extrato():
    connection = None
    try:
        data = request.json 
        if not data:
            return jsonify({'message': 'Nenhum dado enviado'}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_insert = """
            INSERT INTO dbo.Stik_Extrato_Comissoes (
                Competencia, Doc, Cliente, Artigo, Linha, UF,
                DataRecebimento, RecebimentoLiq, PercComissao, ValorComissao,
                Observacao, CriadoPor,
                VendedorID, Vendedor, Titulo, MeioPagamento,
                Emissao, Vencimento, Recebido, ICMSST, Frete,
                PrecoMedio, PrecoVenda, PrazoMedio, Percentual_Comissao,
                Validado, ValidadoPor, ValidadoEm, Consolidado
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,'Comissys-App',
                      ?,?,?,?,?,?,?,?,?,?,?,?,?, 0, NULL, NULL, 0)
        """

        count = 0
        for item in data:
            # 1. Tratamento de Valores e Comissões
            rec_liquido = float(item.get('Rec_Liquido', 0))
            perc_comissao = float(item.get('Percentual_Comissao_Editado') or item.get('Percentual_Comissao') or 0) # PercComissao
            perc_padrao = float(item.get('Percentual_Comissao', 0)) # Percentual_Comissao
            valor_comissao = rec_liquido * perc_comissao # ValorComissao
            
            # 2. Competência baseada na Data de Recebimento
            data_rec_str = item.get('Recebimento')
            competencia = '00/0000'
            if data_rec_str:
                try:
                    dt_obj = datetime.strptime(str(data_rec_str)[:10], '%Y-%m-%d')
                    competencia = dt_obj.strftime('%m/%Y')
                except: pass

            cursor.execute(sql_insert, (
                competencia,
                item.get('ID'),
                item.get('Cliente'),
                item.get('Artigo'),
                item.get('Linha'),
                item.get('UF'),
                item.get('Recebimento'),
                rec_liquido,
                perc_comissao,    # %Comissão -> PercComissao
                valor_comissao,   # Valor Comissão -> ValorComissao
                item.get('Observacao', ''),
                item.get('VendedorID'),
                item.get('Vendedor'),
                item.get('Titulo'),
                item.get('M_Pagamento'),
                item.get('Emissao'),
                item.get('Vencimento'),
                item.get('Recebido'),
                item.get('ICMSST'),
                item.get('Frete'),
                item.get('Preco_Medio'),
                item.get('Preco_Venda'),
                item.get('Prazo_Medio'),
                perc_padrao      # %Percentual Padrão -> Percentual_Comissao
            ))
            count += 1

        connection.commit()
        return jsonify({'message': f'{count} registros salvos no Extrato!'}), 201
    except Exception as e:
        if connection: connection.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        if connection: connection.close()


# ==============================================================================
# 4. ROTA POST: CONSOLIDAR 
# ==============================================================================
@comissoes_bp.route('/consulta/comissoes/consolidar', methods=['POST'])
def consolidar_comissoes():
    connection = None
    try:
        data = request.json
        if not data:
            return jsonify({'message': 'Nenhum dado enviado'}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_consolidar = """
            INSERT INTO dbo.Stik_Consolidacao_Comissoes (
                Competencia, Doc, Cliente, Artigo, Linha, UF,
                DataRecebimento, RecebimentoLiq, PercComissao, ValorComissao,
                Observacao, CriadoPor,
                VendedorID, Vendedor, Titulo, MeioPagamento,
                Emissao, Vencimento, Recebido, ICMSST, Frete,
                PrecoMedio, PrecoVenda, PrazoMedio
            ) VALUES (?,?,?,?,?,?,?,?,?,?,?,'Comissys-App',
                      ?,?,?,?,?,?,?,?,?,?,?,?,?)
        """

        sql_update_extrato = "UPDATE [dbo].[Stik_Extrato_Comissoes] SET Consolidado = 1 WHERE Doc = ? AND Titulo = ?"

        count = 0
        for item in data:
            cursor.execute(sql_consolidar, (
                item.get('Competencia'),
                item.get('Doc'),
                item.get('Cliente'),
                item.get('Artigo'),
                item.get('Linha'),
                item.get('UF'),
                item.get('DataRecebimento'),
                item.get('RecebimentoLiq'),
                item.get('PercComissao'),
                item.get('ValorComissao'),
                item.get('Observacao', ''),
                item.get('VendedorID'),
                item.get('Vendedor'),
                item.get('Titulo'),
                item.get('MeioPagamento'),
                item.get('Emissao'),
                item.get('Vencimento'),
                item.get('Recebido'),
                item.get('ICMSST'),
                item.get('Frete'),
                item.get('PrecoMedio'),
                item.get('PrecoVenda'),
                item.get('PrazoMedio')
            ))

            cursor.execute(sql_update_extrato, (item.get('Doc'), item.get('Titulo')))
            count += 1

        connection.commit()
        return jsonify({'message': 'Comissões consolidadas com sucesso!'}), 201
    except Exception as e:
        if connection: connection.rollback()
        return jsonify({'error': str(e)}), 500
    finally:
        if connection: connection.close()