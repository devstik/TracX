# import requests
# import re
# import unicodedata
# from flask import Blueprint, jsonify, request
# from database.server import create_connection_tinturaria 
# import datetime 
# from datetime import timedelta

# wms_bp = Blueprint('wms', __name__)



# # ROTA 1: GET (Para consultar a lista de romaneios)
# @wms_bp.route('/consulta/romaneio', methods=['GET'])
# def get_romaneio(): 
#     """
#     Endpoint para consultar dados detalhados de romaneio/expedição.
#     Filtra a visibilidade: Admin vê todos, Separador vê não atribuídos 
#     ou atribuídos a ele.
#     """
#     connection = None
#     try:
#         today = datetime.date.today()
#         default_inicio = today.replace(month=1, day=1).strftime('%Y-%m-%d')
#         default_fim = today.replace(month=12, day=31).strftime('%Y-%m-%d')

#         data_inicio = request.args.get('data_inicio', default_inicio)
#         data_fim = request.args.get('data_fim', default_fim)
#         # Pega o ID do usuário logado do query parameter
#         cd_usr = request.args.get('cd_usr', '0')
#         # Garante que cd_usr é um inteiro para o T-SQL
#         try:
#             cd_usr_int = int(cd_usr)
#         except ValueError:
#             cd_usr_int = 0

#         connection = create_connection_tinturaria() 
#         cursor = connection.cursor()

#         sql_query = """
#             SET NOCOUNT ON; -- Para evitar o erro 'No results' do pyodbc

#             -- Declaração de parâmetros que virão do Python
#             DECLARE @DtIni date = ?;
#             DECLARE @DtFim date = ?;

#             /* ==========================================
#                 Contexto / Usuário atual
#             ========================================== */
#             DECLARE @CdUsr int;
#             SET @CdUsr = ?; -- Agora recebe o ID do usuário logado

            

#             /* ==========================================
#                 Base de Faturamento do período/condições
#             ========================================== */
#             IF OBJECT_ID('tempdb..#Stik_Pedido_QtdFat_Base') IS NOT NULL DROP TABLE #Stik_Pedido_QtdFat_Base;

#             SELECT Fat.*
#             INTO #Stik_Pedido_QtdFat_Base
#             FROM dbo.Stik_Pedido_QtdFat AS Fat WITH (NOLOCK) 
#             -- 💡 CORREÇÃO 2 do problema anterior: INNER JOIN OBRIGATÓRIO NA TABELA MESTRA 'Stik_Romaneio'
#             INNER JOIN dbo.Stik_Romaneio AS Sr WITH (NOLOCK) ON Sr.NrRomaneio = Fat.NrRomaneio
#             WHERE (Fat.TpSitFat = 0 OR 0 = 0)
#             --WHERE (Fat.TpSitFat = 2)
#               AND (CONVERT(date, Fat.DtExp) >= @DtIni) 
#               AND (CONVERT(date, Fat.DtExp) <= @DtFim) 
              
              
#               -- FILTRO DE VISIBILIDADE REFORÇADO (AQUI ESTÁ A CORREÇÃO LÓGICA)
#               AND (
#                     -- 1. LÓGICA DE ADMIN: Permite acesso total para admins.
#                     @CdUsr = 0
#                     OR @CdUsr IN (58, 97, 258, 313, 323, 322, 343, 325, 350, 357, 372, 183, 324, 168, 294, 375, 376, 329, 328, 334 , 400 , 421 , 461 , 226, 325 , 327 , 207 , 334)
#                     -- 2. OU LÓGICA DE SEPARADOR: Romaneio não atribuído OU atribuído a ele.
#                     OR (
#                         Fat.CdUsrSep IS NULL 
#                         OR Fat.CdUsrSep = 0
#                         OR Fat.CdUsrSep = @CdUsr
#                     )
#                 )
                
#               -- 💡 CORREÇÃO 1: Garante que só puxa itens com NrRomaneio > 0 (Romaneados)
#               --AND CONVERT(int, ISNULL(Fat.NrRomaneio, 0)) > 0;
#               AND CONVERT(int, ISNULL(Fat.NrRomaneio, 0)) > 0
#                 AND NOT EXISTS (
#                     SELECT 1
#                     FROM dbo.Stik_WMS_Romaneio_Separado Sep
#                     WHERE Sep.NrRomaneio = Fat.NrRomaneio
#                 );

#             /* ==========================================
#                 Estoque (para saldo / reserva por unidade)
#             ========================================== */
#             IF OBJECT_ID('tempdb..#Estoque') IS NOT NULL DROP TABLE #Estoque;

#             SELECT
#                 CdUne       = Let.CdUne,
#                 Let.CdObj,
#                 Qt          = SUM((Let.TpLetSin - 2) * Let.QtLet)
#             INTO #Estoque
#             FROM dbo.TbLet AS Let WITH (NOLOCK) 
#             WHERE Let.CdCcs = 65
#               AND Let.DtLet <= CONVERT(date, GETDATE())
#             GROUP BY Let.CdUne, Let.CdObj
#             HAVING SUM((Let.TpLetSin - 2) * Let.QtLet) > 0;

#             /* ==========================================
#                 Auxiliares (reservas, docs, totais, separador)
#             ========================================== */

#             /* Reservas por item do pedido */
#             IF OBJECT_ID('tempdb..#PedRes') IS NOT NULL DROP TABLE #PedRes;
#             SELECT
#                 Res.CdVpo,
#                 Res.CdObj,
#                 Qt = SUM(ISNULL(Res.QtReserva, Met.QtMet)) - ISNULL(EntRet.Qt, 0)
#             INTO #PedRes
#             FROM dbo.Stik_Pedido_Reserva AS Res WITH (NOLOCK) 
#             JOIN dbo.TbMet AS Met WITH (NOLOCK) ON Met.CdMet = Res.CdMet 
#             LEFT JOIN (
#                 SELECT
#                     Res.CdVpo,
#                     Res.CdObj,
#                     Qt = SUM(ISNULL(Res.QtReserva, Met.QtMet))
#                 FROM dbo.Stik_Pedido_Reserva AS Res WITH (NOLOCK) 
#                 LEFT JOIN dbo.TbMet AS Met WITH (NOLOCK) ON Met.CdMet = Res.CdMet 
#                 WHERE Res.TpResSin = 3
#                 GROUP BY Res.CdVpo, Res.CdObj
#             ) AS EntRet
#                 ON EntRet.CdObj = Res.CdObj
#               AND EntRet.CdVpo = Res.CdVpo
#             WHERE Res.TpResSin = 1
#             GROUP BY Res.CdVpo, Res.CdObj, EntRet.Qt;

#             /* Quantidade expedida via RCO (documentos) */
#             IF OBJECT_ID('tempdb..#FatDoc') IS NOT NULL DROP TABLE #FatDoc;
#             SELECT
#                 Rco.CdVpo,
#                 Qt = SUM(ISNULL(Rco.QtRcoExp, 0))
#             INTO #FatDoc
#             FROM dbo.TbRco AS Rco WITH (NOLOCK) 
#             JOIN dbo.TbVpo AS Vpo WITH (NOLOCK) ON Vpo.CdVpo = Rco.CdVpo 
#             WHERE Rco.TpRcoSta <> 3
#               AND Rco.CdFin = 28
#             GROUP BY Rco.CdVpo;

#             /* Total por pedido × romaneio (se precisar em relatórios) */
#             IF OBJECT_ID('tempdb..#QtTotal') IS NOT NULL DROP TABLE #QtTotal;
#             SELECT
#                 Vpd.CdVpd,
#                 Fat.NrRomaneio,
#                 Vr = SUM(ISNULL(Fat.QtFatAtend, Fat.QtFat))
#             INTO #QtTotal
#             FROM #Stik_Pedido_QtdFat_Base AS Fat
#             JOIN dbo.TbVpo AS Vpo WITH (NOLOCK) ON Vpo.CdVpo = Fat.CdVpo 
#             JOIN dbo.TbVpd AS Vpd WITH (NOLOCK) ON Vpd.CdVpd = Vpo.CdVpd 
#             GROUP BY Vpd.CdVpd, Fat.NrRomaneio;

#             /* Separador do pedido */
#             IF OBJECT_ID('tempdb..#UsrSep') IS NOT NULL DROP TABLE #UsrSep;
#             SELECT DISTINCT
#                 Fat.CdUsrSep,
#                 Usr.NmUsr,
#                 Vpd.CdVpd
#             INTO #UsrSep
#             -- ✅ CORREÇÃO 3: Usar a base de faturamento já filtrada para pegar só separadores de romaneios válidos e visíveis
#             FROM #Stik_Pedido_QtdFat_Base AS Fat 
#             JOIN dbo.TbVpo AS Vpo WITH (NOLOCK) ON Vpo.CdVpo = Fat.CdVpo 
#             JOIN dbo.TbVpd AS Vpd WITH (NOLOCK) ON Vpd.CdVpd = Vpo.CdVpd 
#             -- Não precisa mais do JOIN com Stik_Romaneio aqui, pois já foi feito na criação da #Stik_Pedido_QtdFat_Base
#             LEFT JOIN dbo.TbUsr AS Usr WITH (NOLOCK) ON Usr.CdUsr = Fat.CdUsrSep; 

#             /* ==========================================
#                 SELECT ÚNICO
#             ========================================== */
#             SELECT
#                 ID					= Fat.ID,
#                 NrRomaneio          = Fat.NrRomaneio,
#                 CdVpo               = Vpo.CdVpo,
#                 CdVpd               = Vpd.CdVpd,
#                 Data               = CONVERT(varchar, Fat.DtExp, 103) + ' ' + LEFT(CONVERT(varchar, Fat.DtExp, 108), 5),
#                 HrMovimento         =
#                     SUBSTRING(CONVERT(varchar, CONVERT(date, Fat.DtIniExpSep), 103), 1, 2) + '/' +
#                     SUBSTRING(CONVERT(varchar, CONVERT(date, Fat.DtIniExpSep), 103), 4, 2) + '/' +
#                     SUBSTRING(CONVERT(varchar, CONVERT(date, Fat.DtIniExpSep), 103), 7, 4) + ' ' +
#                     SUBSTRING(CONVERT(varchar, CONVERT(time, Fat.DtIniExpSep), 108), 1, 5),
#                 Descricao           = 'Romaneio :' + CONVERT(varchar, Fat.NrRomaneio) + ' Ped.:' + CONVERT(varchar, Vpd.CdVpd),
#                 CdObj               = Obj.CdObj,
#                 Objeto              = Obj.NmObj,
#                 DetalheID           = LotAtv.CdLot,
#                 Detalhe             = LotAtv.NmLot,
#                 QtPed               = Vpo.QtVpo,
#                 Qt                  = Fat.QtFat,
#                 QtReservado         = ISNULL(PedRes.Qt, 0) + ISNULL(Vpo.QtVpoFatCan, 0) - ISNULL(FatDoc.Qt, 0),
#                 Atendido            = Fat.QtFatAtend,
#                 QtRes               = LetReserva.Qt, 
#                 SaldoDoArtigo       = Vpo.QtVpo + ISNULL(Vpo.QtVpoFatCan, 0) - ISNULL(Vpo.QtVpoFat, 0),
#                 Nfe                 = Ffm.NrFfm,
#                 NrDC                = RcdDc.NrRcd,
#                 CdFat               = FatNfe.CdFat,
#                 CdRcd               = Rcd.CdRcd,
#                 Situacao            = ColFat.Descricao,
#                 PrazoPagto          = Fpg.NmFpg,
#                 FormaPagto          = Tcb.NmTcb,
#                 SitFinan            = ColFin.Descricao,
#                 Observacao          = Obs.TtObs,
#                 ObservacaoID        = ISNULL(Obs.CdObs, 0),
#                 Motivo              = CASE
#                                             WHEN Fat.TpMotivoCan = 1 THEN 'Artigo sem estoque'
#                                             WHEN Fat.TpMotivoCan = 2 THEN 'Artigo não encontrado'
#                                             WHEN Fat.TpMotivoCan = 3 THEN 'Solicitação do Comercial'
#                                             ELSE ''
#                                         END,
#                 Solicitante         = S.Solicitante,
#                 Separador           = UsrSep.NmUsr,
#                 IDSeparador         = ISNULL(Fat.CdUsrSep, 0), -- Garante 0 se for NULL
#                 UsrLogado           = (SELECT @CdUsr),
#                 Cliente             = Cli.NmCli,
#                 Transportadora      = COALESCE(NULLIF(LTRIM(RTRIM(Frn.NmFrn)), ''), 'SEM TRANSPORTADORA')

#             FROM #Stik_Pedido_QtdFat_Base AS Fat
#             -- O INNER JOIN com Sr já foi feito na criação da #Stik_Pedido_QtdFat_Base. Ele ainda está aqui, mas é redundante agora:
#             INNER JOIN dbo.Stik_Romaneio AS Sr WITH (NOLOCK) ON Sr.NrRomaneio = Fat.NrRomaneio
#             JOIN dbo.TbVpo  AS Vpo  WITH (NOLOCK) ON Vpo.CdVpo  = Fat.CdVpo 
#             JOIN dbo.TbVpd  AS Vpd  WITH (NOLOCK) ON Vpd.CdVpd  = Vpo.CdVpd 
#             LEFT JOIN dbo.TbCli  AS Cli  WITH (NOLOCK) ON Cli.CdCli = Vpd.CdCli 
#             LEFT JOIN dbo.TbObj  AS Obj  WITH (NOLOCK) ON Obj.CdObj = Fat.CdObj 
#             LEFT JOIN dbo.TbLot  AS LotAtv WITH (NOLOCK) ON LotAtv.CdLot = Vpo.CdLot 
#             LEFT JOIN dbo.TbObj  AS ObjAtv WITH (NOLOCK) ON ObjAtv.CdObj = LotAtv.CdObj 
            

#             /* NF-e (romaneio → fatura) */
#             LEFT JOIN dbo.Stik_NfeDoRomaneio AS FatNfe WITH (NOLOCK) 
#                         ON Fat.NrRomaneio = FatNfe.NrRomaneio
#             LEFT JOIN dbo.TbFtr AS Ftr WITH (NOLOCK) 
#                         ON Ftr.CdFat = FatNfe.CdFat
#             LEFT JOIN dbo.TbFad AS Fad WITH (NOLOCK) 
#                         ON Fad.CdFtr = Ftr.CdFtr
#                       AND Fad.CdTdo IN (99, 206)
#             LEFT JOIN dbo.TbRcd AS Rcd WITH (NOLOCK) 
#                         ON Rcd.CdFad = Fad.CdFad
#             LEFT JOIN dbo.TbFfm AS Ffm WITH (NOLOCK) 
#                         ON Ffm.CdFfm = Rcd.FolhaDeFormularioID_Nfe

#             /* DC (pedido de crédito / débito) */
#             LEFT JOIN dbo.TbFtr AS FtrDC WITH (NOLOCK) 
#                         ON FtrDC.CdFat = FatNfe.CdFat
#             LEFT JOIN dbo.TbFad AS FadDC WITH (NOLOCK) 
#                         ON FadDC.CdFtr = FtrDC.CdFtr
#                       AND FadDC.CdTdo = 98
#             LEFT JOIN dbo.TbRcd AS RcdDc WITH (NOLOCK) 
#                         ON RcdDc.CdFad = FadDC.CdFad

#             /* Domínios de status */
#             LEFT JOIN dbo.Stik_columndomain AS ColFat WITH (NOLOCK) 
#                         ON ColFat.colunaid = Fat.TpSitFat
#                       AND ColFat.nomedatabela = 'Stik_Pedido_QtdFat'
#                       AND ColFat.nomedacoluna = 'TpSitFat'
#             LEFT JOIN dbo.Stik_columndomain AS ColFin WITH (NOLOCK) 
#                         ON ColFin.colunaid = Fat.TpSitPag
#                       AND ColFin.nomedatabela = 'Stik_Pedido_QtdFat'
#                       AND ColFin.nomedacoluna = 'TpSitPag'

#             /* Separador e observações */
#             LEFT JOIN #UsrSep AS UsrSep
#                         ON UsrSep.CdVpd = Vpd.CdVpd 
#                       AND UsrSep.CdUsrSep = Fat.CdUsrSep
#             LEFT JOIN dbo.TbObs AS Obs WITH (NOLOCK) 
#                         ON Obs.CdObs = Vpd.CdObs
#             LEFT JOIN dbo.Stik_AvaliacaoSeparacao AS A WITH (NOLOCK) 
#                         ON A.NrRomaneio = Fat.NrRomaneio
#                       AND A.CdVpd = Vpd.CdVpd
#                       AND A.Separador = UsrSep.NmUsr

#             /* Saldos / reservas / docs */
#             LEFT JOIN #Estoque AS LetReserva
#                         ON LetReserva.CdObj = Vpo.CdObj
#                       AND LetReserva.CdUne = Vpd.CdUne
#             LEFT JOIN #PedRes  AS PedRes
#                         ON PedRes.CdVpo = Vpo.CdVpo
#                       AND PedRes.CdObj = Vpo.CdObj
#             LEFT JOIN #FatDoc  AS FatDoc
#                         ON FatDoc.CdVpo = Vpo.CdVpo

#             --Transporte
#             left join TbFrn Frn on Frn.CdFrn = Vpd.CdFrnTrp

#             --Prazo e Forma de Pagamento
#             left join TbFpg Fpg on Fpg.CdFpg = Vpd.CdFpg
#             left join TbTcb Tcb ON Tcb.CdTcb = Vpd.CdTcb

#             /* Solicitante de cancelamento */
#             LEFT JOIN dbo.Stik_Solicitante_Canc AS S WITH (NOLOCK) 
#                         ON S.CdVpo = Vpo.CdVpo


#             /* Filtro de cliente/objeto/nota (mantidos como no seu script, efetivamente liberados) */
#             WHERE (Vpd.CdVpd = 0 OR 0 = 0)
#               AND (Vpd.CdCli = 0 OR 0 = 0)
#               AND (0 = 0 OR EXISTS (
#                           SELECT 1
#                           FROM dbo.TbArvObj AS ArvObj WITH (NOLOCK) 
#                           WHERE ArvObj.CdObjFil = Vpo.CdObj
#                             AND ArvObj.CdObj     = 0
#                         ))
#               AND (CONVERT(int, ISNULL(Rcd.FolhaDeFormularioID_Nfe, 0)) = 0 OR 0 = 0)
              

#             /* Ordenação para API */
#             ORDER BY
#                 Fat.NrRomaneio,
#                 Vpd.CdVpd,
#                 Vpo.CdVpo,
#                 Obj.CdObj;
#         """
        
#         # Executa a consulta T-SQL passando as datas e o ID do usuário como parâmetros
#         cursor.execute(sql_query, (data_inicio, data_fim, cd_usr_int))


#         # Converte o resultado em uma lista de dicionários
#         registros = [dict(zip([column[0] for column in cursor.description], row)) for row in cursor.fetchall()]

#         romaneio_debug = 124804
#         registros_debug = [r for r in registros if int(r.get('NrRomaneio', 0) or 0) == romaneio_debug]
#         print(f"DEBUG get_romaneio {romaneio_debug}: {len(registros_debug)} registros")
#         for r in registros_debug[:5]:
#             print("DEBUG item", r.get('NrRomaneio'), r.get('CdVpo'), r.get('Situacao'), r.get('IDSeparador'))

        
#         print(f"✅ [{cd_usr_int}] Romaneios consultados: {len(registros)} registros")

#         return jsonify(registros)

#     except Exception as e:
#         print(f"❌ Erro ao consultar faturamento detalhado: {e}")
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()
#             print("🔌 Conexão com o banco de dados fechada.")

# # ===================================================================
# # ROTA 2: PUT (Para associar um separador a um romaneio)
# # ===================================================================
# @wms_bp.route('/consulta/romaneio/associar', methods=['PUT'])
# def associar_separador():
#     """
#     Endpoint para associar/reatribuir um separador a um NrRomaneio ESPECÍFICO.
#     Atualiza o status para 'Em Separação' (TpSitFat = 3).
#     """
#     connection = None
#     try:
#         data = request.get_json()
#         if not data:
#             return jsonify({"error": "Dados JSON não fornecidos"}), 400

#         nr_romaneio = data.get('NrRomaneio')
#         id_separador = data.get('IDSeparador')
        
