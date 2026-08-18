from flask import Blueprint, jsonify, request
from database.server import create_connection_tinturaria 
import datetime  

# Define o Blueprint
TRACX_Grafico_bp = Blueprint('TRACX_Grafico', __name__)

@TRACX_Grafico_bp.route('/consulta/Tracx/resumo_producao', methods=['GET'])
def get_producao_previsao():
    """
    Endpoint para retornar o Total de Produção, Média Diária, 
    """
    connection = None
    try:
        connection = create_connection_tinturaria() 
        cursor = connection.cursor()

        # SQL Integrado com a lógica de DiasProduzidosDia e DiasProduzidosMes
        sql_query = """
        SET DATEFIRST 1;

        WITH Feriados AS (
            -- Feriados de Janeiro (para o DiasProduzidosDia)
            SELECT CAST(data AS DATE) AS DataFeriado, 'JAN' AS Tipo FROM (VALUES 
                ('2026-01-01'), ('2026-01-02'), ('2026-01-03'), ('2026-01-04')) AS t(data)
            UNION ALL
            -- Feriados de Dezembro (para o DiasProduzidosMes conforme DAX)
            SELECT CAST(data AS DATE), 'DEZ' FROM (VALUES 
                ('2025-12-25'), ('2025-12-31')) AS t(data)
        ),
        ProducaoRealizada AS (
            SELECT 
                SUM(CASE WHEN QtEntrada > 0 THEN QtEntrada ELSE 0 END) AS TotalProducao,
                SUM(CASE 
                    WHEN DATEPART(WEEKDAY, DataDoMapa) BETWEEN 1 AND 5 THEN 1.0 
                    WHEN DATEPART(WEEKDAY, DataDoMapa) = 6 THEN 0.5            
                    ELSE 0 
                END) AS DiasProduzidosDia
            FROM (
                SELECT DISTINCT CAST(DataDoMapa AS DATE) AS DataDoMapa, SUM(QtEntrada) as QtEntrada
                FROM Vw_DiarioDeMovDeEstoque
                WHERE DataDoMapa >= DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1)
                  AND DataDoMapa <= CAST(GETDATE() AS DATE)
                  AND CAST(DataDoMapa AS DATE) NOT IN (SELECT DataFeriado FROM Feriados WHERE Tipo = 'JAN')
                GROUP BY CAST(DataDoMapa AS DATE)
            ) AS MovimentacaoUnica
        ),
        CalendarioCompleto AS (
            SELECT DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1) AS DataCalendario
            UNION ALL
            SELECT DATEADD(DAY, 1, DataCalendario)
            FROM CalendarioCompleto
            WHERE DATEADD(DAY, 1, DataCalendario) <= EOMONTH(GETDATE())
        ),
        DiasProduzidosMes AS (
            SELECT 
                SUM(CASE 
                    WHEN f.DataFeriado IS NOT NULL THEN 0
                    WHEN DATEPART(WEEKDAY, c.DataCalendario) BETWEEN 1 AND 5 THEN 1.0
                    WHEN DATEPART(WEEKDAY, c.DataCalendario) = 6 THEN 0.5
                    ELSE 0 
                END) AS DiasProduzidosMes
            FROM CalendarioCompleto c
            LEFT JOIN Feriados f ON c.DataCalendario = f.DataFeriado AND f.Tipo = 'DEZ'
        )
        SELECT 
            ISNULL(pr.TotalProducao, 0) AS TotalProducao,
            ISNULL(pr.DiasProduzidosDia, 0) AS DiasProduzidosDia,
            ISNULL(dpm.DiasProduzidosMes, 0) AS DiasProduzidosMes,
            CASE WHEN pr.DiasProduzidosDia > 0 THEN (pr.TotalProducao / pr.DiasProduzidosDia) ELSE 0 END AS Media_Diaria,
            CASE WHEN pr.DiasProduzidosDia > 0 THEN (pr.TotalProducao / pr.DiasProduzidosDia) * dpm.DiasProduzidosMes ELSE 0 END AS PrevisaoFechamento
        FROM ProducaoRealizada pr
        CROSS JOIN DiasProduzidosMes dpm
        OPTION (MAXRECURSION 31);
        """
        
        cursor.execute(sql_query)
        row = cursor.fetchone()

        if row:
            result = {
                "TotalProducao": float(row[0]),
                "DiasProduzidosDia": float(row[1]),
                "DiasProduzidosMes": float(row[2]),
                "MediaDiaria": float(row[3]),
                "PrevisaoFechamento": float(row[4]),
                "DataConsulta": datetime.datetime.now().strftime("%d/%m/%Y %H:%M:%S")
            }
            return jsonify(result), 200
        else:
            return jsonify({"error": "Nenhum dado encontrado para o período"}), 404

    except Exception as e:
        print(f"❌ Erro na consulta de produção: {e}")
        return jsonify({"error": str(e)}), 500

    finally:
        if connection: 
            connection.close()