#         # Novo campo para forçar a reatribuição (pode ser útil para administradores)
#         forcar_reatribuicao = data.get('ForcarReatribuicao', False) 

#         if not nr_romaneio or id_separador is None:
#             return jsonify({"error": "Campos 'NrRomaneio' e 'IDSeparador' são obrigatórios"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()

#         # A lógica de UPDATE na rota PUT está correta: atualiza CdUsrSep, e se o status for 2 (Pronto)
#         # o muda para 3 (Em Separação), registrando a data de início se ainda não tiver.
#         sql_update = f"""
#             SET NOCOUNT ON;
#             UPDATE dbo.Stik_Pedido_QtdFat
#             SET 
#                 CdUsrSep = ?,
#                 -- Atualiza o status para 3 (Em Separação) se o status ATUAL for 2 (Pronto)
#                 TpSitFat = CASE WHEN ? > 0 AND TpSitFat = 2 THEN 3 ELSE TpSitFat END,
#                 -- Registra a data de início (apenas se for o primeiro registro)
#                 DtIniExpSep = CASE WHEN DtIniExpSep IS NULL THEN GETDATE() ELSE DtIniExpSep END 
#             WHERE 
#                 NrRomaneio = ?
#                 -- Lógica de prevenção de reatribuição:
#                 AND (
#                     -- A reatribuição só é permitida se:
#                     -- 1. O romaneio não tem separador (NULL ou 0)
#                     CdUsrSep IS NULL 
#                     OR CdUsrSep = 0
#                     -- 2. OU o usuário forçadamente desatribuiu (IDSeparador = 0)
#                     OR ? = 0
#                     -- 3. OU a forçar_reatribuicao for True (para admins)
#                     OR ? = 1
#                 );
#         """

#         # Parâmetros: (id_separador, id_separador, nr_romaneio, id_separador, forcar_reatribuicao)
#         cursor.execute(sql_update, (id_separador, id_separador, nr_romaneio, id_separador, 1 if forcar_reatribuicao else 0))
        
#         if cursor.rowcount == 0:
#             connection.rollback()
            
#             # Se for uma tentativa de atribuição (ID > 0) e não houver linhas afetadas, 
#             # é porque ele já estava atribuído e não foi forçado.
#             if int(id_separador) > 0 and not forcar_reatribuicao:
#                 # O romaneio está atribuído, e o usuário não forçou a reatribuição.
#                 return jsonify({"error": f"O Romaneio {nr_romaneio} já está atribuído. Desassocie ou use Forçar Reatribuição (Admin)."}), 409
            
#             # Caso contrário, nenhum registro encontrado.
#             return jsonify({"error": f"Nenhum registro disponível encontrado para o Romaneio {nr_romaneio}."}), 404

#         connection.commit()

#         print(f"✅ Romaneio {nr_romaneio} → Separador {id_separador} (Linhas: {cursor.rowcount})")
        
#         return jsonify({
#             "success": True,
#             "message": f"Romaneio {nr_romaneio} associado com sucesso. Status atualizado para Em Separação.",
#             "romaneio": nr_romaneio,
#             "separador_id": id_separador,
#             "linhas_afetadas": cursor.rowcount
#         }), 200

#     except Exception as e:
#         if connection:
#             connection.rollback()
#         print(f"❌ Erro ao associar: {e}")
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()

# # ===================================================================
# # ROTA 3: POST (Para selecionar e bloquear o próximo romaneio disponível)
# # Implementa a lógica de SELECT TOP(1) e UPDATE (TpSitFat = 3)
# # ===================================================================
# @wms_bp.route('/consulta/romaneio/proximo', methods=['POST'])
# def selecionar_proximo_romaneio():
#     """
#     1. Seleciona o romaneio mais antigo (Min(DtExp)) com TpSitFat = 2 (Pronto para Separação).
#     2. Bloqueia o romaneio (atualiza TpSitFat = 3) e atribui o separador (CdUsrSep).
#     3. Retorna o NrRomaneio selecionado.
#     """
#     connection = None
#     try:
#         data = request.get_json()
#         if not data:
#             return jsonify({"error": "Dados JSON não fornecidos"}), 400

#         # O endpoint espera receber o ID do Separador que está pedindo o próximo romaneio
#         id_separador = data.get('IDSeparador')

#         if id_separador is None:
#             return jsonify({"error": "Campo 'IDSeparador' é obrigatório"}), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
        
#         # O SQL abaixo executa a lógica de seleção e atualização de forma ATÔMICA,
#         # prevenindo que dois separadores peguem o mesmo romaneio.
#         sql_select_and_update = f"""
#             SET NOCOUNT ON;
            
#             -- Variável para armazenar o romaneio que será selecionado
#             DECLARE @NrRomaneio INT;

#             -- 1. Seleciona o Romaneio mais antigo (Menor DtExp) em TpSitFat = 2 (Pronto para Separação)
#             -- e atribui o NrRomaneio à variável @NrRomaneio.
#             -- O uso de (UPDLOCK, HOLDLOCK) é CRUCIAL para bloquear a linha imediatamente 
#             -- e evitar que outro usuário a selecione ao mesmo tempo.
#             SELECT TOP(1)
#                 @NrRomaneio = Fat.NrRomaneio
#             FROM dbo.Stik_Pedido_QtdFat Fat WITH (UPDLOCK, HOLDLOCK)
#             WHERE
#                 Fat.TpSitFat = 2  -- Status: Pronto para Separação
#                 AND (Fat.CdUsrSep IS NULL OR Fat.CdUsrSep = 0) -- Não atribuído
#                 AND CONVERT(int, ISNULL(Fat.NrRomaneio, 0)) > 0 -- Garante que é um romaneio válido
#             GROUP BY
#                 Fat.NrRomaneio
#             ORDER BY
#                 MIN(Fat.DtExp) ASC; -- Seleciona o mais antigo
                
#             -- Se @NrRomaneio for NULL, nenhum romaneio disponível foi encontrado.
#             IF @NrRomaneio IS NULL
#             BEGIN
#                 SELECT 'NAO_ENCONTRADO' AS Status, NULL AS NrRomaneio;
#                 RETURN;
#             END
            
#             -- 2. Atualiza todos os itens desse Romaneio para TpSitFat = 3 (Em Separação)
#             -- e atribui o separador.
#             UPDATE dbo.Stik_Pedido_QtdFat
#             SET
#                 TpSitFat = 3,      -- NOVO STATUS: Em Separação
#                 DtIniExpSep = GETDATE(),
#                 CdUsrSep = ?
#             WHERE
#                 NrRomaneio = @NrRomaneio
#                 AND TpSitFat = 2; -- Confirma a transição de 2 para 3 (cobertura dupla)
                
#             -- Retorna o Romaneio selecionado
#             SELECT 'OK' AS Status, @NrRomaneio AS NrRomaneio;
#         """

#         # Executa o SQL, passando o ID do separador como parâmetro para o UPDATE
#         cursor.execute(sql_select_and_update, (id_separador,))
        
#         # Pega a linha de retorno (Status e NrRomaneio)
#         result = cursor.fetchone()
        
#         if not result or result[0] == 'NAO_ENCONTRADO':
#             connection.rollback()
#             return jsonify({
#                 "success": False,
#                 "message": "Nenhum romaneio disponível para separação (Status 2)."
#             }), 200

#         nr_romaneio = result[1]
#         connection.commit()

#         print(f"✅ Próximo Romaneio selecionado: {nr_romaneio} → Separador {id_separador}")
        
#         return jsonify({
#             "success": True,
#             "message": f"Romaneio {nr_romaneio} atribuído e bloqueado com sucesso",
#             "romaneio": nr_romaneio,
#             "separador_id": id_separador
#         }), 200

#     except Exception as e:
#         if connection:
#             connection.rollback()
#         print(f"❌ Erro ao selecionar próximo romaneio: {e}")
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()

# @wms_bp.route('/consulta/romaneio/cancelar_com_devolucao', methods=['POST'])
# def cancelar_romaneio_com_devolucao():
#     connection = None
#     try:
#         data = request.get_json()
#         if not data:
#             return jsonify({"error": "Dados JSON não fornecidos"}), 400

#         nr_romaneio = data.get('NrRomaneio')
#         motivo = data.get('Motivo')
#         solicitante = data.get('Solicitante')

#         if not all([nr_romaneio, motivo, solicitante]):
#             return jsonify({
#                 "error": "Campos 'NrRomaneio', 'Motivo' e 'Solicitante' são obrigatórios."
#             }), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON;")

#         itens_query = """
#             SELECT
#                 Fat.CdObj,
#                 LotAtv.CdLot AS DetalheID,
#                 Fat.QtFat AS Qt
#             FROM dbo.Stik_Pedido_QtdFat Fat
#             LEFT JOIN dbo.TbVpo Vpo ON Vpo.CdVpo = Fat.CdVpo
#             LEFT JOIN dbo.TbLot LotAtv ON LotAtv.CdLot = Vpo.CdLot
#             WHERE Fat.NrRomaneio = ?
#         """
#         cursor.execute(itens_query, (nr_romaneio,))
#         itens = cursor.fetchall()
#         if not itens:
#             return jsonify({"error": "Itens do romaneio não encontrados."}), 404

#         for cdobj, detalhe_id, qt in itens:
#             if not cdobj or not qt or qt <= 0:
#                 continue

#             # 1) Palete do SKU + Detalhe
#             palete_query = """
#                 SELECT TOP 1 Endereco
#                 FROM dbo.Stik_WMS_Alocacao
#                 WHERE CodSKU = ?
#                   AND Detalhe = ?
#                   AND (
#                         QtMaxima IS NULL
#                         OR (ISNULL(QtMaxima, 0) - ISNULL(QtAlocada, 0)) >= ?
#                       )
#                 ORDER BY (ISNULL(QtMaxima, 999999999) - ISNULL(QtAlocada, 0)) DESC,
#                          DataAtualizacao DESC
#             """
#             cursor.execute(palete_query, (cdobj, detalhe_id, qt))
#             row = cursor.fetchone()

#             # 2) Palete do SKU (qualquer Detalhe)
#             if not row:
#                 palete_fallback = """
#                     SELECT TOP 1 Endereco
#                     FROM dbo.Stik_WMS_Alocacao
#                     WHERE CodSKU = ?
#                       AND (
#                             QtMaxima IS NULL
#                             OR (ISNULL(QtMaxima, 0) - ISNULL(QtAlocada, 0)) >= ?
#                           )
#                     ORDER BY (ISNULL(QtMaxima, 999999999) - ISNULL(QtAlocada, 0)) DESC,
#                              DataAtualizacao DESC
#                 """
#                 cursor.execute(palete_fallback, (cdobj, qt))
#                 row = cursor.fetchone()

#             # 3) Qualquer palete com capacidade
#             if not row:
#                 palete_any = """
#                     SELECT TOP 1 Endereco
#                     FROM dbo.Stik_WMS_Alocacao
#                     WHERE (
#                         QtMaxima IS NULL
#                         OR (ISNULL(QtMaxima, 0) - ISNULL(QtAlocada, 0)) >= ?
#                     )
#                     ORDER BY (ISNULL(QtMaxima, 999999999) - ISNULL(QtAlocada, 0)) DESC,
#                              DataAtualizacao DESC
#                 """
#                 cursor.execute(palete_any, (qt,))
#                 row = cursor.fetchone()

#             if not row:
#                 return jsonify({
#                     "error": f"Sem palete com capacidade para SKU {cdobj} (det {detalhe_id}) para devolver {qt}"
#                 }), 400

#             endereco = row[0]

#             mov_query = """
#                 INSERT INTO dbo.stik_WMS_Movimento
#                     (Endereco, CodSKU, TpMov, QtMovida, Detalhe, DataMovimento)
#                 VALUES
#                     (?, ?, 1, ?, ?, SYSDATETIME());
#             """
#             cursor.execute(mov_query, (endereco, cdobj, qt, detalhe_id))

#         update_query = """
#             UPDATE Stik_Pedido_QtdFat
#             SET TpSitFat = 11,
#                 TpMotivoCan = ?
#             WHERE NrRomaneio = ?;
#         """
#         cursor.execute(update_query, (motivo, nr_romaneio))
#         if cursor.rowcount == 0:
#             return jsonify({"error": "Romaneio não encontrado."}), 404

#         insert_query = """
#             INSERT INTO Stik_Solicitante_Canc (DtCancelamento, Solicitante, CdVpo, NrRomaneio)
#             SELECT SYSDATETIME(), ?, CdVpo, NrRomaneio
#             FROM Stik_Pedido_QtdFat
#             WHERE NrRomaneio = ?;
#         """
#         cursor.execute(insert_query, (solicitante, nr_romaneio))

#         connection.commit()
#         return jsonify({"message": "Cancelamento com devolução realizado."}), 200

#     except Exception as e:
#         if connection:
#             connection.rollback()
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()

# @wms_bp.route('/consulta/romaneio/lista_conferencia', methods=['GET'])
# def get_lista_conferencia():
#     connection = None
#     try:
#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({
#                 "status": "SQL_ERROR",
#                 "details": "Falha ao conectar ao banco."
#             }), 500

#         cursor = connection.cursor()

#         sql_query = """
#             SET NOCOUNT ON;

#             SELECT
#                 Sep.NrRomaneio,
#                 Sep.CdVpo,
#                 Vpd.CdVpd,
#                 Sep.CdObj,
#                 Sep.CdLot,
#                 Cli.NmCli AS Cliente,
#                 Obj.NmObj AS Objeto,
#                 Lot.NmLot AS Detalhe,
#                 Fat.ID,
#                 Fat.DtExp AS DataExpedicao,
#                 Sep.DtSeparacao AS DataConclusaoSep,
#                 Usr.NmUsr AS Separador,
#                 COUNT(*) OVER (PARTITION BY Sep.NrRomaneio) AS TotalItens,
#                 Fat.QtFat AS Qt,
#                 Sep.QtSeparada AS QtSeparada
#             FROM dbo.Stik_WMS_Romaneio_Separado Sep WITH (NOLOCK)
#             JOIN dbo.TbVpo Vpo WITH (NOLOCK)
#                 ON Vpo.CdVpo = Sep.CdVpo
#             JOIN dbo.TbVpd Vpd WITH (NOLOCK)
#                 ON Vpd.CdVpd = Vpo.CdVpd
#             LEFT JOIN dbo.TbCli Cli WITH (NOLOCK)
#                 ON Cli.CdCli = Vpd.CdCli
#             LEFT JOIN dbo.TbUsr Usr WITH (NOLOCK)
#                 ON Usr.CdUsr = Sep.CdUsrSep
#             LEFT JOIN dbo.Stik_Pedido_QtdFat Fat WITH (NOLOCK)
#                 ON Fat.NrRomaneio = Sep.NrRomaneio
#                AND Fat.CdVpo = Sep.CdVpo
#             LEFT JOIN dbo.TbObj Obj WITH (NOLOCK)
#                 ON Obj.CdObj = Sep.CdObj
#             LEFT JOIN dbo.TbLot Lot WITH (NOLOCK)
#                 ON Lot.CdLot = Sep.CdLot
#             WHERE Sep.Separado = 1
#               AND NOT EXISTS (
#                     SELECT 1
#                     FROM dbo.Stik_WMS_Romaneio_Conferencia Conf WITH (NOLOCK)
#                     WHERE Conf.NrRomaneio = Sep.NrRomaneio
#                       AND Conf.CdVpo = Sep.CdVpo
#                       AND ISNULL(Conf.CdObj, 0) = ISNULL(Sep.CdObj, 0)
#                       AND ISNULL(Conf.Detalhe, 0) = ISNULL(Sep.CdLot, 0)
#                       AND Conf.SituacaoConferencia = 'SEPARADO_CONFERIDO'
#               )
#             ORDER BY Sep.DtSeparacao ASC
#         """
#         print("DEBUG lista_conferencia executando")

#         cursor.execute(sql_query)
#         registros = [
#             dict(zip([column[0] for column in cursor.description], row))
#             for row in cursor.fetchall()
#         ]

#         return jsonify(registros), 200

#     # except Exception as e:
#     #     return jsonify({"error": str(e)}), 500

#     except Exception as e:
#         print(f"❌ Erro ao listar conferência: {e}")
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


# @wms_bp.route('/consulta/romaneio/confirmar_conferencia', methods=['PUT'])
# def confirmar_conferencia():
#     connection = None
#     try:
#         data = request.get_json()
#         nr_romaneio = data.get('NrRomaneio')
#         qt_conferida = float(data.get('QtFatAtend', 0))
        
#         # 1. BUSCAR A QUANTIDADE ORIGINAL SOLICITADA (QtFat)
#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()
        
#         cursor.execute("SELECT SUM(QtFat) FROM Stik_Pedido_QtdFat WHERE NrRomaneio = ?", (nr_romaneio,))
#         row = cursor.fetchone()
#         qt_pedida = float(row[0]) if row and row[0] else 0

#         # 2. VALIDAR A REGRA DE NEGÓCIO
#         # Se você não quer que finalize com quantidade divergente:
#         if qt_conferida != qt_pedida:
#             return jsonify({
#                 "error": f"Divergência: Pedido {qt_pedida} / Conferido {qt_conferida}. O status permanecerá em separação."
#             }), 400

#         # 3. SE ESTIVER TUDO OK, EXECUTA O UPDATE COM A TRAVA DE STATUS
#         sql_update = """
#             UPDATE dbo.Stik_Pedido_QtdFat
#             SET TpSitFat = 4, QtFatAtend = ?, CdUsrConf = ?, DtConf = GETDATE()
#             WHERE NrRomaneio = ? AND TpSitFat = 3
#         """
#         cursor.execute(sql_update, (qt_conferida, data.get('CdUsrConf'), nr_romaneio))
        
#         if cursor.rowcount == 0:
#             return jsonify({"error": "Romaneio não encontrado ou já processado."}), 404

#         connection.commit()
#         return jsonify({"success": True, "message": "Conferência finalizada com sucesso."})

#     except Exception as e:
#         if connection: connection.rollback()
#         return jsonify({"error": str(e)}), 500

        
# @wms_bp.route('/consulta/romaneio/finalizar_separacao', methods=['PUT'])
# def finalizar_separacao():
#     connection = None
#     try:
#         data = request.get_json() or {}

#         nr_romaneio = data.get('nr_romaneio')
#         usuario_id = data.get('cd_usr_conf') or data.get('UsuarioID')
#         itens = data.get('itens', [])

#         if not nr_romaneio or not usuario_id or not isinstance(itens, list) or not itens:
#             return jsonify({
#                 "error": "Campos obrigatórios ausentes",
#                 "recebido": data
#             }), 400

#         try:
#             nr_romaneio = int(nr_romaneio)
#             usuario_id = int(usuario_id)
#         except (TypeError, ValueError):
#             return jsonify({
#                 "error": "nr_romaneio ou usuario_id inválido",
#                 "recebido": {
#                     "nr_romaneio": nr_romaneio,
#                     "usuario_id": usuario_id
#                 }
#             }), 400

#         itens_validos = []
#         for idx, item in enumerate(itens, start=1):
#             cd_vpo = item.get('cdVpo') or item.get('CdVpo')
#             cd_obj = item.get('CdObj') or item.get('cdObj')
#             cd_lot = item.get('CdLot') or item.get('cdLot') or item.get('DetalheId')
#             qt_sep = item.get('quantidadeSeparada')

#             if cd_vpo is None or qt_sep is None:
#                 return jsonify({
#                     "error": f"Item {idx}: CdVpo e quantidadeSeparada são obrigatórios"
#                 }), 400

#             try:
#                 cd_vpo = int(cd_vpo)
#                 cd_obj = int(cd_obj) if cd_obj is not None else 0
#                 cd_lot = int(cd_lot) if cd_lot is not None else 0
#                 qt_sep = float(str(qt_sep).replace(',', '.'))
#             except (TypeError, ValueError):
#                 return jsonify({"error": f"Item {idx}: dados inválidos"}), 400

#             itens_validos.append((cd_vpo, cd_obj, cd_lot, qt_sep))

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({
#                 "status": "SQL_ERROR",
#                 "details": "Falha ao conectar ao banco de dados."
#             }), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         sql_upsert_fila = """
#             IF EXISTS (
#                 SELECT 1
#                 FROM dbo.Stik_WMS_Romaneio_Separado
#                 WHERE NrRomaneio = ?
#                   AND CdVpo = ?
#                   AND ISNULL(CdObj, 0) = ISNULL(?, 0)
#                   AND ISNULL(CdLot, 0) = ISNULL(?, 0)
#             )
#             BEGIN
#                 UPDATE dbo.Stik_WMS_Romaneio_Separado
#                 SET
#                     QtSeparada = ?,
#                     CdUsrSep = ?,
#                     DtSeparacao = GETDATE(),
#                     Separado = 1
#                 WHERE NrRomaneio = ?
#                   AND CdVpo = ?
#                   AND ISNULL(CdObj, 0) = ISNULL(?, 0)
#                   AND ISNULL(CdLot, 0) = ISNULL(?, 0)
#             END
#             ELSE
#             BEGIN
#                 INSERT INTO dbo.Stik_WMS_Romaneio_Separado
#                     (NrRomaneio, CdVpo, CdObj, CdLot, QtSeparada, CdUsrSep, DtSeparacao, Separado)
#                 VALUES
#                     (?, ?, ?, ?, ?, ?, GETDATE(), 1)
#             END
#         """

#         itens_processados = []

#         for cd_vpo, cd_obj, cd_lot, qt_sep in itens_validos:
#             cursor.execute(
#                 sql_upsert_fila,
#                 (
#                     nr_romaneio, cd_vpo, cd_obj, cd_lot,
#                     qt_sep, usuario_id, nr_romaneio, cd_vpo, cd_obj, cd_lot,
#                     nr_romaneio, cd_vpo, cd_obj, cd_lot, qt_sep, usuario_id
#                 )
#             )

#             cursor.execute("""
#                 SELECT COUNT(1)
#                 FROM dbo.Stik_WMS_Romaneio_Separado
#                 WHERE NrRomaneio = ?
#                   AND CdVpo = ?
#                   AND ISNULL(CdObj, 0) = ISNULL(?, 0)
#                   AND ISNULL(CdLot, 0) = ISNULL(?, 0)
#             """, (nr_romaneio, cd_vpo, cd_obj, cd_lot))
#             count_row = cursor.fetchone()
#             count_value = count_row[0] if count_row else 0

#             print(
#                 f"DEBUG finalizar_separacao romaneio={nr_romaneio} "
#                 f"cd_vpo={cd_vpo} cd_obj={cd_obj} cd_lot={cd_lot} "
#                 f"qt_sep={qt_sep} count={count_value}"
#             )

#             itens_processados.append({
#                 "CdVpo": cd_vpo,
#                 "CdObj": cd_obj,
#                 "CdLot": cd_lot,
#                 "QtSeparada": qt_sep,
#                 "FilaCount": count_value
#             })

#         connection.commit()

#         cursor.execute("""
#             SELECT NrRomaneio, CdVpo, CdObj, CdLot, QtSeparada
#             FROM dbo.Stik_WMS_Romaneio_Separado
#             WHERE NrRomaneio = ?
#         """, (nr_romaneio,))
#         print("DEBUG apos commit fila", cursor.fetchall())

#         return jsonify({
#             "status": "SQL_SUCCESS",
#             "message": "Separação finalizada com quantidades gravadas na fila da conferência.",
#             "nr_romaneio": nr_romaneio,
#             "itens_processados": itens_processados
#         }), 200

#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({
#             "status": "SQL_ERROR",
#             "details": str(e)
#         }), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_bp.route('/consulta/romaneio/conferir2', methods=['PUT'])
# def conferir_item_romaneio():
#     connection = None
#     try:
#         data = request.get_json() or {}

#         id_registro = data.get('ID')
#         qt_atendida = data.get('QtAtendida')
#         cd_usr_conf = data.get('CdUsrConf')
#         tp_sit_can = data.get('TpSitCan', 0)
#         tp_motivo_can = data.get('TpMotivoCan', 0)

#         if not id_registro or qt_atendida is None or not cd_usr_conf:
#             return jsonify({"error": "Campos obrigatórios: ID, QtAtendida, CdUsrConf"}), 400

#         try:
#             id_registro = int(id_registro)
#             qt_atendida = float(str(qt_atendida).replace(',', '.'))
#             cd_usr_conf = int(cd_usr_conf)
#             tp_sit_can = int(tp_sit_can)
#             tp_motivo_can = int(tp_motivo_can)
#         except (TypeError, ValueError):
#             return jsonify({"error": "ID/QtAtendida/CdUsrConf inválidos"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET XACT_ABORT ON;")

#         cursor.execute("""
#             SELECT
#                 Fat.ID,
#                 Fat.NrRomaneio,
#                 Fat.CdVpo,
#                 ISNULL(Fat.CdObj, 0) AS CdObj,
#                 ISNULL(Vpo.CdLot, 0) AS CdLot,
#                 Fat.TpSitFat
#             FROM dbo.Stik_Pedido_QtdFat Fat WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
#             LEFT JOIN dbo.TbVpo Vpo WITH (NOLOCK)
#                 ON Vpo.CdVpo = Fat.CdVpo
#             WHERE Fat.ID = ?
#         """, (id_registro,))
#         row = cursor.fetchone()

#         if not row:
#             return jsonify({"error": "Registro não encontrado."}), 404

#         _, nr_romaneio, cd_vpo, cd_obj, cd_lot, tp_sit_fat = row

#         if tp_sit_fat != 4:
#             return jsonify({
#                 "error": f"Item não está disponível para conferência. TpSitFat atual: {tp_sit_fat}"
#             }), 409

#         cursor.execute("""
#             SELECT QtSeparada
#             FROM dbo.Stik_WMS_Romaneio_Separado WITH (NOLOCK)
#             WHERE NrRomaneio = ?
#               AND CdVpo = ?
#         """, (nr_romaneio, cd_vpo))
#         row_sep = cursor.fetchone()

#         if not row_sep:
#             return jsonify({
#                 "error": "Quantidade separada não encontrada na fila da conferência."
#             }), 404

#         qt_separada = float(row_sep[0])

#         if abs(qt_atendida - qt_separada) > 0.0001:
#             return jsonify({
#                 "error": "Quantidade divergente da separação.",
#                 "NrRomaneio": nr_romaneio,
#                 "CdVpo": cd_vpo,
#                 "QtDigitada": qt_atendida,
#                 "QtReferencia": qt_separada
#             }), 409

#         cursor.execute("""
#             UPDATE dbo.Stik_Pedido_QtdFat
#             SET
#                 QtFatAtend = ?,
#                 TpSitFat = 5,
#                 TpSitCan = ?,
#                 TpMotivoCan = ?,
#                 CdUsrConf = ?,
#                 DtConf = GETDATE()
#             WHERE ID = ?
#               AND TpSitFat = 4
#         """, (qt_atendida, tp_sit_can, tp_motivo_can, cd_usr_conf, id_registro))

#         if cursor.rowcount != 1:
#             connection.rollback()
#             return jsonify({"error": "Nenhuma linha atualizada para o item."}), 409

#         cursor.execute("""
#             UPDATE dbo.Stik_WMS_Romaneio_Separado
#             SET Separado = 2
#             WHERE NrRomaneio = ?
#               AND CdVpo = ?
#         """, (nr_romaneio, cd_vpo))

#         print("DEBUG conferir2 fila rowcount", cursor.rowcount, nr_romaneio, cd_vpo)

#         if cursor.rowcount != 1:
#             connection.rollback()
#             return jsonify({
#                 "error": "Falha ao atualizar fila da conferência."
#             }), 409

#         connection.commit()

#         return jsonify({
#             "message": "Item enviado para faturamento com sucesso.",
#             "ID": id_registro,
#             "NrRomaneio": nr_romaneio,
#             "CdVpo": cd_vpo,
#             "QtAtendida": qt_atendida
#         }), 200

#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()

# @wms_bp.route('/consulta/romaneio/separado_conferido', methods=['PUT'])
# def marcar_separado_conferido():
#     connection = None
#     try:
#         data = request.get_json() or {}

#         nr_romaneio = data.get('NrRomaneio')
#         cd_usr_conf = data.get('CdUsrConf')
#         itens = data.get('itens', [])

#         if not nr_romaneio or not cd_usr_conf or not isinstance(itens, list) or not itens:
#             return jsonify({"error": "Campos obrigatórios: NrRomaneio, CdUsrConf, itens"}), 400

#         try:
#             nr_romaneio = int(nr_romaneio)
#             cd_usr_conf = int(cd_usr_conf)
#         except (TypeError, ValueError):
#             return jsonify({"error": "NrRomaneio ou CdUsrConf inválido"}), 400

#         itens_validos = []
#         for idx, item in enumerate(itens, start=1):
#             cd_vpo = item.get('CdVpo') or item.get('cdVpo')
#             cd_obj = item.get('CdObj') or item.get('cdObj')
#             cd_lot = item.get('CdLot') or item.get('cdLot') or item.get('DetalheId')

#             if cd_vpo is None:
#                 return jsonify({"error": f"Item {idx}: CdVpo obrigatório"}), 400

#             try:
#                 cd_vpo = int(cd_vpo)
#                 cd_obj = int(cd_obj) if cd_obj is not None else 0
#                 cd_lot = int(cd_lot) if cd_lot is not None else 0
#             except (TypeError, ValueError):
#                 return jsonify({"error": f"Item {idx}: CdVpo/CdObj/CdLot inválidos"}), 400

#             itens_validos.append((cd_vpo, cd_obj, cd_lot))

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET XACT_ABORT ON;")

#         sql_get_qt = """
#             SELECT QtSeparada
#             FROM dbo.Stik_WMS_Romaneio_Separado
#             WHERE NrRomaneio = ?
#               AND CdVpo = ?
#         """

#         sql_insert_conf = """
#             IF NOT EXISTS (
#                 SELECT 1
#                 FROM dbo.Stik_WMS_Romaneio_Conferencia
#                 WHERE NrRomaneio = ?
#                   AND CdVpo = ?
#                   AND ISNULL(CdObj, 0) = ISNULL(?, 0)
#                   AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#                   AND SituacaoConferencia = 'SEPARADO_CONFERIDO'
#             )
#             BEGIN
#                 INSERT INTO dbo.Stik_WMS_Romaneio_Conferencia
#                     (NrRomaneio, CdVpo, CdObj, Detalhe, SituacaoConferencia, CdUsrConf, DtConf)
#                 VALUES
#                     (?, ?, ?, ?, 'SEPARADO_CONFERIDO', ?, GETDATE())
#             END
#         """

#         sql_update_principal = """
#             UPDATE dbo.Stik_Pedido_QtdFat
#             SET
#                 QtFatAtend = ?,
#                 TpSitFat = 4,
#                 CdUsrConf = ?,
#                 DtConf = GETDATE()
#             WHERE NrRomaneio = ?
#               AND CdVpo = ?
#         """

#         sql_update_fila = """
#             UPDATE dbo.Stik_WMS_Romaneio_Separado
#             SET Separado = 2
#             WHERE NrRomaneio = ?
#               AND CdVpo = ?
#         """

#         itens_processados = []

#         for cd_vpo, cd_obj, cd_lot in itens_validos:
#             cursor.execute(sql_get_qt, (nr_romaneio, cd_vpo))
#             row = cursor.fetchone()
#             if not row:
#                 connection.rollback()
#                 return jsonify({
#                     "error": f"Quantidade separada não encontrada para CdVpo {cd_vpo}."
#                 }), 404

#             qt_separada = float(row[0])

#             cursor.execute(
#                 sql_insert_conf,
#                 (
#                     nr_romaneio, cd_vpo, cd_obj, cd_lot,
#                     nr_romaneio, cd_vpo, cd_obj, cd_lot, cd_usr_conf
#                 )
#             )

#             cursor.execute(
#                 sql_update_principal,
#                 (qt_separada, cd_usr_conf, nr_romaneio, cd_vpo)
#             )
#             if cursor.rowcount != 1:
#                 connection.rollback()
#                 return jsonify({
#                     "error": f"Falha ao atualizar principal para CdVpo {cd_vpo}."
#                 }), 409

#             cursor.execute(sql_update_fila, (nr_romaneio, cd_vpo))
#             print("DEBUG separado_conferido fila rowcount", cursor.rowcount, nr_romaneio, cd_vpo)

#             cursor.execute("""
#                 SELECT Separado
#                 FROM dbo.Stik_WMS_Romaneio_Separado
#                 WHERE NrRomaneio = ?
#                   AND CdVpo = ?
#             """, (nr_romaneio, cd_vpo))
#             row_fila = cursor.fetchone()

#             if not row_fila:
#                 connection.rollback()
#                 return jsonify({
#                     "error": f"Fila não encontrada para CdVpo {cd_vpo}."
#                 }), 404

#             if int(row_fila[0] or 0) != 2:
#                 connection.rollback()
#                 return jsonify({
#                     "error": f"Fila não atualizada para Separado=2 no CdVpo {cd_vpo}."
#                 }), 409

#             itens_processados.append({
#                 "CdVpo": cd_vpo,
#                 "CdObj": cd_obj,
#                 "CdLot": cd_lot,
#                 "QtSeparada": qt_separada
#             })

#         connection.commit()

#         return jsonify({
#             "success": True,
#             "message": f"Romaneio {nr_romaneio} marcado como Separado/Conferido.",
#             "nr_romaneio": nr_romaneio,
#             "itens_processados": itens_processados
#         }), 200

#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"status": "SQL_ERROR", "details": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()


# @wms_bp.route('/consulta/romaneio/finalizados', methods=['GET'])
# def listar_romaneios_finalizados():
#     connection = None
#     try:
#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({
#                 "status": "SQL_ERROR",
#                 "details": "Falha ao conectar ao banco."
#             }), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON;")

#         sql_query = """
#             WITH Base AS (
#                 SELECT
#                     Fat.NrRomaneio,
#                     MAX(Fat.TpSitFat) AS TpSitFat,
#                     MAX(Fat.CdUsrConf) AS CdUsrConf,
#                     MAX(Fat.DtConf) AS DataAtualizacao
#                 FROM dbo.Stik_Pedido_QtdFat Fat WITH (NOLOCK)
#                 WHERE Fat.TpSitFat IN (4, 5)
#                 GROUP BY Fat.NrRomaneio
#             )
#             SELECT
#                 B.NrRomaneio,
#                 Situacao = CASE
#                     WHEN B.TpSitFat = 4 THEN 'Separado/Conferido'
#                     WHEN B.TpSitFat = 5 THEN 'Ag.Faturamento'
#                     ELSE 'N/D'
#                 END,
#                 B.CdUsrConf,
#                 Usuario = Usr.NmUsr,
#                 DataConferencia = B.DataAtualizacao,
#                 DataAtualizacao = B.DataAtualizacao
#             FROM Base B
#             LEFT JOIN dbo.TbUsr Usr WITH (NOLOCK)
#                 ON Usr.CdUsr = B.CdUsrConf
#             ORDER BY B.DataAtualizacao DESC
#         """

#         cursor.execute(sql_query)
#         registros = [
#             dict(zip([column[0] for column in cursor.description], row))
#             for row in cursor.fetchall()
#         ]

#         return jsonify(registros), 200

#     except Exception as e:
#         return jsonify({
#             "status": "SQL_ERROR",
#             "details": str(e)
#         }), 500
#     finally:
#         if connection:
#             connection.close()


# # ===================================================================
# # ROTA: Cancelar Romaneio
# # ===================================================================
# @wms_bp.route('/consulta/romaneio/cancelar', methods=['POST'])
# def cancelar_romaneio():
#     """
#     Cancela um romaneio.
#     Campos obrigatórios: NrRomaneio, Motivo (int), Solicitante (string)
#     """
#     connection = None
#     try:
#         data = request.get_json()
#         if not data:
#             return jsonify({"error": "Dados JSON não fornecidos"}), 400

#         nr_romaneio = data.get('NrRomaneio')
#         motivo = data.get('Motivo')
#         solicitante = data.get('Solicitante')

#         if not all([nr_romaneio, motivo, solicitante]):
#             return jsonify({
#                 "error": "Campos 'NrRomaneio', 'Motivo' e 'Solicitante' são obrigatórios."
#             }), 400

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()

#         # Atualiza situação do romaneio
#         update_query = """
#             UPDATE Stik_Pedido_QtdFat
#             SET TpSitFat = 11,
#                 TpMotivoCan = ?
#             WHERE NrRomaneio = ?;
#         """
#         cursor.execute(update_query, (motivo, nr_romaneio))

#         if cursor.rowcount == 0:
#             return jsonify({"error": "Romaneio não encontrado."}), 404

#         # Registra solicitante do cancelamento
#         insert_query = """
#             INSERT INTO Stik_Solicitante_Canc (DtCancelamento, Solicitante, CdVpo, NrRomaneio)
#             SELECT GETDATE(), ?, CdVpo, NrRomaneio
#             FROM Stik_Pedido_QtdFat
#             WHERE NrRomaneio = ?;
#         """
#         cursor.execute(insert_query, (solicitante, nr_romaneio))

#         connection.commit()

#         return jsonify({
#             "message": "Cancelamento solicitado com sucesso!",
#             "NrRomaneio": nr_romaneio,
#             "Motivo": motivo,
#             "Solicitante": solicitante
#         }), 200

#     except Exception as e:
#         if connection:
#             connection.rollback()
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()


# # ===================================================================
# # ROTA: Atualizar Romaneios
# # ===================================================================
# @wms_bp.route('/consulta/romaneio/delta', methods=['GET'])
# def get_romaneio_delta():



#     connection = None
#     try:
#         since_raw = request.args.get('since')  # 'YYYY-MM-DD HH:MM:SS'
#         cd_usr = request.args.get('cd_usr', '0')
#         try:
#             cd_usr_int = int(cd_usr)
#         except ValueError:
#             cd_usr_int = 0

#         if not since_raw:
#             since_raw = datetime.datetime.now().strftime('%Y-%m-%d 00:00:00')

#         connection = create_connection_tinturaria()
#         cursor = connection.cursor()

#         sql_query = """
#             SET NOCOUNT ON;

#             DECLARE @Since datetime = ?;
#             DECLARE @CdUsr int = ?;

#             SELECT NrRomaneio, CdVpo, CdUsrSep, ChangeType, ChangedAt, Payload
#             FROM dbo.Romaneio_ChangeLog
#             WHERE ChangedAt >= @Since
#               AND (
#                     @CdUsr = 0
#                     OR @CdUsr IN (58, 97, 258, 313, 323, 322, 343, 325, 350, 357, 372, 183, 324, 168, 294, 375, 376, 329, 328, 334, 400, 421, 461, 226, 325, 327, 207, 334)
#                     OR CdUsrSep IS NULL
#                     OR CdUsrSep = 0
#                     OR CdUsrSep = @CdUsr
#                   )
#             ORDER BY ChangedAt;
#         """

#         cursor.execute(sql_query, (since_raw, cd_usr_int))
#         registros = [dict(zip([c[0] for c in cursor.description], r)) for r in cursor.fetchall()]
#         return jsonify(registros)

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()

# @wms_bp.route('/consulta/romaneio/cancelar_item', methods=['PUT', 'POST'])
# def cancelar_item_romaneio():
#     connection = None
#     try:
#         data = request.get_json() or {}

#         nr_romaneio = data.get('NrRomaneio')
#         cd_vpo = data.get('CdVpo')
#         cd_obj = data.get('CdObj')
#         cd_lot = data.get('CdLot')
#         motivo = data.get('Motivo')
#         solicitante = data.get('Solicitante')

#         if not nr_romaneio or not cd_vpo or motivo is None:
#             return jsonify({
#                 "error": "NrRomaneio, CdVpo e Motivo são obrigatórios"
#             }), 400

#         try:
#             nr_romaneio = int(nr_romaneio)
#             cd_vpo = int(cd_vpo)
#             cd_obj = int(cd_obj) if cd_obj is not None else 0
#             cd_lot = int(cd_lot) if cd_lot is not None else 0
#             motivo = int(motivo)
#         except (TypeError, ValueError):
#             return jsonify({
#                 "error": "NrRomaneio, CdVpo, CdObj, CdLot ou Motivo inválidos"
#             }), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({
#                 "status": "SQL_ERROR",
#                 "details": "Falha ao conectar ao banco."
#             }), 500

#         cursor = connection.cursor()
#         cursor.execute("SET XACT_ABORT ON;")

#         cursor.execute("""
#             SELECT ID, CdObj, CdLot
#             FROM dbo.Stik_Pedido_QtdFat
#             WHERE NrRomaneio = ?
#               AND CdVpo = ?
#         """, (nr_romaneio, cd_vpo))
#         row = cursor.fetchone()

#         if not row:
#             return jsonify({"error": "Item do romaneio não encontrado."}), 404

#         _, db_cd_obj, db_cd_lot = row

#         if cd_obj and int(db_cd_obj or 0) != cd_obj:
#             return jsonify({"error": "CdObj divergente para o item informado."}), 409

#         if cd_lot and int(db_cd_lot or 0) != cd_lot:
#             return jsonify({"error": "CdLot divergente para o item informado."}), 409

#         cursor.execute("""
#             UPDATE dbo.Stik_Pedido_QtdFat
#             SET
#                 TpSitFat = 11,
#                 TpMotivoCan = ?
#             WHERE NrRomaneio = ?
#               AND CdVpo = ?
#         """, (motivo, nr_romaneio, cd_vpo))

#         if cursor.rowcount != 1:
#             connection.rollback()
#             return jsonify({"error": "Nenhuma linha atualizada para o item."}), 409

#         if solicitante:
#             cursor.execute("""
#                 INSERT INTO dbo.Stik_Solicitante_Canc
#                     (DtCancelamento, Solicitante, CdVpo, NrRomaneio)
#                 VALUES
#                     (GETDATE(), ?, ?, ?)
#             """, (str(solicitante), cd_vpo, nr_romaneio))

#         connection.commit()

#         return jsonify({
#             "success": True,
#             "message": "Item cancelado com sucesso.",
#             "NrRomaneio": nr_romaneio,
#             "CdVpo": cd_vpo
#         }), 200

#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()

# @wms_bp.route('/consulta/wms/palete/itens_embalagem', methods=['GET'])
# def listar_itens_palete_embalagem():
#     connection = None
#     try:
#         endereco = (request.args.get('endereco') or '').strip().upper()
#         if not endereco:
#             return jsonify({"error": "Parâmetro obrigatório: endereco"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({"error": "Falha ao conectar ao banco."}), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON;")

#         sql = """
#             WITH BaseItens AS (
#                 SELECT
#                     Endereco = UPPER(LTRIM(RTRIM(A.Endereco))),
#                     A.CodSKU,
#                     CdLot = ISNULL(A.Detalhe, 0),
#                     QtSaldoFinal = ISNULL(A.QtAlocada, 0)
#                 FROM dbo.Stik_WMS_Alocacao A WITH (NOLOCK)
#                 WHERE UPPER(LTRIM(RTRIM(A.Endereco))) = ?
#             ),
#             MovItens AS (
#                 SELECT
#                     Endereco = UPPER(LTRIM(RTRIM(M.Endereco))),
#                     M.CodSKU,
#                     CdLot = ISNULL(M.Detalhe, 0),
#                     QtSaldoFinal = SUM(
#                         CASE
#                             WHEN M.TpMov = 1 THEN ISNULL(M.QtMovida, 0)
#                             WHEN M.TpMov = 3 THEN ISNULL(M.QtMovida, 0)
#                             WHEN M.TpMov = 2 THEN -ISNULL(M.QtMovida, 0)
#                             ELSE 0
#                         END
#                     )
#                 FROM dbo.Stik_WMS_Movimento M WITH (NOLOCK)
#                 WHERE UPPER(LTRIM(RTRIM(M.Endereco))) = ?
#                 GROUP BY
#                     UPPER(LTRIM(RTRIM(M.Endereco))),
#                     M.CodSKU,
#                     ISNULL(M.Detalhe, 0)
#             ),
#             EmbAtual AS (
#                 SELECT
#                     Endereco = UPPER(LTRIM(RTRIM(E.Endereco))),
#                     E.CodSKU,
#                     CdLot = ISNULL(E.Detalhe, 0),
#                     QtCaixaP = ISNULL(E.QtCaixaP, 0),
#                     QtCaixaG = ISNULL(E.QtCaixaG, 0),
#                     QtEnfestado = ISNULL(E.QtEnfestado, 0),
#                     QtEnfraldado = ISNULL(E.QtEnfraldado, 0)
#                 FROM dbo.Stik_WMS_Alocacao_Embalagem E WITH (NOLOCK)
#                 WHERE UPPER(LTRIM(RTRIM(E.Endereco))) = ?
#             ),
#             EmbMov AS (
#                 SELECT
#                     M.CodSKU,
#                     CdLot = ISNULL(M.Detalhe, 0),
#                     QtCaixaP = SUM(
#                         CASE
#                             WHEN M.TpMov = 4
#                                  AND UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN ISNULL(M.QtCaixaP, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaP, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaP, 0)
#                             ELSE 0
#                         END
#                     ),
#                     QtCaixaG = SUM(
#                         CASE
#                             WHEN M.TpMov = 4
#                                  AND UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN ISNULL(M.QtCaixaG, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaG, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaG, 0)
#                             ELSE 0
#                         END
#                     ),
#                     QtEnfestado = SUM(
#                         CASE
#                             WHEN M.TpMov = 4
#                                  AND UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN ISNULL(M.QtEnfestado, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtEnfestado, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtEnfestado, 0)
#                             ELSE 0
#                         END
#                     ),
#                     QtEnfraldado = SUM(
#                         CASE
#                             WHEN M.TpMov = 4
#                                  AND UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN ISNULL(M.QtEnfraldado, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtEnfraldado, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtEnfraldado, 0)
#                             ELSE 0
#                         END
#                     )
#                 FROM dbo.Stik_WMS_Movimento_Embalagem M WITH (NOLOCK)
#                 WHERE (
#                     UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ?
#                     OR UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ?
#                 )
#                 GROUP BY
#                     M.CodSKU,
#                     ISNULL(M.Detalhe, 0)
#             ),
#             Chaves AS (
#                 SELECT CodSKU, CdLot FROM BaseItens
#                 UNION
#                 SELECT CodSKU, CdLot FROM MovItens
#                 UNION
#                 SELECT CodSKU, CdLot FROM EmbAtual
#                 UNION
#                 SELECT CodSKU, CdLot FROM EmbMov
#             )
#             SELECT
#                 Endereco = ?,
#                 CodSKU = C.CodSKU,
#                 Detalhe = C.CdLot,
#                 Descricao = ISNULL(Obj.NmObj, 'Produto não identificado'),
#                 QtSaldoFinal = ISNULL(B.QtSaldoFinal, 0) + ISNULL(MI.QtSaldoFinal, 0),
#                 QtCaixaP = CASE
#                     WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaP, 0)
#                     ELSE ISNULL(EM.QtCaixaP, 0)
#                 END,
#                 QtCaixaG = CASE
#                     WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaG, 0)
#                     ELSE ISNULL(EM.QtCaixaG, 0)
#                 END,
#                 QtEnfestado = CASE
#                     WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfestado, 0)
#                     ELSE ISNULL(EM.QtEnfestado, 0)
#                 END,
#                 QtEnfraldado = CASE
#                     WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfraldado, 0)
#                     ELSE ISNULL(EM.QtEnfraldado, 0)
#                 END
#             FROM Chaves C
#             LEFT JOIN BaseItens B
#                 ON B.CodSKU = C.CodSKU
#                AND B.CdLot = C.CdLot
#             LEFT JOIN MovItens MI
#                 ON MI.CodSKU = C.CodSKU
#                AND MI.CdLot = C.CdLot
#             LEFT JOIN EmbAtual EA
#                 ON EA.CodSKU = C.CodSKU
#                AND EA.CdLot = C.CdLot
#             LEFT JOIN EmbMov EM
#                 ON EM.CodSKU = C.CodSKU
#                AND EM.CdLot = C.CdLot
#             LEFT JOIN dbo.TbObj Obj WITH (NOLOCK)
#                 ON Obj.CdObj = C.CodSKU
#             WHERE
#                 (ISNULL(B.QtSaldoFinal, 0) + ISNULL(MI.QtSaldoFinal, 0)) > 0
#                 OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaP, 0) ELSE ISNULL(EM.QtCaixaP, 0) END > 0
#                 OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaG, 0) ELSE ISNULL(EM.QtCaixaG, 0) END > 0
#                 OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfestado, 0) ELSE ISNULL(EM.QtEnfestado, 0) END > 0
#                 OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfraldado, 0) ELSE ISNULL(EM.QtEnfraldado, 0) END > 0
#             ORDER BY Descricao, C.CdLot
#         """

#         cursor.execute(sql, (
#             endereco,
#             endereco,
#             endereco,
#             endereco, endereco, endereco,
#             endereco, endereco, endereco,
#             endereco, endereco, endereco,
#             endereco, endereco, endereco,
#             endereco, endereco,
#             endereco,
#         ))

#         colunas = [col[0] for col in cursor.description]
#         resultados = [dict(zip(colunas, row)) for row in cursor.fetchall()]
#         return jsonify(resultados), 200

#     except Exception as e:
#         return jsonify({"error": str(e)}), 500
#     finally:
#         if connection:
#             connection.close()

# # Padrão de Caixas
# def _normalizar_texto(valor):
#     texto = (valor or '').strip()
#     if not texto:
#         return ''
#     texto = unicodedata.normalize('NFKD', texto)
#     texto = ''.join(ch for ch in texto if not unicodedata.combining(ch))
#     return ' '.join(texto.split()).strip()


# def _extrair_artigo_base(artigo):
#     texto = _normalizar_texto(artigo)
#     if not texto:
#         return ''

#     match = re.search(r'^(.+?\bmm)\b', texto, flags=re.IGNORECASE)
#     if match:
#         return match.group(1).strip()

#     return texto.strip()


# def _obter_token_node_api():
#     urls_login = [
#         'https://api.stiktech.com.br/auth/login',
#     ]

#     payload = {
#         'username': 'anderson',
#         'password': '142046',
#     }

#     for url in urls_login:
#         try:
#             resp = requests.post(
#                 url,
#                 json=payload,
#                 timeout=15,
#                 headers={'Content-Type': 'application/json'}
#             )
#             if resp.status_code != 200:
#                 continue

#             body = resp.json() or {}
#             token = body.get('accessToken') or body.get('token')
#             if token:
#                 return token
#         except Exception:
#             continue

#     return None


# def _resolver_artigo_oficial_por_sku(cod_sku):
#     token = _obter_token_node_api()
#     if not token:
#         return None

#     urls_artigos = [
#         'https://api.stiktech.com.br/api/artigos',
#     ]

#     for url in urls_artigos:
#         try:
#             resp = requests.get(
#                 url,
#                 params={'CdObj': cod_sku},
#                 timeout=15,
#                 headers={
#                     'Content-Type': 'application/json',
#                     'Authorization': f'Bearer {token}',
#                 }
#             )
#             if resp.status_code != 200:
#                 continue

#             payload = resp.json() or {}
#             rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

#             if not isinstance(rows, list) or not rows:
#                 continue

#             for row in rows:
#                 if not isinstance(row, dict):
#                     continue

#                 artigo = str(
#                     row.get('artigo')
#                     or row.get('Artigo')
#                     or row.get('ARTIGO')
#                     or row.get('Objeto')
#                     or row.get('objeto')
#                     or row.get('NmArtigo')
#                     or ''
#                 ).strip()

#                 if artigo:
#                     return artigo
#         except Exception:
#             continue

#     return None


# def _buscar_padrao_embalagem_por_artigo(artigo):
#     urls_padrao = [
#         'https://api.stiktech.com.br/consulta/wms/stik_padrao_caixa',
#         'http://168.190.90.2:3000/consulta/wms/stik_padrao_caixa',
#     ]

#     artigo_normalizado = _normalizar_texto(artigo).lower()

#     for url in urls_padrao:
#         try:
#             resp = requests.get(url, timeout=15)
#             if resp.status_code != 200:
#                 continue

#             payload = resp.json() or {}
#             rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

#             if not isinstance(rows, list) or not rows:
#                 continue

#             for row in rows:
#                 if not isinstance(row, dict):
#                     continue

#                 artigo_row = str(
#                     row.get('artigo')
#                     or row.get('Artigo')
#                     or row.get('ARTIGO')
#                     or row.get('Objeto')
#                     or row.get('objeto')
#                     or row.get('NmArtigo')
#                     or ''
#                 ).strip()

#                 if not artigo_row:
#                     continue

#                 artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
#                 if artigo_row_normalizado == artigo_normalizado:
#                     return row

#             for row in rows:
#                 if not isinstance(row, dict):
#                     continue

#                 artigo_row = str(
#                     row.get('artigo')
#                     or row.get('Artigo')
#                     or row.get('ARTIGO')
#                     or row.get('Objeto')
#                     or row.get('objeto')
#                     or row.get('NmArtigo')
#                     or ''
#                 ).strip()

#                 if not artigo_row:
#                     continue

#                 artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
#                 if artigo_normalizado in artigo_row_normalizado:
#                     return row
#         except Exception:
#             continue

#     return None

# @wms_bp.route('/consulta/wms/palete/ajustar_embalagem', methods=['POST'])
# def ajustar_embalagem_palete():
#     connection = None
#     try:
#         data = request.get_json() or {}

#         endereco = (data.get('endereco') or '').strip().upper()
#         cod_sku = data.get('cod_sku')
#         detalhe = data.get('detalhe', 0)
#         artigo = (data.get('artigo') or '').strip()
#         cd_usr = data.get('cd_usr')

#         qt_caixa_p = data.get('qt_caixa_p', 0)
#         qt_caixa_g = data.get('qt_caixa_g', 0)
#         qt_enfestado = data.get('qt_enfestado', 0)
#         qt_enfraldado = data.get('qt_enfraldado', 0)

#         if not endereco or cod_sku is None:
#             return jsonify({
#                 "error": "Campos obrigatórios: endereco, cod_sku"
#             }), 400

#         try:
#             cod_sku = int(cod_sku)
#             detalhe = int(detalhe or 0)
#             cd_usr = int(cd_usr) if cd_usr not in (None, '', '0', 0) else None
#             qt_caixa_p = int(qt_caixa_p or 0)
#             qt_caixa_g = int(qt_caixa_g or 0)
#             qt_enfestado = int(qt_enfestado or 0)
#             qt_enfraldado = int(qt_enfraldado or 0)
#         except (TypeError, ValueError):
#             return jsonify({"error": "Parâmetros inválidos"}), 400

#         if min(qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado) < 0:
#             return jsonify({"error": "Quantidades de embalagem não podem ser negativas"}), 400

#         connection = create_connection_tinturaria()
#         if connection is None:
#             return jsonify({
#                 "status": "SQL_ERROR",
#                 "details": "Falha ao conectar ao banco."
#             }), 500

#         cursor = connection.cursor()
#         cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

#         sql_item = """
#             WITH Base AS (
#                 SELECT
#                     Endereco = UPPER(LTRIM(RTRIM(A.Endereco))),
#                     A.CodSKU,
#                     CdLot = ISNULL(A.Detalhe, 0),
#                     QtSaldoInicial = ISNULL(A.QtAlocada, 0),
#                     QtMaxima = ISNULL(A.QtMaxima, 0),
#                     A.DataAtualizacao
#                 FROM dbo.Stik_WMS_Alocacao A WITH (NOLOCK)
#                 WHERE UPPER(LTRIM(RTRIM(A.Endereco))) = ?
#                   AND A.CodSKU = ?
#                   AND ISNULL(A.Detalhe, 0) = ISNULL(?, 0)
#             ),
#             Mov AS (
#                 SELECT
#                     Endereco = UPPER(LTRIM(RTRIM(M.Endereco))),
#                     M.CodSKU,
#                     CdLot = ISNULL(M.Detalhe, 0),
#                     QtMovEntrada = SUM(CASE WHEN M.TpMov = 1 THEN ISNULL(M.QtMovida, 0) ELSE 0 END),
#                     QtMovSaida = SUM(CASE WHEN M.TpMov = 2 THEN ISNULL(M.QtMovida, 0) ELSE 0 END),
#                     QtMovRetorno = SUM(CASE WHEN M.TpMov = 3 THEN ISNULL(M.QtMovida, 0) ELSE 0 END)
#                 FROM dbo.Stik_WMS_Movimento M WITH (NOLOCK)
#                 WHERE UPPER(LTRIM(RTRIM(M.Endereco))) = ?
#                   AND M.CodSKU = ?
#                   AND ISNULL(M.Detalhe, 0) = ISNULL(?, 0)
#                 GROUP BY
#                     UPPER(LTRIM(RTRIM(M.Endereco))),
#                     M.CodSKU,
#                     ISNULL(M.Detalhe, 0)
#             ),
#             EmbAtual AS (
#                 SELECT
#                     Endereco = UPPER(LTRIM(RTRIM(E.Endereco))),
#                     E.CodSKU,
#                     CdLot = ISNULL(E.Detalhe, 0),
#                     QtCaixaP = ISNULL(E.QtCaixaP, 0),
#                     QtCaixaG = ISNULL(E.QtCaixaG, 0),
#                     QtEnfestado = ISNULL(E.QtEnfestado, 0),
#                     QtEnfraldado = ISNULL(E.QtEnfraldado, 0)
#                 FROM dbo.Stik_WMS_Alocacao_Embalagem E WITH (NOLOCK)
#                 WHERE UPPER(LTRIM(RTRIM(E.Endereco))) = ?
#                   AND E.CodSKU = ?
#                   AND ISNULL(E.Detalhe, 0) = ISNULL(?, 0)
#             ),
#             EmbMov AS (
#                 SELECT
#                     CodSKU = M.CodSKU,
#                     CdLot = ISNULL(M.Detalhe, 0),
#                     QtCaixaP = SUM(
#                         CASE
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaP, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaP, 0)
#                             ELSE 0
#                         END
#                     ),
#                     QtCaixaG = SUM(
#                         CASE
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaG, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaG, 0)
#                             ELSE 0
#                         END
#                     ),
#                     QtEnfestado = SUM(
#                         CASE
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtEnfestado, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtEnfestado, 0)
#                             ELSE 0
#                         END
#                     ),
#                     QtEnfraldado = SUM(
#                         CASE
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtEnfraldado, 0)
#                             WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtEnfraldado, 0)
#                             ELSE 0
#                         END
#                     )
#                 FROM dbo.Stik_WMS_Movimento_Embalagem M WITH (NOLOCK)
#                 WHERE (
#                     UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ?
#                     OR UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ?
#                 )
#                   AND M.CodSKU = ?
#                   AND ISNULL(M.Detalhe, 0) = ISNULL(?, 0)
#                 GROUP BY
#                     M.CodSKU,
#                     ISNULL(M.Detalhe, 0)
#             )
#             SELECT TOP 1
#                 QtSaldoFinal =
#                     ISNULL(B.QtSaldoInicial, 0)
#                     + ISNULL(M.QtMovEntrada, 0)
#                     + ISNULL(M.QtMovRetorno, 0)
#                     - ISNULL(M.QtMovSaida, 0),
#                 QtCaixaP = CASE
#                     WHEN B.Endereco IS NOT NULL THEN ISNULL(EA.QtCaixaP, 0)
#                     ELSE ISNULL(EM.QtCaixaP, 0)
#                 END,
#                 QtCaixaG = CASE
#                     WHEN B.Endereco IS NOT NULL THEN ISNULL(EA.QtCaixaG, 0)
#                     ELSE ISNULL(EM.QtCaixaG, 0)
#                 END,
#                 QtEnfestado = CASE
#                     WHEN B.Endereco IS NOT NULL THEN ISNULL(EA.QtEnfestado, 0)
#                     ELSE ISNULL(EM.QtEnfestado, 0)
#                 END,
#                 QtEnfraldado = CASE
#                     WHEN B.Endereco IS NOT NULL THEN ISNULL(EA.QtEnfraldado, 0)
#                     ELSE ISNULL(EM.QtEnfraldado, 0)
#                 END
#             FROM Base B
#             FULL OUTER JOIN Mov M
#                 ON M.Endereco = B.Endereco
#                AND M.CodSKU = B.CodSKU
#                AND M.CdLot = B.CdLot
#             FULL OUTER JOIN EmbAtual EA
#                 ON EA.Endereco = COALESCE(B.Endereco, M.Endereco)
#                AND EA.CodSKU = COALESCE(B.CodSKU, M.CodSKU)
#                AND EA.CdLot = COALESCE(B.CdLot, M.CdLot)
#             FULL OUTER JOIN EmbMov EM
#                 ON EM.CodSKU = COALESCE(B.CodSKU, M.CodSKU, EA.CodSKU)
#                AND EM.CdLot = COALESCE(B.CdLot, M.CdLot, EA.CdLot)
#         """

#         cursor.execute(sql_item, (
#             endereco, cod_sku, detalhe,
#             endereco, cod_sku, detalhe,
#             endereco, cod_sku, detalhe,
#             endereco, endereco,
#             endereco, endereco,
#             endereco, endereco,
#             endereco, endereco,
#             endereco, endereco,
#             cod_sku, detalhe,
#         ))
#         row_item = cursor.fetchone()

#         if not row_item:
#             return jsonify({
#                 "error": "Item não encontrado neste palete."
#             }), 404

#         qt_saldo_final = float((row_item[0] or 0))
#         if qt_saldo_final <= 0:
#             return jsonify({
#                 "error": "Item sem saldo disponível neste palete."
#             }), 409

#         saldo_caixa_p = int((row_item[1] or 0))
#         saldo_caixa_g = int((row_item[2] or 0))
#         saldo_enfestado = int((row_item[3] or 0))
#         saldo_enfraldado = int((row_item[4] or 0))

#         cursor.execute("""
#             IF EXISTS (
#                 SELECT 1
#                 FROM dbo.Stik_WMS_Alocacao_Embalagem
#                 WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
#                   AND CodSKU = ?
#                   AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#             )
#             BEGIN
#                 UPDATE dbo.Stik_WMS_Alocacao_Embalagem
#                 SET
#                     QtCaixaP = ?,
#                     QtCaixaG = ?,
#                     QtEnfestado = ?,
#                     QtEnfraldado = ?,
#                     DtAtualizacao = GETDATE()
#                 WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
#                   AND CodSKU = ?
#                   AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
#             END
#             ELSE
#             BEGIN
#                 INSERT INTO dbo.Stik_WMS_Alocacao_Embalagem
#                     (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado, DtAtualizacao)
#                 VALUES
#                     (?, ?, ?, ?, ?, ?, ?, GETDATE())
#             END
#         """, (
#             endereco, cod_sku, detalhe,
#             qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado,
#             endereco, cod_sku, detalhe,
#             endereco, cod_sku, detalhe,
#             qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado
#         ))

#         cursor.execute("""
#             INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
#                 (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
#                  QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
#                  QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
#             VALUES
#                 (?, NULL, ?, ?, 4, ?, ?, ?, ?, ?, ?, 'AJUSTE', 'Ajuste manual de embalagem', GETDATE())
#         """, (
#             endereco,
#             cod_sku,
#             detalhe,
#             qt_caixa_p,
#             qt_caixa_g,
#             qt_enfestado,
#             qt_enfraldado,
#             qt_saldo_final,
#             cd_usr
#         ))

#         connection.commit()

#         return jsonify({
#             "success": True,
#             "message": "Ajuste de embalagem salvo com sucesso.",
#             "endereco": endereco,
#             "cod_sku": cod_sku,
#             "detalhe": detalhe,
#             "artigo": artigo,
#             "qt_saldo_final": qt_saldo_final,
#             "qt_caixa_p": qt_caixa_p,
#             "qt_caixa_g": qt_caixa_g,
#             "qt_enfestado": qt_enfestado,
#             "qt_enfraldado": qt_enfraldado,
#             "saldo_anterior": {
#                 "QtCaixaP": saldo_caixa_p,
#                 "QtCaixaG": saldo_caixa_g,
#                 "QtEnfestado": saldo_enfestado,
#                 "QtEnfraldado": saldo_enfraldado
#             }
#         }), 200

#     except Exception as e:
#         if connection:
#             try:
#                 connection.rollback()
#             except Exception:
#                 pass
#         return jsonify({"error": str(e)}), 500

#     finally:
#         if connection:
#             connection.close()
    
  
import requests
import re
import unicodedata
from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 
import datetime 
from datetime import timedelta

wms_bp = Blueprint('wms', __name__)



# ROTA 1: GET (Para consultar a lista de romaneios)
@wms_bp.route('/consulta/romaneio', methods=['GET'])
def get_romaneio(): 
    """
    Endpoint para consultar dados detalhados de romaneio/expedição.
    Filtra a visibilidade: Admin vê todos, Separador vê não atribuídos 
    ou atribuídos a ele.
    """
    connection = None
    try:
        today = datetime.date.today()
        default_inicio = today.replace(month=1, day=1).strftime('%Y-%m-%d')
        default_fim = today.replace(month=12, day=31).strftime('%Y-%m-%d')

        data_inicio = request.args.get('data_inicio', default_inicio)
        data_fim = request.args.get('data_fim', default_fim)
        # Pega o ID do usuário logado do query parameter
        cd_usr = request.args.get('cd_usr', '0')
        # Garante que cd_usr é um inteiro para o T-SQL
        try:
            cd_usr_int = int(cd_usr)
        except ValueError:
            cd_usr_int = 0

        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON; -- Para evitar o erro 'No results' do pyodbc

            -- Declaração de parâmetros que virão do Python
            DECLARE @DtIni date = ?;
            DECLARE @DtFim date = ?;

            /* ==========================================
                Contexto / Usuário atual
            ========================================== */
            DECLARE @CdUsr int;
            SET @CdUsr = ?; -- Agora recebe o ID do usuário logado

            

            /* ==========================================
                Base de Faturamento do período/condições
            ========================================== */
            IF OBJECT_ID('tempdb..#Stik_Pedido_QtdFat_Base') IS NOT NULL DROP TABLE #Stik_Pedido_QtdFat_Base;

            SELECT Fat.*
            INTO #Stik_Pedido_QtdFat_Base
            FROM dbo.Stik_Pedido_QtdFat AS Fat WITH (NOLOCK) 
            -- 💡 CORREÇÃO 2 do problema anterior: INNER JOIN OBRIGATÓRIO NA TABELA MESTRA 'Stik_Romaneio'
            INNER JOIN dbo.Stik_Romaneio AS Sr WITH (NOLOCK) ON Sr.NrRomaneio = Fat.NrRomaneio
            WHERE (Fat.TpSitFat = 0 OR 0 = 0)
            --WHERE (Fat.TpSitFat = 2)
              AND (CONVERT(date, Fat.DtExp) >= @DtIni) 
              AND (CONVERT(date, Fat.DtExp) <= @DtFim) 
              
              
              -- FILTRO DE VISIBILIDADE REFORÇADO (AQUI ESTÁ A CORREÇÃO LÓGICA)
              AND (
                    -- 1. LÓGICA DE ADMIN: Permite acesso total para admins.
                    @CdUsr = 0
                    OR @CdUsr IN (58, 97, 258, 313, 323, 322, 343, 325, 350, 357, 372, 183, 324, 168, 294, 375, 376, 329, 328, 334 , 400 , 421 , 461 , 226, 325 , 327 , 207 , 334)
                    -- 2. OU LÓGICA DE SEPARADOR: Romaneio não atribuído OU atribuído a ele.
                    OR (
                        Fat.CdUsrSep IS NULL 
                        OR Fat.CdUsrSep = 0
                        OR Fat.CdUsrSep = @CdUsr
                    )
                )
                
              -- 💡 CORREÇÃO 1: Garante que só puxa itens com NrRomaneio > 0 (Romaneados)
              --AND CONVERT(int, ISNULL(Fat.NrRomaneio, 0)) > 0;
              AND CONVERT(int, ISNULL(Fat.NrRomaneio, 0)) > 0
                AND NOT EXISTS (
                    SELECT 1
                    FROM dbo.Stik_WMS_Romaneio_Separado Sep
                    WHERE Sep.NrRomaneio = Fat.NrRomaneio
                );

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
            -- ✅ CORREÇÃO 3: Usar a base de faturamento já filtrada para pegar só separadores de romaneios válidos e visíveis
            FROM #Stik_Pedido_QtdFat_Base AS Fat 
            JOIN dbo.TbVpo AS Vpo WITH (NOLOCK) ON Vpo.CdVpo = Fat.CdVpo 
            JOIN dbo.TbVpd AS Vpd WITH (NOLOCK) ON Vpd.CdVpd = Vpo.CdVpd 
            -- Não precisa mais do JOIN com Stik_Romaneio aqui, pois já foi feito na criação da #Stik_Pedido_QtdFat_Base
            LEFT JOIN dbo.TbUsr AS Usr WITH (NOLOCK) ON Usr.CdUsr = Fat.CdUsrSep; 

            /* ==========================================
                SELECT ÚNICO
            ========================================== */
            SELECT
                ID					= Fat.ID,
                NrRomaneio          = Fat.NrRomaneio,
                CdVpo               = Vpo.CdVpo,
                CdVpd               = Vpd.CdVpd,
                Data               = CONVERT(varchar, Fat.DtExp, 103) + ' ' + LEFT(CONVERT(varchar, Fat.DtExp, 108), 5),
                HrMovimento         =
                    SUBSTRING(CONVERT(varchar, CONVERT(date, Fat.DtIniExpSep), 103), 1, 2) + '/' +
                    SUBSTRING(CONVERT(varchar, CONVERT(date, Fat.DtIniExpSep), 103), 4, 2) + '/' +
                    SUBSTRING(CONVERT(varchar, CONVERT(date, Fat.DtIniExpSep), 103), 7, 4) + ' ' +
                    SUBSTRING(CONVERT(varchar, CONVERT(time, Fat.DtIniExpSep), 108), 1, 5),
                Descricao           = 'Romaneio :' + CONVERT(varchar, Fat.NrRomaneio) + ' Ped.:' + CONVERT(varchar, Vpd.CdVpd),
                CdObj               = Obj.CdObj,
                Objeto              = Obj.NmObj,
                DetalheID           = LotAtv.CdLot,
                Detalhe             = LotAtv.NmLot,
                QtPed               = Vpo.QtVpo,
                Qt                  = Fat.QtFat,
                QtReservado         = ISNULL(PedRes.Qt, 0) + ISNULL(Vpo.QtVpoFatCan, 0) - ISNULL(FatDoc.Qt, 0),
                Atendido            = Fat.QtFatAtend,
                QtRes               = LetReserva.Qt, 
                SaldoDoArtigo       = Vpo.QtVpo + ISNULL(Vpo.QtVpoFatCan, 0) - ISNULL(Vpo.QtVpoFat, 0),
                Nfe                 = Ffm.NrFfm,
                NrDC                = RcdDc.NrRcd,
                CdFat               = FatNfe.CdFat,
                CdRcd               = Rcd.CdRcd,
                Situacao            = ColFat.Descricao,
                PrazoPagto          = Fpg.NmFpg,
                FormaPagto          = Tcb.NmTcb,
                SitFinan            = ColFin.Descricao,
                Observacao          = Obs.TtObs,
                ObservacaoID        = ISNULL(Obs.CdObs, 0),
                Motivo              = CASE
                                            WHEN Fat.TpMotivoCan = 1 THEN 'Artigo sem estoque'
                                            WHEN Fat.TpMotivoCan = 2 THEN 'Artigo não encontrado'
                                            WHEN Fat.TpMotivoCan = 3 THEN 'Solicitação do Comercial'
                                            ELSE ''
                                        END,
                Solicitante         = S.Solicitante,
                Separador           = UsrSep.NmUsr,
                IDSeparador         = ISNULL(Fat.CdUsrSep, 0), -- Garante 0 se for NULL
                UsrLogado           = (SELECT @CdUsr),
                Cliente             = Cli.NmCli,
                Transportadora      = COALESCE(NULLIF(LTRIM(RTRIM(Frn.NmFrn)), ''), 'SEM TRANSPORTADORA')

            FROM #Stik_Pedido_QtdFat_Base AS Fat
            -- O INNER JOIN com Sr já foi feito na criação da #Stik_Pedido_QtdFat_Base. Ele ainda está aqui, mas é redundante agora:
            INNER JOIN dbo.Stik_Romaneio AS Sr WITH (NOLOCK) ON Sr.NrRomaneio = Fat.NrRomaneio
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

            --Transporte
            left join TbFrn Frn on Frn.CdFrn = Vpd.CdFrnTrp

            --Prazo e Forma de Pagamento
            left join TbFpg Fpg on Fpg.CdFpg = Vpd.CdFpg
            left join TbTcb Tcb ON Tcb.CdTcb = Vpd.CdTcb

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
                            AND ArvObj.CdObj     = 0
                        ))
              AND (CONVERT(int, ISNULL(Rcd.FolhaDeFormularioID_Nfe, 0)) = 0 OR 0 = 0)
              

            /* Ordenação para API */
            ORDER BY
                Fat.NrRomaneio,
                Vpd.CdVpd,
                Vpo.CdVpo,
                Obj.CdObj;
        """
        
        # Executa a consulta T-SQL passando as datas e o ID do usuário como parâmetros
        cursor.execute(sql_query, (data_inicio, data_fim, cd_usr_int))


        # Converte o resultado em uma lista de dicionários
        registros = [dict(zip([column[0] for column in cursor.description], row)) for row in cursor.fetchall()]

        romaneio_debug = 124804
        registros_debug = [r for r in registros if int(r.get('NrRomaneio', 0) or 0) == romaneio_debug]
        print(f"DEBUG get_romaneio {romaneio_debug}: {len(registros_debug)} registros")
        for r in registros_debug[:5]:
            print("DEBUG item", r.get('NrRomaneio'), r.get('CdVpo'), r.get('Situacao'), r.get('IDSeparador'))

        
        print(f"✅ [{cd_usr_int}] Romaneios consultados: {len(registros)} registros")

        return jsonify(registros)

    except Exception as e:
        print(f"❌ Erro ao consultar faturamento detalhado: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()
            print("🔌 Conexão com o banco de dados fechada.")

# ===================================================================
# ROTA 2: PUT (Para associar um separador a um romaneio)
# ===================================================================
@wms_bp.route('/consulta/romaneio/associar', methods=['PUT'])
def associar_separador():
    """
    Endpoint para associar/reatribuir um separador a um NrRomaneio ESPECÍFICO.
    Atualiza o status para 'Em Separação' (TpSitFat = 3).
    """
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        nr_romaneio = data.get('NrRomaneio')
        id_separador = data.get('IDSeparador')
        
        # Novo campo para forçar a reatribuição (pode ser útil para administradores)
        forcar_reatribuicao = data.get('ForcarReatribuicao', False) 

        if not nr_romaneio or id_separador is None:
            return jsonify({"error": "Campos 'NrRomaneio' e 'IDSeparador' são obrigatórios"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        # A lógica de UPDATE na rota PUT está correta: atualiza CdUsrSep, e se o status for 2 (Pronto)
        # o muda para 3 (Em Separação), registrando a data de início se ainda não tiver.
        sql_update = f"""
            SET NOCOUNT ON;
            UPDATE dbo.Stik_Pedido_QtdFat
            SET 
                CdUsrSep = ?,
                -- Atualiza o status para 3 (Em Separação) se o status ATUAL for 2 (Pronto)
                TpSitFat = CASE WHEN ? > 0 AND TpSitFat = 2 THEN 3 ELSE TpSitFat END,
                -- Registra a data de início (apenas se for o primeiro registro)
                DtIniExpSep = CASE WHEN DtIniExpSep IS NULL THEN GETDATE() ELSE DtIniExpSep END 
            WHERE 
                NrRomaneio = ?
                -- Lógica de prevenção de reatribuição:
                AND (
                    -- A reatribuição só é permitida se:
                    -- 1. O romaneio não tem separador (NULL ou 0)
                    CdUsrSep IS NULL 
                    OR CdUsrSep = 0
                    -- 2. OU o usuário forçadamente desatribuiu (IDSeparador = 0)
                    OR ? = 0
                    -- 3. OU a forçar_reatribuicao for True (para admins)
                    OR ? = 1
                );
        """

        # Parâmetros: (id_separador, id_separador, nr_romaneio, id_separador, forcar_reatribuicao)
        cursor.execute(sql_update, (id_separador, id_separador, nr_romaneio, id_separador, 1 if forcar_reatribuicao else 0))
        
        if cursor.rowcount == 0:
            connection.rollback()
            
            # Se for uma tentativa de atribuição (ID > 0) e não houver linhas afetadas, 
            # é porque ele já estava atribuído e não foi forçado.
            if int(id_separador) > 0 and not forcar_reatribuicao:
                # O romaneio está atribuído, e o usuário não forçou a reatribuição.
                return jsonify({"error": f"O Romaneio {nr_romaneio} já está atribuído. Desassocie ou use Forçar Reatribuição (Admin)."}), 409
            
            # Caso contrário, nenhum registro encontrado.
            return jsonify({"error": f"Nenhum registro disponível encontrado para o Romaneio {nr_romaneio}."}), 404

        connection.commit()

        print(f"✅ Romaneio {nr_romaneio} → Separador {id_separador} (Linhas: {cursor.rowcount})")
        
        return jsonify({
            "success": True,
            "message": f"Romaneio {nr_romaneio} associado com sucesso. Status atualizado para Em Separação.",
            "romaneio": nr_romaneio,
            "separador_id": id_separador,
            "linhas_afetadas": cursor.rowcount
        }), 200

    except Exception as e:
        if connection:
            connection.rollback()
        print(f"❌ Erro ao associar: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

# ===================================================================
# ROTA 3: POST (Para selecionar e bloquear o próximo romaneio disponível)
# Implementa a lógica de SELECT TOP(1) e UPDATE (TpSitFat = 3)
# ===================================================================
@wms_bp.route('/consulta/romaneio/proximo', methods=['POST'])
def selecionar_proximo_romaneio():
    """
    1. Seleciona o romaneio mais antigo (Min(DtExp)) com TpSitFat = 2 (Pronto para Separação).
    2. Bloqueia o romaneio (atualiza TpSitFat = 3) e atribui o separador (CdUsrSep).
    3. Retorna o NrRomaneio selecionado.
    """
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        # O endpoint espera receber o ID do Separador que está pedindo o próximo romaneio
        id_separador = data.get('IDSeparador')

        if id_separador is None:
            return jsonify({"error": "Campo 'IDSeparador' é obrigatório"}), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        
        # O SQL abaixo executa a lógica de seleção e atualização de forma ATÔMICA,
        # prevenindo que dois separadores peguem o mesmo romaneio.
        sql_select_and_update = f"""
            SET NOCOUNT ON;
            
            -- Variável para armazenar o romaneio que será selecionado
            DECLARE @NrRomaneio INT;

            -- 1. Seleciona o Romaneio mais antigo (Menor DtExp) em TpSitFat = 2 (Pronto para Separação)
            -- e atribui o NrRomaneio à variável @NrRomaneio.
            -- O uso de (UPDLOCK, HOLDLOCK) é CRUCIAL para bloquear a linha imediatamente 
            -- e evitar que outro usuário a selecione ao mesmo tempo.
            SELECT TOP(1)
                @NrRomaneio = Fat.NrRomaneio
            FROM dbo.Stik_Pedido_QtdFat Fat WITH (UPDLOCK, HOLDLOCK)
            WHERE
                Fat.TpSitFat = 2  -- Status: Pronto para Separação
                AND (Fat.CdUsrSep IS NULL OR Fat.CdUsrSep = 0) -- Não atribuído
                AND CONVERT(int, ISNULL(Fat.NrRomaneio, 0)) > 0 -- Garante que é um romaneio válido
            GROUP BY
                Fat.NrRomaneio
            ORDER BY
                MIN(Fat.DtExp) ASC; -- Seleciona o mais antigo
                
            -- Se @NrRomaneio for NULL, nenhum romaneio disponível foi encontrado.
            IF @NrRomaneio IS NULL
            BEGIN
                SELECT 'NAO_ENCONTRADO' AS Status, NULL AS NrRomaneio;
                RETURN;
            END
            
            -- 2. Atualiza todos os itens desse Romaneio para TpSitFat = 3 (Em Separação)
            -- e atribui o separador.
            UPDATE dbo.Stik_Pedido_QtdFat
            SET
                TpSitFat = 3,      -- NOVO STATUS: Em Separação
                DtIniExpSep = GETDATE(),
                CdUsrSep = ?
            WHERE
                NrRomaneio = @NrRomaneio
                AND TpSitFat = 2; -- Confirma a transição de 2 para 3 (cobertura dupla)
                
            -- Retorna o Romaneio selecionado
            SELECT 'OK' AS Status, @NrRomaneio AS NrRomaneio;
        """

        # Executa o SQL, passando o ID do separador como parâmetro para o UPDATE
        cursor.execute(sql_select_and_update, (id_separador,))
        
        # Pega a linha de retorno (Status e NrRomaneio)
        result = cursor.fetchone()
        
        if not result or result[0] == 'NAO_ENCONTRADO':
            connection.rollback()
            return jsonify({
                "success": False,
                "message": "Nenhum romaneio disponível para separação (Status 2)."
            }), 200

        nr_romaneio = result[1]
        connection.commit()

        print(f"✅ Próximo Romaneio selecionado: {nr_romaneio} → Separador {id_separador}")
        
        return jsonify({
            "success": True,
            "message": f"Romaneio {nr_romaneio} atribuído e bloqueado com sucesso",
            "romaneio": nr_romaneio,
            "separador_id": id_separador
        }), 200

    except Exception as e:
        if connection:
            connection.rollback()
        print(f"❌ Erro ao selecionar próximo romaneio: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()

@wms_bp.route('/consulta/romaneio/cancelar_com_devolucao', methods=['POST'])
def cancelar_romaneio_com_devolucao():
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        nr_romaneio = data.get('NrRomaneio')
        motivo = data.get('Motivo')
        solicitante = data.get('Solicitante')

        if not all([nr_romaneio, motivo, solicitante]):
            return jsonify({
                "error": "Campos 'NrRomaneio', 'Motivo' e 'Solicitante' são obrigatórios."
            }), 400

        connection = create_connection_tinturaria()
        connection.autocommit = False
        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        itens_query = """
            SELECT
                Fat.CdObj,
                LotAtv.CdLot AS DetalheID,
                Fat.QtFat AS Qt
            FROM dbo.Stik_Pedido_QtdFat Fat
            LEFT JOIN dbo.TbVpo Vpo ON Vpo.CdVpo = Fat.CdVpo
            LEFT JOIN dbo.TbLot LotAtv ON LotAtv.CdLot = Vpo.CdLot
            WHERE Fat.NrRomaneio = ?
        """
        cursor.execute(itens_query, (nr_romaneio,))
        itens = cursor.fetchall()
        if not itens:
            return jsonify({"error": "Itens do romaneio não encontrados."}), 404

        for cdobj, detalhe_id, qt in itens:
            if not cdobj or not qt or qt <= 0:
                continue

            # 1) Palete do SKU + Detalhe
            palete_query = """
                SELECT TOP 1 Endereco
                FROM dbo.Stik_WMS_Alocacao
                WHERE CodSKU = ?
                  AND Detalhe = ?
                  AND (
                        QtMaxima IS NULL
                        OR (ISNULL(QtMaxima, 0) - ISNULL(QtAlocada, 0)) >= ?
                      )
                ORDER BY (ISNULL(QtMaxima, 999999999) - ISNULL(QtAlocada, 0)) DESC,
                         DataAtualizacao DESC
            """
            cursor.execute(palete_query, (cdobj, detalhe_id, qt))
            row = cursor.fetchone()

            # 2) Palete do SKU (qualquer Detalhe)
            if not row:
                palete_fallback = """
                    SELECT TOP 1 Endereco
                    FROM dbo.Stik_WMS_Alocacao
                    WHERE CodSKU = ?
                      AND (
                            QtMaxima IS NULL
                            OR (ISNULL(QtMaxima, 0) - ISNULL(QtAlocada, 0)) >= ?
                          )
                    ORDER BY (ISNULL(QtMaxima, 999999999) - ISNULL(QtAlocada, 0)) DESC,
                             DataAtualizacao DESC
                """
                cursor.execute(palete_fallback, (cdobj, qt))
                row = cursor.fetchone()

            # 3) Qualquer palete com capacidade
            if not row:
                palete_any = """
                    SELECT TOP 1 Endereco
                    FROM dbo.Stik_WMS_Alocacao
                    WHERE (
                        QtMaxima IS NULL
                        OR (ISNULL(QtMaxima, 0) - ISNULL(QtAlocada, 0)) >= ?
                    )
                    ORDER BY (ISNULL(QtMaxima, 999999999) - ISNULL(QtAlocada, 0)) DESC,
                             DataAtualizacao DESC
                """
                cursor.execute(palete_any, (qt,))
                row = cursor.fetchone()

            if not row:
                return jsonify({
                    "error": f"Sem palete com capacidade para SKU {cdobj} (det {detalhe_id}) para devolver {qt}"
                }), 400

            endereco = row[0]

            mov_query = """
                INSERT INTO dbo.stik_WMS_Movimento
                    (Endereco, CodSKU, TpMov, QtMovida, Detalhe, DataMovimento)
                VALUES
                    (?, ?, 1, ?, ?, SYSDATETIME());
            """
            cursor.execute(mov_query, (endereco, cdobj, qt, detalhe_id))

        # Devolve as embalagens pela mesma chave operacional usada na
        # separação/transferência: CdObj + Detalhe + TipoCaixa. O cancelamento
        # não depende de LI nem de CX. A quantidade é derivada dos metros
        # confirmados divididos pelos metros de cada caixa; no exemplo de
        # 9.000m / 3.000m por caixa, devolve 3 caixas G mesmo com uma leitura.
        cursor.execute("""
            IF OBJECT_ID('tempdb..#EmbalagensCancelamento') IS NOT NULL
                DROP TABLE #EmbalagensCancelamento;

            SELECT
                Endereco = UPPER(LTRIM(RTRIM(COALESCE(NULLIF(E.EnderecoLido, ''), E.Endereco)))),
                I.CdObj,
                Detalhe = ISNULL(I.Detalhe, 0),
                TipoCaixa = UPPER(LTRIM(RTRIM(E.TipoCaixa))),
                Quantidade = SUM(
                    CASE
                        WHEN ISNULL(E.MtsPorCaixa, 0) > 0
                         AND ISNULL(E.MtsConfirmados, 0) > 0
                            THEN CEILING(E.MtsConfirmados / E.MtsPorCaixa)
                        ELSE ISNULL(E.QtCaixasConfirmada, 0)
                    END
                )
            INTO #EmbalagensCancelamento
            FROM dbo.Stik_WMS_SeparacaoPlanejada_Execucao E WITH (UPDLOCK, HOLDLOCK)
            INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada_Item I WITH (UPDLOCK, HOLDLOCK)
                ON I.IdPlanoItem = E.IdPlanoItem
            INNER JOIN dbo.Stik_WMS_SeparacaoPlanejada P WITH (UPDLOCK, HOLDLOCK)
                ON P.IdPlano = I.IdPlano
            WHERE P.NrRomaneio = ?
              AND ISNULL(E.Confirmado, 0) = 1
              AND UPPER(LTRIM(RTRIM(E.TipoCaixa))) IN ('P', 'G')
            GROUP BY
                UPPER(LTRIM(RTRIM(COALESCE(NULLIF(E.EnderecoLido, ''), E.Endereco)))),
                I.CdObj, ISNULL(I.Detalhe, 0),
                UPPER(LTRIM(RTRIM(E.TipoCaixa)));
        """, (nr_romaneio,))

        cursor.execute("SELECT ISNULL(SUM(Quantidade), 0) FROM #EmbalagensCancelamento")
        caixas_row = cursor.fetchone()
        caixas_devolvidas = int(caixas_row[0] or 0) if caixas_row else 0

        if caixas_devolvidas > 0:
            cursor.execute("""
                MERGE dbo.Stik_WMS_Alocacao_Embalagem WITH (HOLDLOCK) AS A
                USING (
                    SELECT Endereco, CdObj, Detalhe,
                           QtCaixaP = SUM(CASE WHEN TipoCaixa = 'P' THEN Quantidade ELSE 0 END),
                           QtCaixaG = SUM(CASE WHEN TipoCaixa = 'G' THEN Quantidade ELSE 0 END)
                    FROM #EmbalagensCancelamento
                    GROUP BY Endereco, CdObj, Detalhe
                ) AS D
                  ON UPPER(LTRIM(RTRIM(A.Endereco))) = D.Endereco
                 AND A.CodSKU = D.CdObj
                 AND ISNULL(A.Detalhe, 0) = D.Detalhe
                WHEN MATCHED THEN
                    UPDATE SET QtCaixaP = ISNULL(A.QtCaixaP, 0) + D.QtCaixaP,
                               QtCaixaG = ISNULL(A.QtCaixaG, 0) + D.QtCaixaG,
                               DtAtualizacao = GETDATE()
                WHEN NOT MATCHED THEN
                    INSERT (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG,
                            QtEnfestado, QtEnfraldado, DtAtualizacao)
                    VALUES (D.Endereco, D.CdObj, D.Detalhe, D.QtCaixaP,
                            D.QtCaixaG, 0, 0, GETDATE());
            """)

            # Se houver caixas físicas consumidas, libera até a quantidade
            # calculada para o mesmo CdObj+Detalhe+Tipo+Endereço. A contagem
            # da embalagem não depende da existência dessas linhas.
            cursor.execute("""
                DECLARE @Endereco varchar(100), @CdObj int, @Detalhe int,
                        @TipoCaixa varchar(10), @Quantidade int;

                DECLARE caixas_cursor CURSOR LOCAL FAST_FORWARD FOR
                    SELECT Endereco, CdObj, Detalhe, TipoCaixa, Quantidade
                    FROM #EmbalagensCancelamento;

                OPEN caixas_cursor;
                FETCH NEXT FROM caixas_cursor
                    INTO @Endereco, @CdObj, @Detalhe, @TipoCaixa, @Quantidade;

                WHILE @@FETCH_STATUS = 0
                BEGIN
                    ;WITH C AS (
                        SELECT TOP (@Quantidade) *
                        FROM dbo.Stik_WMS_Caixa WITH (UPDLOCK, READPAST)
                        WHERE Status = 'CONSUMIDA'
                          AND UPPER(LTRIM(RTRIM(Endereco))) = @Endereco
                          AND CdObj = @CdObj
                          AND ISNULL(Detalhe, 0) = @Detalhe
                          AND UPPER(LTRIM(RTRIM(TipoCaixa))) = @TipoCaixa
                        ORDER BY DataConsumo DESC
                    )
                    UPDATE C
                    SET Status = 'DISPONIVEL', IdExecucao = NULL,
                        DataConsumo = NULL;

                    FETCH NEXT FROM caixas_cursor
                        INTO @Endereco, @CdObj, @Detalhe, @TipoCaixa, @Quantidade;
                END

                CLOSE caixas_cursor;
                DEALLOCATE caixas_cursor;
            """)

            cursor.execute("""
                INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
                    (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
                     QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
                     QtMovidaMetro, Origem, Observacao, DataMovimento)
                SELECT NULL, D.Endereco, D.CdObj, D.Detalhe, 1,
                       SUM(CASE WHEN D.TipoCaixa = 'P' THEN D.Quantidade ELSE 0 END),
                       SUM(CASE WHEN D.TipoCaixa = 'G' THEN D.Quantidade ELSE 0 END),
                       0, 0, 0, 'CANCELAMENTO_ROMANEIO',
                       CONCAT('Devolução de caixas do romaneio ', ?), GETDATE()
                FROM #EmbalagensCancelamento D
                GROUP BY D.Endereco, D.CdObj, D.Detalhe;
            """, (nr_romaneio,))

        update_query = """
            UPDATE Stik_Pedido_QtdFat
            SET TpSitFat = 11,
                TpMotivoCan = ?
            WHERE NrRomaneio = ?;
        """
        cursor.execute(update_query, (motivo, nr_romaneio))
        if cursor.rowcount == 0:
            return jsonify({"error": "Romaneio não encontrado."}), 404

        insert_query = """
            INSERT INTO Stik_Solicitante_Canc (DtCancelamento, Solicitante, CdVpo, NrRomaneio)
            SELECT SYSDATETIME(), ?, CdVpo, NrRomaneio
            FROM Stik_Pedido_QtdFat
            WHERE NrRomaneio = ?;
        """
        cursor.execute(insert_query, (solicitante, nr_romaneio))

        connection.commit()
        return jsonify({
            "message": "Cancelamento com devolução realizado.",
            "caixas_devolvidas": caixas_devolvidas
        }), 200

    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()

@wms_bp.route('/consulta/romaneio/lista_conferencia', methods=['GET'])
def get_lista_conferencia():
    connection = None
    try:
        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;

            SELECT
                Sep.NrRomaneio,
                Sep.CdVpo,
                Vpd.CdVpd,
                Sep.CdObj,
                Sep.CdLot,
                Cli.NmCli AS Cliente,
                Obj.NmObj AS Objeto,
                Lot.NmLot AS Detalhe,
                Fat.ID,
                Fat.DtExp AS DataExpedicao,
                Sep.DtSeparacao AS DataConclusaoSep,
                Usr.NmUsr AS Separador,
                COUNT(*) OVER (PARTITION BY Sep.NrRomaneio) AS TotalItens,
                Fat.QtFat AS Qt,
                Sep.QtSeparada AS QtSeparada
            FROM dbo.Stik_WMS_Romaneio_Separado Sep WITH (NOLOCK)
            JOIN dbo.TbVpo Vpo WITH (NOLOCK)
                ON Vpo.CdVpo = Sep.CdVpo
            JOIN dbo.TbVpd Vpd WITH (NOLOCK)
                ON Vpd.CdVpd = Vpo.CdVpd
            LEFT JOIN dbo.TbCli Cli WITH (NOLOCK)
                ON Cli.CdCli = Vpd.CdCli
            LEFT JOIN dbo.TbUsr Usr WITH (NOLOCK)
                ON Usr.CdUsr = Sep.CdUsrSep
            LEFT JOIN dbo.Stik_Pedido_QtdFat Fat WITH (NOLOCK)
                ON Fat.NrRomaneio = Sep.NrRomaneio
               AND Fat.CdVpo = Sep.CdVpo
            LEFT JOIN dbo.TbObj Obj WITH (NOLOCK)
                ON Obj.CdObj = Sep.CdObj
            LEFT JOIN dbo.TbLot Lot WITH (NOLOCK)
                ON Lot.CdLot = Sep.CdLot
            WHERE Sep.Separado = 1
              AND NOT EXISTS (
                    SELECT 1
                    FROM dbo.Stik_WMS_Romaneio_Conferencia Conf WITH (NOLOCK)
                    WHERE Conf.NrRomaneio = Sep.NrRomaneio
                      AND Conf.CdVpo = Sep.CdVpo
                      AND ISNULL(Conf.CdObj, 0) = ISNULL(Sep.CdObj, 0)
                      AND ISNULL(Conf.Detalhe, 0) = ISNULL(Sep.CdLot, 0)
                      AND Conf.SituacaoConferencia = 'SEPARADO_CONFERIDO'
              )
            ORDER BY Sep.DtSeparacao ASC
        """
        print("DEBUG lista_conferencia executando")

        cursor.execute(sql_query)
        registros = [
            dict(zip([column[0] for column in cursor.description], row))
            for row in cursor.fetchall()
        ]

        return jsonify(registros), 200

    # except Exception as e:
    #     return jsonify({"error": str(e)}), 500

    except Exception as e:
        print(f"❌ Erro ao listar conferência: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


@wms_bp.route('/consulta/romaneio/confirmar_conferencia', methods=['PUT'])
def confirmar_conferencia():
    connection = None
    try:
        data = request.get_json()
        nr_romaneio = data.get('NrRomaneio')
        qt_conferida = float(data.get('QtFatAtend', 0))
        
        # 1. BUSCAR A QUANTIDADE ORIGINAL SOLICITADA (QtFat)
        connection = create_connection_tinturaria()
        cursor = connection.cursor()
        
        cursor.execute("SELECT SUM(QtFat) FROM Stik_Pedido_QtdFat WHERE NrRomaneio = ?", (nr_romaneio,))
        row = cursor.fetchone()
        qt_pedida = float(row[0]) if row and row[0] else 0

        # 2. VALIDAR A REGRA DE NEGÓCIO
        # Se você não quer que finalize com quantidade divergente:
        if qt_conferida != qt_pedida:
            return jsonify({
                "error": f"Divergência: Pedido {qt_pedida} / Conferido {qt_conferida}. O status permanecerá em separação."
            }), 400

        # 3. SE ESTIVER TUDO OK, EXECUTA O UPDATE COM A TRAVA DE STATUS
        sql_update = """
            UPDATE dbo.Stik_Pedido_QtdFat
            SET TpSitFat = 4, QtFatAtend = ?, CdUsrConf = ?, DtConf = GETDATE()
            WHERE NrRomaneio = ? AND TpSitFat = 3
        """
        cursor.execute(sql_update, (qt_conferida, data.get('CdUsrConf'), nr_romaneio))
        
        if cursor.rowcount == 0:
            return jsonify({"error": "Romaneio não encontrado ou já processado."}), 404

        connection.commit()
        return jsonify({"success": True, "message": "Conferência finalizada com sucesso."})

    except Exception as e:
        if connection: connection.rollback()
        return jsonify({"error": str(e)}), 500

        
@wms_bp.route('/consulta/romaneio/finalizar_separacao', methods=['PUT'])
def finalizar_separacao():
    connection = None
    try:
        data = request.get_json() or {}

        nr_romaneio = data.get('nr_romaneio')
        usuario_id = data.get('cd_usr_conf') or data.get('UsuarioID')
        itens = data.get('itens', [])

        if not nr_romaneio or not usuario_id or not isinstance(itens, list) or not itens:
            return jsonify({
                "error": "Campos obrigatórios ausentes",
                "recebido": data
            }), 400

        try:
            nr_romaneio = int(nr_romaneio)
            usuario_id = int(usuario_id)
        except (TypeError, ValueError):
            return jsonify({
                "error": "nr_romaneio ou usuario_id inválido",
                "recebido": {
                    "nr_romaneio": nr_romaneio,
                    "usuario_id": usuario_id
                }
            }), 400

        itens_validos = []
        for idx, item in enumerate(itens, start=1):
            cd_vpo = item.get('cdVpo') or item.get('CdVpo')
            cd_obj = item.get('CdObj') or item.get('cdObj')
            cd_lot = item.get('CdLot') or item.get('cdLot') or item.get('DetalheId')
            qt_sep = item.get('quantidadeSeparada')

            if cd_vpo is None or qt_sep is None:
                return jsonify({
                    "error": f"Item {idx}: CdVpo e quantidadeSeparada são obrigatórios"
                }), 400

            try:
                cd_vpo = int(cd_vpo)
                cd_obj = int(cd_obj) if cd_obj is not None else 0
                cd_lot = int(cd_lot) if cd_lot is not None else 0
                qt_sep = float(str(qt_sep).replace(',', '.'))
            except (TypeError, ValueError):
                return jsonify({"error": f"Item {idx}: dados inválidos"}), 400

            itens_validos.append((cd_vpo, cd_obj, cd_lot, qt_sep))

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco de dados."
            }), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        sql_upsert_fila = """
            IF EXISTS (
                SELECT 1
                FROM dbo.Stik_WMS_Romaneio_Separado
                WHERE NrRomaneio = ?
                  AND CdVpo = ?
                  AND ISNULL(CdObj, 0) = ISNULL(?, 0)
                  AND ISNULL(CdLot, 0) = ISNULL(?, 0)
            )
            BEGIN
                UPDATE dbo.Stik_WMS_Romaneio_Separado
                SET
                    QtSeparada = ?,
                    CdUsrSep = ?,
                    DtSeparacao = GETDATE(),
                    Separado = 1
                WHERE NrRomaneio = ?
                  AND CdVpo = ?
                  AND ISNULL(CdObj, 0) = ISNULL(?, 0)
                  AND ISNULL(CdLot, 0) = ISNULL(?, 0)
            END
            ELSE
            BEGIN
                INSERT INTO dbo.Stik_WMS_Romaneio_Separado
                    (NrRomaneio, CdVpo, CdObj, CdLot, QtSeparada, CdUsrSep, DtSeparacao, Separado)
                VALUES
                    (?, ?, ?, ?, ?, ?, GETDATE(), 1)
            END
        """

        itens_processados = []

        for cd_vpo, cd_obj, cd_lot, qt_sep in itens_validos:
            cursor.execute(
                sql_upsert_fila,
                (
                    nr_romaneio, cd_vpo, cd_obj, cd_lot,
                    qt_sep, usuario_id, nr_romaneio, cd_vpo, cd_obj, cd_lot,
                    nr_romaneio, cd_vpo, cd_obj, cd_lot, qt_sep, usuario_id
                )
            )

            cursor.execute("""
                SELECT COUNT(1)
                FROM dbo.Stik_WMS_Romaneio_Separado
                WHERE NrRomaneio = ?
                  AND CdVpo = ?
                  AND ISNULL(CdObj, 0) = ISNULL(?, 0)
                  AND ISNULL(CdLot, 0) = ISNULL(?, 0)
            """, (nr_romaneio, cd_vpo, cd_obj, cd_lot))
            count_row = cursor.fetchone()
            count_value = count_row[0] if count_row else 0

            print(
                f"DEBUG finalizar_separacao romaneio={nr_romaneio} "
                f"cd_vpo={cd_vpo} cd_obj={cd_obj} cd_lot={cd_lot} "
                f"qt_sep={qt_sep} count={count_value}"
            )

            itens_processados.append({
                "CdVpo": cd_vpo,
                "CdObj": cd_obj,
                "CdLot": cd_lot,
                "QtSeparada": qt_sep,
                "FilaCount": count_value
            })

        connection.commit()

        cursor.execute("""
            SELECT NrRomaneio, CdVpo, CdObj, CdLot, QtSeparada
            FROM dbo.Stik_WMS_Romaneio_Separado
            WHERE NrRomaneio = ?
        """, (nr_romaneio,))
        print("DEBUG apos commit fila", cursor.fetchall())

        return jsonify({
            "status": "SQL_SUCCESS",
            "message": "Separação finalizada com quantidades gravadas na fila da conferência.",
            "nr_romaneio": nr_romaneio,
            "itens_processados": itens_processados
        }), 200

    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({
            "status": "SQL_ERROR",
            "details": str(e)
        }), 500
    finally:
        if connection:
            connection.close()


@wms_bp.route('/consulta/romaneio/conferir2', methods=['PUT'])
def conferir_item_romaneio():
    connection = None
    try:
        data = request.get_json() or {}

        id_registro = data.get('ID')
        qt_atendida = data.get('QtAtendida')
        cd_usr_conf = data.get('CdUsrConf')
        tp_sit_can = data.get('TpSitCan', 0)
        tp_motivo_can = data.get('TpMotivoCan', 0)

        if not id_registro or qt_atendida is None or not cd_usr_conf:
            return jsonify({"error": "Campos obrigatórios: ID, QtAtendida, CdUsrConf"}), 400

        try:
            id_registro = int(id_registro)
            qt_atendida = float(str(qt_atendida).replace(',', '.'))
            cd_usr_conf = int(cd_usr_conf)
            tp_sit_can = int(tp_sit_can)
            tp_motivo_can = int(tp_motivo_can)
        except (TypeError, ValueError):
            return jsonify({"error": "ID/QtAtendida/CdUsrConf inválidos"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET XACT_ABORT ON;")

        cursor.execute("""
            SELECT
                Fat.ID,
                Fat.NrRomaneio,
                Fat.CdVpo,
                ISNULL(Fat.CdObj, 0) AS CdObj,
                ISNULL(Vpo.CdLot, 0) AS CdLot,
                Fat.TpSitFat
            FROM dbo.Stik_Pedido_QtdFat Fat WITH (UPDLOCK, ROWLOCK, HOLDLOCK)
            LEFT JOIN dbo.TbVpo Vpo WITH (NOLOCK)
                ON Vpo.CdVpo = Fat.CdVpo
            WHERE Fat.ID = ?
        """, (id_registro,))
        row = cursor.fetchone()

        if not row:
            return jsonify({"error": "Registro não encontrado."}), 404

        _, nr_romaneio, cd_vpo, cd_obj, cd_lot, tp_sit_fat = row

        if tp_sit_fat != 4:
            return jsonify({
                "error": f"Item não está disponível para conferência. TpSitFat atual: {tp_sit_fat}"
            }), 409

        cursor.execute("""
            SELECT QtSeparada
            FROM dbo.Stik_WMS_Romaneio_Separado WITH (NOLOCK)
            WHERE NrRomaneio = ?
              AND CdVpo = ?
        """, (nr_romaneio, cd_vpo))
        row_sep = cursor.fetchone()

        if not row_sep:
            return jsonify({
                "error": "Quantidade separada não encontrada na fila da conferência."
            }), 404

        qt_separada = float(row_sep[0])

        if abs(qt_atendida - qt_separada) > 0.0001:
            return jsonify({
                "error": "Quantidade divergente da separação.",
                "NrRomaneio": nr_romaneio,
                "CdVpo": cd_vpo,
                "QtDigitada": qt_atendida,
                "QtReferencia": qt_separada
            }), 409

        cursor.execute("""
            UPDATE dbo.Stik_Pedido_QtdFat
            SET
                QtFatAtend = ?,
                TpSitFat = 5,
                TpSitCan = ?,
                TpMotivoCan = ?,
                CdUsrConf = ?,
                DtConf = GETDATE()
            WHERE ID = ?
              AND TpSitFat = 4
        """, (qt_atendida, tp_sit_can, tp_motivo_can, cd_usr_conf, id_registro))

        if cursor.rowcount != 1:
            connection.rollback()
            return jsonify({"error": "Nenhuma linha atualizada para o item."}), 409

        cursor.execute("""
            UPDATE dbo.Stik_WMS_Romaneio_Separado
            SET Separado = 2
            WHERE NrRomaneio = ?
              AND CdVpo = ?
        """, (nr_romaneio, cd_vpo))

        print("DEBUG conferir2 fila rowcount", cursor.rowcount, nr_romaneio, cd_vpo)

        if cursor.rowcount != 1:
            connection.rollback()
            return jsonify({
                "error": "Falha ao atualizar fila da conferência."
            }), 409

        connection.commit()

        return jsonify({
            "message": "Item enviado para faturamento com sucesso.",
            "ID": id_registro,
            "NrRomaneio": nr_romaneio,
            "CdVpo": cd_vpo,
            "QtAtendida": qt_atendida
        }), 200

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

@wms_bp.route('/consulta/romaneio/separado_conferido', methods=['PUT'])
def marcar_separado_conferido():
    connection = None
    try:
        data = request.get_json() or {}

        nr_romaneio = data.get('NrRomaneio')
        cd_usr_conf = data.get('CdUsrConf')
        itens = data.get('itens', [])

        if not nr_romaneio or not cd_usr_conf or not isinstance(itens, list) or not itens:
            return jsonify({"error": "Campos obrigatórios: NrRomaneio, CdUsrConf, itens"}), 400

        try:
            nr_romaneio = int(nr_romaneio)
            cd_usr_conf = int(cd_usr_conf)
        except (TypeError, ValueError):
            return jsonify({"error": "NrRomaneio ou CdUsrConf inválido"}), 400

        itens_validos = []
        for idx, item in enumerate(itens, start=1):
            cd_vpo = item.get('CdVpo') or item.get('cdVpo')
            cd_obj = item.get('CdObj') or item.get('cdObj')
            cd_lot = item.get('CdLot') or item.get('cdLot') or item.get('DetalheId')

            if cd_vpo is None:
                return jsonify({"error": f"Item {idx}: CdVpo obrigatório"}), 400

            try:
                cd_vpo = int(cd_vpo)
                cd_obj = int(cd_obj) if cd_obj is not None else 0
                cd_lot = int(cd_lot) if cd_lot is not None else 0
            except (TypeError, ValueError):
                return jsonify({"error": f"Item {idx}: CdVpo/CdObj/CdLot inválidos"}), 400

            itens_validos.append((cd_vpo, cd_obj, cd_lot))

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({"status": "SQL_ERROR", "details": "Falha ao conectar ao banco."}), 500

        cursor = connection.cursor()
        cursor.execute("SET XACT_ABORT ON;")

        sql_get_qt = """
            SELECT QtSeparada
            FROM dbo.Stik_WMS_Romaneio_Separado
            WHERE NrRomaneio = ?
              AND CdVpo = ?
        """

        sql_insert_conf = """
            IF NOT EXISTS (
                SELECT 1
                FROM dbo.Stik_WMS_Romaneio_Conferencia
                WHERE NrRomaneio = ?
                  AND CdVpo = ?
                  AND ISNULL(CdObj, 0) = ISNULL(?, 0)
                  AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
                  AND SituacaoConferencia = 'SEPARADO_CONFERIDO'
            )
            BEGIN
                INSERT INTO dbo.Stik_WMS_Romaneio_Conferencia
                    (NrRomaneio, CdVpo, CdObj, Detalhe, SituacaoConferencia, CdUsrConf, DtConf)
                VALUES
                    (?, ?, ?, ?, 'SEPARADO_CONFERIDO', ?, GETDATE())
            END
        """

        sql_update_principal = """
            UPDATE dbo.Stik_Pedido_QtdFat
            SET
                QtFatAtend = ?,
                TpSitFat = 4,
                CdUsrConf = ?,
                DtConf = GETDATE()
            WHERE NrRomaneio = ?
              AND CdVpo = ?
        """

        sql_update_fila = """
            UPDATE dbo.Stik_WMS_Romaneio_Separado
            SET Separado = 2
            WHERE NrRomaneio = ?
              AND CdVpo = ?
        """

        itens_processados = []

        for cd_vpo, cd_obj, cd_lot in itens_validos:
            cursor.execute(sql_get_qt, (nr_romaneio, cd_vpo))
            row = cursor.fetchone()
            if not row:
                connection.rollback()
                return jsonify({
                    "error": f"Quantidade separada não encontrada para CdVpo {cd_vpo}."
                }), 404

            qt_separada = float(row[0])

            cursor.execute(
                sql_insert_conf,
                (
                    nr_romaneio, cd_vpo, cd_obj, cd_lot,
                    nr_romaneio, cd_vpo, cd_obj, cd_lot, cd_usr_conf
                )
            )

            cursor.execute(
                sql_update_principal,
                (qt_separada, cd_usr_conf, nr_romaneio, cd_vpo)
            )
            if cursor.rowcount != 1:
                connection.rollback()
                return jsonify({
                    "error": f"Falha ao atualizar principal para CdVpo {cd_vpo}."
                }), 409

            cursor.execute(sql_update_fila, (nr_romaneio, cd_vpo))
            print("DEBUG separado_conferido fila rowcount", cursor.rowcount, nr_romaneio, cd_vpo)

            cursor.execute("""
                SELECT Separado
                FROM dbo.Stik_WMS_Romaneio_Separado
                WHERE NrRomaneio = ?
                  AND CdVpo = ?
            """, (nr_romaneio, cd_vpo))
            row_fila = cursor.fetchone()

            if not row_fila:
                connection.rollback()
                return jsonify({
                    "error": f"Fila não encontrada para CdVpo {cd_vpo}."
                }), 404

            if int(row_fila[0] or 0) != 2:
                connection.rollback()
                return jsonify({
                    "error": f"Fila não atualizada para Separado=2 no CdVpo {cd_vpo}."
                }), 409

            itens_processados.append({
                "CdVpo": cd_vpo,
                "CdObj": cd_obj,
                "CdLot": cd_lot,
                "QtSeparada": qt_separada
            })

        connection.commit()

        return jsonify({
            "success": True,
            "message": f"Romaneio {nr_romaneio} marcado como Separado/Conferido.",
            "nr_romaneio": nr_romaneio,
            "itens_processados": itens_processados
        }), 200

    except Exception as e:
        if connection:
            try:
                connection.rollback()
            except Exception:
                pass
        return jsonify({"status": "SQL_ERROR", "details": str(e)}), 500
    finally:
        if connection:
            connection.close()


@wms_bp.route('/consulta/romaneio/finalizados', methods=['GET'])
def listar_romaneios_finalizados():
    connection = None
    try:
        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        sql_query = """
            WITH Base AS (
                SELECT
                    Fat.NrRomaneio,
                    MAX(Fat.TpSitFat) AS TpSitFat,
                    MAX(Fat.CdUsrConf) AS CdUsrConf,
                    MAX(Fat.DtConf) AS DataAtualizacao
                FROM dbo.Stik_Pedido_QtdFat Fat WITH (NOLOCK)
                WHERE Fat.TpSitFat IN (4, 5)
                GROUP BY Fat.NrRomaneio
            )
            SELECT
                B.NrRomaneio,
                Situacao = CASE
                    WHEN B.TpSitFat = 4 THEN 'Separado/Conferido'
                    WHEN B.TpSitFat = 5 THEN 'Ag.Faturamento'
                    ELSE 'N/D'
                END,
                B.CdUsrConf,
                Usuario = Usr.NmUsr,
                DataConferencia = B.DataAtualizacao,
                DataAtualizacao = B.DataAtualizacao
            FROM Base B
            LEFT JOIN dbo.TbUsr Usr WITH (NOLOCK)
                ON Usr.CdUsr = B.CdUsrConf
            ORDER BY B.DataAtualizacao DESC
        """

        cursor.execute(sql_query)
        registros = [
            dict(zip([column[0] for column in cursor.description], row))
            for row in cursor.fetchall()
        ]

        return jsonify(registros), 200

    except Exception as e:
        return jsonify({
            "status": "SQL_ERROR",
            "details": str(e)
        }), 500
    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: Cancelar Romaneio
# ===================================================================
@wms_bp.route('/consulta/romaneio/cancelar', methods=['POST'])
def cancelar_romaneio():
    """
    Cancela um romaneio.
    Campos obrigatórios: NrRomaneio, Motivo (int), Solicitante (string)
    """
    connection = None
    try:
        data = request.get_json()
        if not data:
            return jsonify({"error": "Dados JSON não fornecidos"}), 400

        nr_romaneio = data.get('NrRomaneio')
        motivo = data.get('Motivo')
        solicitante = data.get('Solicitante')

        if not all([nr_romaneio, motivo, solicitante]):
            return jsonify({
                "error": "Campos 'NrRomaneio', 'Motivo' e 'Solicitante' são obrigatórios."
            }), 400

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        # Atualiza situação do romaneio
        update_query = """
            UPDATE Stik_Pedido_QtdFat
            SET TpSitFat = 11,
                TpMotivoCan = ?
            WHERE NrRomaneio = ?;
        """
        cursor.execute(update_query, (motivo, nr_romaneio))

        if cursor.rowcount == 0:
            return jsonify({"error": "Romaneio não encontrado."}), 404

        # Registra solicitante do cancelamento
        insert_query = """
            INSERT INTO Stik_Solicitante_Canc (DtCancelamento, Solicitante, CdVpo, NrRomaneio)
            SELECT GETDATE(), ?, CdVpo, NrRomaneio
            FROM Stik_Pedido_QtdFat
            WHERE NrRomaneio = ?;
        """
        cursor.execute(insert_query, (solicitante, nr_romaneio))

        connection.commit()

        return jsonify({
            "message": "Cancelamento solicitado com sucesso!",
            "NrRomaneio": nr_romaneio,
            "Motivo": motivo,
            "Solicitante": solicitante
        }), 200

    except Exception as e:
        if connection:
            connection.rollback()
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()


# ===================================================================
# ROTA: Atualizar Romaneios
# ===================================================================
@wms_bp.route('/consulta/romaneio/delta', methods=['GET'])
def get_romaneio_delta():



    connection = None
    try:
        since_raw = request.args.get('since')  # 'YYYY-MM-DD HH:MM:SS'
        cd_usr = request.args.get('cd_usr', '0')
        try:
            cd_usr_int = int(cd_usr)
        except ValueError:
            cd_usr_int = 0

        if not since_raw:
            since_raw = datetime.datetime.now().strftime('%Y-%m-%d 00:00:00')

        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_query = """
            SET NOCOUNT ON;

            DECLARE @Since datetime = ?;
            DECLARE @CdUsr int = ?;

            SELECT NrRomaneio, CdVpo, CdUsrSep, ChangeType, ChangedAt, Payload
            FROM dbo.Romaneio_ChangeLog
            WHERE ChangedAt >= @Since
              AND (
                    @CdUsr = 0
                    OR @CdUsr IN (58, 97, 258, 313, 323, 322, 343, 325, 350, 357, 372, 183, 324, 168, 294, 375, 376, 329, 328, 334, 400, 421, 461, 226, 325, 327, 207, 334)
                    OR CdUsrSep IS NULL
                    OR CdUsrSep = 0
                    OR CdUsrSep = @CdUsr
                  )
            ORDER BY ChangedAt;
        """

        cursor.execute(sql_query, (since_raw, cd_usr_int))
        registros = [dict(zip([c[0] for c in cursor.description], r)) for r in cursor.fetchall()]
        return jsonify(registros)

    except Exception as e:
        return jsonify({"error": str(e)}), 500
    finally:
        if connection:
            connection.close()

@wms_bp.route('/consulta/romaneio/cancelar_item', methods=['PUT', 'POST'])
def cancelar_item_romaneio():
    connection = None
    try:
        data = request.get_json() or {}

        nr_romaneio = data.get('NrRomaneio')
        cd_vpo = data.get('CdVpo')
        cd_obj = data.get('CdObj')
        cd_lot = data.get('CdLot')
        motivo = data.get('Motivo')
        solicitante = data.get('Solicitante')

        if not nr_romaneio or not cd_vpo or motivo is None:
            return jsonify({
                "error": "NrRomaneio, CdVpo e Motivo são obrigatórios"
            }), 400

        try:
            nr_romaneio = int(nr_romaneio)
            cd_vpo = int(cd_vpo)
            cd_obj = int(cd_obj) if cd_obj is not None else 0
            cd_lot = int(cd_lot) if cd_lot is not None else 0
            motivo = int(motivo)
        except (TypeError, ValueError):
            return jsonify({
                "error": "NrRomaneio, CdVpo, CdObj, CdLot ou Motivo inválidos"
            }), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        cursor = connection.cursor()
        cursor.execute("SET XACT_ABORT ON;")

        cursor.execute("""
            SELECT ID, CdObj, CdLot
            FROM dbo.Stik_Pedido_QtdFat
            WHERE NrRomaneio = ?
              AND CdVpo = ?
        """, (nr_romaneio, cd_vpo))
        row = cursor.fetchone()

        if not row:
            return jsonify({"error": "Item do romaneio não encontrado."}), 404

        _, db_cd_obj, db_cd_lot = row

        if cd_obj and int(db_cd_obj or 0) != cd_obj:
            return jsonify({"error": "CdObj divergente para o item informado."}), 409

        if cd_lot and int(db_cd_lot or 0) != cd_lot:
            return jsonify({"error": "CdLot divergente para o item informado."}), 409

        cursor.execute("""
            UPDATE dbo.Stik_Pedido_QtdFat
            SET
                TpSitFat = 11,
                TpMotivoCan = ?
            WHERE NrRomaneio = ?
              AND CdVpo = ?
        """, (motivo, nr_romaneio, cd_vpo))

        if cursor.rowcount != 1:
            connection.rollback()
            return jsonify({"error": "Nenhuma linha atualizada para o item."}), 409

        if solicitante:
            cursor.execute("""
                INSERT INTO dbo.Stik_Solicitante_Canc
                    (DtCancelamento, Solicitante, CdVpo, NrRomaneio)
                VALUES
                    (GETDATE(), ?, ?, ?)
            """, (str(solicitante), cd_vpo, nr_romaneio))

        connection.commit()

        return jsonify({
            "success": True,
            "message": "Item cancelado com sucesso.",
            "NrRomaneio": nr_romaneio,
            "CdVpo": cd_vpo
        }), 200

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

@wms_bp.route('/consulta/wms/palete/itens_embalagem', methods=['GET'])
def listar_itens_palete_embalagem():
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
            WITH BaseItens AS (
                SELECT
                    Endereco = UPPER(LTRIM(RTRIM(A.Endereco))),
                    A.CodSKU,
                    CdLot = ISNULL(A.Detalhe, 0),
                    QtSaldoFinal = ISNULL(A.QtAlocada, 0)
                FROM dbo.Stik_WMS_Alocacao A WITH (NOLOCK)
                WHERE UPPER(LTRIM(RTRIM(A.Endereco))) = ?
            ),
            MovItens AS (
                SELECT
                    Endereco = UPPER(LTRIM(RTRIM(M.Endereco))),
                    M.CodSKU,
                    CdLot = ISNULL(M.Detalhe, 0),
                    QtSaldoFinal = SUM(
                        CASE
                            WHEN M.TpMov = 1 THEN ISNULL(M.QtMovida, 0)
                            WHEN M.TpMov = 3 THEN ISNULL(M.QtMovida, 0)
                            WHEN M.TpMov = 2 THEN -ISNULL(M.QtMovida, 0)
                            ELSE 0
                        END
                    )
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
                    M.CodSKU,
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
                SELECT CodSKU, CdLot FROM BaseItens
                UNION
                SELECT CodSKU, CdLot FROM MovItens
                UNION
                SELECT CodSKU, CdLot FROM EmbAtual
                UNION
                SELECT CodSKU, CdLot FROM EmbMov
            )
            SELECT
                Endereco = ?,
                CodSKU = C.CodSKU,
                Detalhe = C.CdLot,
                Descricao = ISNULL(Obj.NmObj, 'Produto não identificado'),
                QtSaldoFinal = ISNULL(B.QtSaldoFinal, 0) + ISNULL(MI.QtSaldoFinal, 0),
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
                END
            FROM Chaves C
            LEFT JOIN BaseItens B
                ON B.CodSKU = C.CodSKU
               AND B.CdLot = C.CdLot
            LEFT JOIN MovItens MI
                ON MI.CodSKU = C.CodSKU
               AND MI.CdLot = C.CdLot
            LEFT JOIN EmbAtual EA
                ON EA.CodSKU = C.CodSKU
               AND EA.CdLot = C.CdLot
            LEFT JOIN EmbMov EM
                ON EM.CodSKU = C.CodSKU
               AND EM.CdLot = C.CdLot
            LEFT JOIN dbo.TbObj Obj WITH (NOLOCK)
                ON Obj.CdObj = C.CodSKU
            WHERE
                (ISNULL(B.QtSaldoFinal, 0) + ISNULL(MI.QtSaldoFinal, 0)) > 0
                OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaP, 0) ELSE ISNULL(EM.QtCaixaP, 0) END > 0
                OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtCaixaG, 0) ELSE ISNULL(EM.QtCaixaG, 0) END > 0
                OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfestado, 0) ELSE ISNULL(EM.QtEnfestado, 0) END > 0
                OR CASE WHEN EA.CodSKU IS NOT NULL THEN ISNULL(EA.QtEnfraldado, 0) ELSE ISNULL(EM.QtEnfraldado, 0) END > 0
            ORDER BY Descricao, C.CdLot
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

# Padrão de Caixas
def _normalizar_texto(valor):
    texto = (valor or '').strip()
    if not texto:
        return ''
    texto = unicodedata.normalize('NFKD', texto)
    texto = ''.join(ch for ch in texto if not unicodedata.combining(ch))
    return ' '.join(texto.split()).strip()


def _extrair_artigo_base(artigo):
    texto = _normalizar_texto(artigo)
    if not texto:
        return ''

    match = re.search(r'^(.+?\bmm)\b', texto, flags=re.IGNORECASE)
    if match:
        return match.group(1).strip()

    return texto.strip()


def _serializar_padrao_caixa(row):
    return {
        "artigo": row[0],
        "caixa_p": row[1],
        "enfestado": row[2],
        "enfraldado": row[3],
        "caixa_g": row[4],
        "disco": row[5],
    }


def _consultar_padrao_caixa_banco(artigo=None):
    connection = None
    try:
        connection = create_connection_tinturaria()
        if connection is None:
            return []

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON;")

        artigo_busca = (artigo or '').strip()
        if artigo_busca:
            cursor.execute("""
                SELECT
                    artigo,
                    caixa_p,
                    enfestado,
                    enfraldado,
                    caixa_g,
                    disco
                FROM dbo.Stik_PadraoCaixa WITH (NOLOCK)
                WHERE UPPER(LTRIM(RTRIM(artigo))) = UPPER(LTRIM(RTRIM(?)))
                ORDER BY artigo
            """, (artigo_busca,))
        else:
            cursor.execute("""
                SELECT
                    artigo,
                    caixa_p,
                    enfestado,
                    enfraldado,
                    caixa_g,
                    disco
                FROM dbo.Stik_PadraoCaixa WITH (NOLOCK)
                ORDER BY artigo
            """)

        return [_serializar_padrao_caixa(row) for row in cursor.fetchall()]
    finally:
        if connection:
            connection.close()


@wms_bp.route('/consulta/wms/stik_padrao_caixa', methods=['GET'])
@wms_bp.route('/consulta/wms/padrao_caixa', methods=['GET'])
@wms_bp.route('/consulta/wms/padrao-caixa', methods=['GET'])
def consultar_padrao_caixa():
    artigo = request.args.get('artigo') or request.args.get('Artigo')
    try:
        rows = _consultar_padrao_caixa_banco(artigo)
        return jsonify({"data": rows, "rows": rows}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500


def _obter_token_node_api():
    urls_login = [
        'https://api.stiktech.com.br/auth/login',
    ]

    payload = {
        'username': 'anderson',
        'password': '142046',
    }

    for url in urls_login:
        try:
            resp = requests.post(
                url,
                json=payload,
                timeout=15,
                headers={'Content-Type': 'application/json'}
            )
            if resp.status_code != 200:
                continue

            body = resp.json() or {}
            token = body.get('accessToken') or body.get('token')
            if token:
                return token
        except Exception:
            continue

    return None


def _resolver_artigo_oficial_por_sku(cod_sku):
    token = _obter_token_node_api()
    if not token:
        return None

    urls_artigos = [
        'https://api.stiktech.com.br/api/artigos',
    ]

    for url in urls_artigos:
        try:
            resp = requests.get(
                url,
                params={'CdObj': cod_sku},
                timeout=15,
                headers={
                    'Content-Type': 'application/json',
                    'Authorization': f'Bearer {token}',
                }
            )
            if resp.status_code != 200:
                continue

            payload = resp.json() or {}
            rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

            if not isinstance(rows, list) or not rows:
                continue

            for row in rows:
                if not isinstance(row, dict):
                    continue

                artigo = str(
                    row.get('artigo')
                    or row.get('Artigo')
                    or row.get('ARTIGO')
                    or row.get('Objeto')
                    or row.get('objeto')
                    or row.get('NmArtigo')
                    or ''
                ).strip()

                if artigo:
                    return artigo
        except Exception:
            continue

    return None


def _buscar_padrao_embalagem_por_artigo(artigo):
    urls_padrao = [
        'https://api.stiktech.com.br/consulta/wms/stik_padrao_caixa',
        'http://168.190.90.2:3000/consulta/wms/stik_padrao_caixa',
    ]

    artigo_normalizado = _normalizar_texto(artigo).lower()

    for url in urls_padrao:
        try:
            resp = requests.get(url, timeout=15)
            if resp.status_code != 200:
                continue

            payload = resp.json() or {}
            rows = payload.get('data') or payload.get('rows') or payload.get('result') or []

            if not isinstance(rows, list) or not rows:
                continue

            for row in rows:
                if not isinstance(row, dict):
                    continue

                artigo_row = str(
                    row.get('artigo')
                    or row.get('Artigo')
                    or row.get('ARTIGO')
                    or row.get('Objeto')
                    or row.get('objeto')
                    or row.get('NmArtigo')
                    or ''
                ).strip()

                if not artigo_row:
                    continue

                artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
                if artigo_row_normalizado == artigo_normalizado:
                    return row

            for row in rows:
                if not isinstance(row, dict):
                    continue

                artigo_row = str(
                    row.get('artigo')
                    or row.get('Artigo')
                    or row.get('ARTIGO')
                    or row.get('Objeto')
                    or row.get('objeto')
                    or row.get('NmArtigo')
                    or ''
                ).strip()

                if not artigo_row:
                    continue

                artigo_row_normalizado = _normalizar_texto(artigo_row).lower()
                if artigo_normalizado in artigo_row_normalizado:
                    return row
        except Exception:
            continue

    return None

@wms_bp.route('/consulta/wms/palete/ajustar_embalagem', methods=['POST'])
def ajustar_embalagem_palete():
    connection = None
    try:
        data = request.get_json() or {}

        endereco = (data.get('endereco') or '').strip().upper()
        cod_sku = data.get('cod_sku')
        detalhe = data.get('detalhe', 0)
        artigo = (data.get('artigo') or '').strip()
        cd_usr = data.get('cd_usr')

        qt_caixa_p = data.get('qt_caixa_p', 0)
        qt_caixa_g = data.get('qt_caixa_g', 0)
        qt_enfestado = data.get('qt_enfestado', 0)
        qt_enfraldado = data.get('qt_enfraldado', 0)

        if not endereco or cod_sku is None:
            return jsonify({
                "error": "Campos obrigatórios: endereco, cod_sku"
            }), 400

        try:
            cod_sku = int(cod_sku)
            detalhe = int(detalhe or 0)
            cd_usr = int(cd_usr) if cd_usr not in (None, '', '0', 0) else None
            qt_caixa_p = int(qt_caixa_p or 0)
            qt_caixa_g = int(qt_caixa_g or 0)
            qt_enfestado = int(qt_enfestado or 0)
            qt_enfraldado = int(qt_enfraldado or 0)
        except (TypeError, ValueError):
            return jsonify({"error": "Parâmetros inválidos"}), 400

        if min(qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado) < 0:
            return jsonify({"error": "Quantidades de embalagem não podem ser negativas"}), 400

        connection = create_connection_tinturaria()
        if connection is None:
            return jsonify({
                "status": "SQL_ERROR",
                "details": "Falha ao conectar ao banco."
            }), 500

        cursor = connection.cursor()
        cursor.execute("SET NOCOUNT ON; SET XACT_ABORT ON;")

        sql_item = """
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
                  AND A.CodSKU = ?
                  AND ISNULL(A.Detalhe, 0) = ISNULL(?, 0)
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
                  AND M.CodSKU = ?
                  AND ISNULL(M.Detalhe, 0) = ISNULL(?, 0)
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
                  AND E.CodSKU = ?
                  AND ISNULL(E.Detalhe, 0) = ISNULL(?, 0)
            ),
            EmbMov AS (
                SELECT
                    CodSKU = M.CodSKU,
                    CdLot = ISNULL(M.Detalhe, 0),
                    QtCaixaP = SUM(
                        CASE
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaP, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaP, 0)
                            ELSE 0
                        END
                    ),
                    QtCaixaG = SUM(
                        CASE
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtCaixaG, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtCaixaG, 0)
                            ELSE 0
                        END
                    ),
                    QtEnfestado = SUM(
                        CASE
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoDestino, '')))) = ? THEN ISNULL(M.QtEnfestado, 0)
                            WHEN UPPER(LTRIM(RTRIM(ISNULL(M.EnderecoOrigem, '')))) = ? THEN -ISNULL(M.QtEnfestado, 0)
                            ELSE 0
                        END
                    ),
                    QtEnfraldado = SUM(
                        CASE
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
                  AND M.CodSKU = ?
                  AND ISNULL(M.Detalhe, 0) = ISNULL(?, 0)
                GROUP BY
                    M.CodSKU,
                    ISNULL(M.Detalhe, 0)
            )
            SELECT TOP 1
                QtSaldoFinal =
                    ISNULL(B.QtSaldoInicial, 0)
                    + ISNULL(M.QtMovEntrada, 0)
                    + ISNULL(M.QtMovRetorno, 0)
                    - ISNULL(M.QtMovSaida, 0),
                QtCaixaP = CASE
                    WHEN B.Endereco IS NOT NULL THEN ISNULL(EA.QtCaixaP, 0)
                    ELSE ISNULL(EM.QtCaixaP, 0)
                END,
                QtCaixaG = CASE
                    WHEN B.Endereco IS NOT NULL THEN ISNULL(EA.QtCaixaG, 0)
                    ELSE ISNULL(EM.QtCaixaG, 0)
                END,
                QtEnfestado = CASE
                    WHEN B.Endereco IS NOT NULL THEN ISNULL(EA.QtEnfestado, 0)
                    ELSE ISNULL(EM.QtEnfestado, 0)
                END,
                QtEnfraldado = CASE
                    WHEN B.Endereco IS NOT NULL THEN ISNULL(EA.QtEnfraldado, 0)
                    ELSE ISNULL(EM.QtEnfraldado, 0)
                END
            FROM Base B
            FULL OUTER JOIN Mov M
                ON M.Endereco = B.Endereco
               AND M.CodSKU = B.CodSKU
               AND M.CdLot = B.CdLot
            FULL OUTER JOIN EmbAtual EA
                ON EA.Endereco = COALESCE(B.Endereco, M.Endereco)
               AND EA.CodSKU = COALESCE(B.CodSKU, M.CodSKU)
               AND EA.CdLot = COALESCE(B.CdLot, M.CdLot)
            FULL OUTER JOIN EmbMov EM
                ON EM.CodSKU = COALESCE(B.CodSKU, M.CodSKU, EA.CodSKU)
               AND EM.CdLot = COALESCE(B.CdLot, M.CdLot, EA.CdLot)
        """

        cursor.execute(sql_item, (
            endereco, cod_sku, detalhe,
            endereco, cod_sku, detalhe,
            endereco, cod_sku, detalhe,
            endereco, endereco,
            endereco, endereco,
            endereco, endereco,
            endereco, endereco,
            endereco, endereco,
            cod_sku, detalhe,
        ))
        row_item = cursor.fetchone()

        if not row_item:
            return jsonify({
                "error": "Item não encontrado neste palete."
            }), 404

        qt_saldo_final = float((row_item[0] or 0))
        if qt_saldo_final <= 0:
            return jsonify({
                "error": "Item sem saldo disponível neste palete."
            }), 409

        saldo_caixa_p = int((row_item[1] or 0))
        saldo_caixa_g = int((row_item[2] or 0))
        saldo_enfestado = int((row_item[3] or 0))
        saldo_enfraldado = int((row_item[4] or 0))

        cursor.execute("""
            IF EXISTS (
                SELECT 1
                FROM dbo.Stik_WMS_Alocacao_Embalagem
                WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
                  AND CodSKU = ?
                  AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
            )
            BEGIN
                UPDATE dbo.Stik_WMS_Alocacao_Embalagem
                SET
                    QtCaixaP = ?,
                    QtCaixaG = ?,
                    QtEnfestado = ?,
                    QtEnfraldado = ?,
                    DtAtualizacao = GETDATE()
                WHERE UPPER(LTRIM(RTRIM(Endereco))) = ?
                  AND CodSKU = ?
                  AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
            END
            ELSE
            BEGIN
                INSERT INTO dbo.Stik_WMS_Alocacao_Embalagem
                    (Endereco, CodSKU, Detalhe, QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado, DtAtualizacao)
                VALUES
                    (?, ?, ?, ?, ?, ?, ?, GETDATE())
            END
        """, (
            endereco, cod_sku, detalhe,
            qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado,
            endereco, cod_sku, detalhe,
            endereco, cod_sku, detalhe,
            qt_caixa_p, qt_caixa_g, qt_enfestado, qt_enfraldado
        ))

        # A tela de Alocações usa Stik_WMS_Caixa (uma linha DISPONIVEL por
        # caixa P/G), e não o contador agregado acima. Mantém as duas fontes
        # coerentes quando a Auditoria ajusta a quantidade física. O CX aqui
        # é apenas uma chave técnica gerada para a nova unidade auditada; a
        # regra operacional continua sendo CdObj + Detalhe + TipoCaixa.
        cursor.execute("""
            DECLARE @Tipo varchar(10), @Alvo int, @Atual int, @Delta int;

            DECLARE tipos_auditoria CURSOR LOCAL FAST_FORWARD FOR
                SELECT Tipo, Alvo
                FROM (VALUES ('P', ?), ('G', ?)) V(Tipo, Alvo);

            OPEN tipos_auditoria;
            FETCH NEXT FROM tipos_auditoria INTO @Tipo, @Alvo;

            WHILE @@FETCH_STATUS = 0
            BEGIN
                SELECT @Atual = COUNT(1)
                FROM dbo.Stik_WMS_Caixa WITH (UPDLOCK, HOLDLOCK)
                WHERE Status = 'DISPONIVEL'
                  AND UPPER(LTRIM(RTRIM(Endereco))) = ?
                  AND CdObj = ?
                  AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
                  AND UPPER(LTRIM(RTRIM(TipoCaixa))) = @Tipo;

                SET @Delta = @Alvo - ISNULL(@Atual, 0);

                WHILE @Delta > 0
                BEGIN
                    DECLARE @NovoCx varchar(20);
                    SET @NovoCx = 'A' + RIGHT(
                        '0000000' + CONVERT(varchar(20),
                            ABS(CONVERT(bigint, CHECKSUM(NEWID())))), 7
                    );

                    IF NOT EXISTS (
                        SELECT 1 FROM dbo.Stik_WMS_Caixa WHERE CX = @NovoCx
                    )
                    BEGIN
                        INSERT INTO dbo.Stik_WMS_Caixa
                            (CX, CdObj, Detalhe, TipoCaixa, DataFabricacao,
                             Endereco, CdUsr, DataImpressao, DataAlocacao,
                             Status, IdExecucao, DataConsumo, LI)
                        VALUES
                            (@NovoCx, ?, ?, @Tipo,
                             CONVERT(varchar(8), GETDATE(), 112), ?, ?,
                             GETDATE(), GETDATE(), 'DISPONIVEL', NULL, NULL, NULL);
                        SET @Delta = @Delta - 1;
                    END
                END

                IF @Delta < 0
                BEGIN
                    ;WITH Remover AS (
                        SELECT TOP (ABS(@Delta)) *
                        FROM dbo.Stik_WMS_Caixa WITH (UPDLOCK, READPAST)
                        WHERE Status = 'DISPONIVEL'
                          AND UPPER(LTRIM(RTRIM(Endereco))) = ?
                          AND CdObj = ?
                          AND ISNULL(Detalhe, 0) = ISNULL(?, 0)
                          AND UPPER(LTRIM(RTRIM(TipoCaixa))) = @Tipo
                        ORDER BY DataAlocacao DESC, ID DESC
                    )
                    UPDATE Remover
                    SET Status = 'AJUSTE_REMOVIDA',
                        IdExecucao = NULL,
                        DataConsumo = GETDATE();
                END

                FETCH NEXT FROM tipos_auditoria INTO @Tipo, @Alvo;
            END

            CLOSE tipos_auditoria;
            DEALLOCATE tipos_auditoria;
        """, (
            qt_caixa_p, qt_caixa_g,
            endereco, cod_sku, detalhe,
            cod_sku, detalhe, endereco, cd_usr,
            endereco, cod_sku, detalhe,
        ))

        cursor.execute("""
            INSERT INTO dbo.Stik_WMS_Movimento_Embalagem
                (EnderecoOrigem, EnderecoDestino, CodSKU, Detalhe, TpMov,
                 QtCaixaP, QtCaixaG, QtEnfestado, QtEnfraldado,
                 QtMovidaMetro, CdUsr, Origem, Observacao, DataMovimento)
            VALUES
                (?, NULL, ?, ?, 4, ?, ?, ?, ?, ?, ?, 'AJUSTE', 'Ajuste manual de embalagem', GETDATE())
        """, (
            endereco,
            cod_sku,
            detalhe,
            qt_caixa_p,
            qt_caixa_g,
            qt_enfestado,
            qt_enfraldado,
            qt_saldo_final,
            cd_usr
        ))

        connection.commit()

        return jsonify({
            "success": True,
            "message": "Ajuste de embalagem salvo com sucesso.",
            "endereco": endereco,
            "cod_sku": cod_sku,
            "detalhe": detalhe,
            "artigo": artigo,
            "qt_saldo_final": qt_saldo_final,
            "qt_caixa_p": qt_caixa_p,
            "qt_caixa_g": qt_caixa_g,
            "qt_enfestado": qt_enfestado,
            "qt_enfraldado": qt_enfraldado,
            "saldo_anterior": {
                "QtCaixaP": saldo_caixa_p,
                "QtCaixaG": saldo_caixa_g,
                "QtEnfestado": saldo_enfestado,
                "QtEnfraldado": saldo_enfraldado
            }
        }), 200

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
    
  

    
  

    
  
