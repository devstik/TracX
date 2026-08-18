from flask import Blueprint, jsonify, request
from datetime import datetime, timedelta, date
from database.server import create_connection_tinturaria 

fyox_producaoPost_bp = Blueprint('fyox_producaoPost', __name__)

def _format_timedelta(td: timedelta) -> str:
    total_seconds = int(td.total_seconds())
    hours, remainder = divmod(total_seconds, 3600)
    minutes, seconds = divmod(remainder, 60)
    return f"{hours:02d}:{minutes:02d}:{seconds:02d}"


def _parse_date_only(value):
    if not value:
        return datetime.now().date()

    if isinstance(value, datetime):
        return value.date()

    if isinstance(value, date):
        return value

    if isinstance(value, str):
        raw = value.strip()

        for fmt in (
            '%Y-%m-%d',
            '%d/%m/%Y',
            '%Y-%m-%d %H:%M:%S',
            '%Y-%m-%d %H:%M:%S.%f',
        ):
            try:
                return datetime.strptime(raw, fmt).date()
            except ValueError:
                pass

        try:
            return datetime.fromisoformat(raw).date()
        except ValueError:
            pass

    raise ValueError(f'Data inválida: {value}')


def _parse_datetime_flexible(value, base_date=None):
    if not value:
        return None

    if isinstance(value, datetime):
        return value

    if isinstance(value, str):
        raw = value.strip()

        try:
            return datetime.fromisoformat(raw)
        except ValueError:
            pass

        for fmt in (
            '%Y-%m-%d %H:%M:%S.%f',
            '%Y-%m-%d %H:%M:%S',
            '%Y-%m-%d %H:%M',
            '%d/%m/%Y %H:%M:%S',
            '%d/%m/%Y %H:%M',
        ):
            try:
                return datetime.strptime(raw, fmt)
            except ValueError:
                pass

        for fmt in ('%H:%M:%S', '%H:%M'):
            try:
                hora = datetime.strptime(raw, fmt).time()
                if base_date is None:
                    base_date = datetime.now().date()
                return datetime.combine(base_date, hora)
            except ValueError:
                pass

    return None


# ==========================
# POST - SALVAR PRODUÇÃO
# ==========================
@fyox_producaoPost_bp.route('/producao/mapa', methods=['POST'])
def salvar_producao():
    data_json = request.get_json() or {}

    maquina_id = data_json.get('MaquinaID')
    artigo_id = data_json.get('ArtigoID')
    producao = data_json.get('Producao')
    id_setor = data_json.get('IDSetor')
    meta = data_json.get('Meta')
    odom_inicio = data_json.get('OdomInicio')
    odom_fim = data_json.get('OdomFim')
    data_registro = data_json.get('Data')

    # AJUSTE TURNO: recebe o turno selecionado no app
    turno_recebido = data_json.get('Turno') or data_json.get('TurnoID')

    try:
        if id_setor is not None:
            id_setor = int(str(id_setor).strip())
            if id_setor == 4214:
                id_setor = 4763
    except (TypeError, ValueError):
        pass

    duracao = data_json.get('Duracao')
    eficiencia = data_json.get('Eficiencia')
    cod_parada = data_json.get('CodParada')
    parada_inicio = data_json.get('ParadaInicio')
    parada_fim = data_json.get('ParadaFim')
    duracao_parada = data_json.get('DuracaoParada')

    if isinstance(meta, str):
        meta = float(meta.replace(',', '.'))

    inicio = data_json.get('Inicio')
    fim = data_json.get('Fim')

    if maquina_id is None or artigo_id is None or producao is None:
        return jsonify({"error": "Campos obrigatórios: MaquinaID, ArtigoID, Producao"}), 400

    try:
        data_base = _parse_date_only(data_registro)

        if isinstance(odom_inicio, str):
            odom_inicio = float(odom_inicio.replace(',', '.'))
        if isinstance(odom_fim, str):
            odom_fim = float(odom_fim.replace(',', '.'))
        if isinstance(eficiencia, str):
            eficiencia = float(eficiencia.replace(',', '.'))

        inicio = _parse_datetime_flexible(inicio, data_base)
        fim = _parse_datetime_flexible(fim, data_base)

        if inicio and fim:
            delta = fim - inicio
            if delta.total_seconds() < 0:
                delta += timedelta(days=1)
            duracao = _format_timedelta(delta)

        parada_inicio = _parse_datetime_flexible(parada_inicio, data_base)
        parada_fim = _parse_datetime_flexible(parada_fim, data_base)

        if parada_inicio and parada_fim:
            delta_p = parada_fim - parada_inicio
            if delta_p.total_seconds() < 0:
                delta_p += timedelta(days=1)
            duracao_parada = _format_timedelta(delta_p)

    except Exception:
        pass

    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        data_base = _parse_date_only(data_registro)
        data_para_gravar = data_base.strftime('%Y-%m-%d')

        # AJUSTE TURNO:
        # Se o app enviar A, B ou C, usa o turno selecionado.
        # Se não enviar, mantém o comportamento anterior calculando pela hora atual.
        mapa_turnos = {
            'A': 8,
            'B': 9,
            'C': 10,
            '8': 8,
            '9': 9,
            '10': 10,
            8: 8,
            9: 9,
            10: 10,
        }

        turno_id = mapa_turnos.get(str(turno_recebido).strip().upper())

        if turno_id is None:
            hora_atual = datetime.now().hour

            if 8 <= hora_atual < 14:
                turno_id = 8
            elif 14 <= hora_atual < 22:
                turno_id = 9
            else:
                turno_id = 10

        sql_insert = """
            INSERT INTO Stik_PCP_PREPARACAO
            (Data, MaquinaID, ArtigoID, TurnoID, Producao, Meta, IDSetor,
             OdomInicio, OdomFim, Duracao, Eficiencia, CodParada,
             ParadaInicio, ParadaFim, DuracaoParada)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        valores = (
            data_para_gravar,
            maquina_id,
            artigo_id,
            turno_id,
            producao,
            meta,
            id_setor,
            odom_inicio,
            odom_fim,
            duracao,
            eficiencia,
            cod_parada,
            parada_inicio,
            parada_fim,
            duracao_parada
        )

        cursor.execute(sql_insert, valores)
        connection.commit()

        return jsonify({
            "message": "Produção registrada com sucesso!",
            "turno": turno_id
        }), 201

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()



# ==========================
# GET - CONSULTAR PRODUÇÃO
# ==========================
@fyox_producaoPost_bp.route('/producao/consultar/mapa', methods=['GET'])
def buscar_producao():
    connection = None
    try:
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        sql_select = """
            SELECT 
                P.ID,                 
                P.Data, 
                P.MaquinaID, 
                Maq.NmObj AS NomeMaquina,
                P.ArtigoID, 
                Art.NmObj AS NomeArtigo,
                P.TurnoID, 
                P.Producao, 
                P.Meta,
                P.IDSetor,
                P.OdomInicio,
                P.OdomFim,
                P.Duracao,
                P.Eficiencia,
                P.CodParada,
                P.ParadaInicio,
                P.ParadaFim,
                P.DuracaoParada
            FROM Stik_PCP_PREPARACAO P
            LEFT JOIN TbObj Maq ON P.MaquinaID = Maq.CdObj
            LEFT JOIN TbObj Art ON P.ArtigoID = Art.CdObj
            ORDER BY P.Data DESC, P.TurnoID ASC
        """
        
        cursor.execute(sql_select)
        rows = cursor.fetchall()

        resultados = []
        for row in rows:
            setor_nome = "Desconhecido"
            if row[9] == 4213:
                setor_nome = "Urdideira"
            elif row[9] == 4763:
                setor_nome = "Recobrideira"

            resultados.append({
                "ID": row[0],  # ✅ enviar ID
                "Data": row[1],
                "MaquinaID": row[2],
                "NomeMaquina": row[3],
                "ArtigoID": row[4],
                "NomeArtigo": row[5],
                "TurnoID": row[6],
                "Producao": float(row[7]) if row[7] else 0,
                "Meta": float(row[8]) if row[8] else 0,
                "IDSetor": row[9],
                "OdomInicio": float(row[10]) if row[10] else None,
                "OdomFim": float(row[11]) if row[11] else None,
                "Duracao": str(row[12]) if row[12] else None,
                "Eficiencia": float(row[13]) if row[13] else None,
                "CodParada": row[14],
                "ParadaInicio": row[15],
                "ParadaFim": row[16],
                "DuracaoParada": str(row[17]) if row[17] else None,
                "Setor": setor_nome
            })

        return jsonify(resultados), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()



@fyox_producaoPost_bp.route('/producao/mapa/<int:producao_id>', methods=['PATCH'])
def atualizar_producao(producao_id):
    data_json = request.get_json() or {}

    if not data_json:
        return jsonify({"error": "Nenhum campo para atualizar."}), 400

    try:
        # Confere se o registro existe antes do UPDATE
        connection = create_connection_tinturaria()
        cursor = connection.cursor()

        cursor.execute(
            "SELECT ID FROM Stik_PCP_PREPARACAO WHERE ID = ?",
            (producao_id,)
        )
        if cursor.fetchone() is None:
            return jsonify({"error": "Registro não encontrado."}), 404

        campos = {}

        def campo_enviado(nome):
            return nome in data_json

        def valor(nome):
            return data_json.get(nome)

        # Data
        if campo_enviado("Data"):
            campos["Data"] = _parse_date_only(valor("Data")).strftime("%Y-%m-%d")

        # Máquina / Artigo
        if campo_enviado("MaquinaID"):
            campos["MaquinaID"] = valor("MaquinaID")

        if campo_enviado("ArtigoID"):
            campos["ArtigoID"] = valor("ArtigoID")

        # Turno: aceita A/B/C ou 8/9/10
        turno_recebido = data_json.get("TurnoID", data_json.get("Turno"))
        if "TurnoID" in data_json or "Turno" in data_json:
            mapa_turnos = {
                "A": 8,
                "B": 9,
                "C": 10,
                "8": 8,
                "9": 9,
                "10": 10,
                8: 8,
                9: 9,
                10: 10,
            }

            turno_id = mapa_turnos.get(
                str(turno_recebido).strip().upper()
                if turno_recebido is not None
                else None
            )

            if turno_id is None:
                return jsonify({"error": "Turno inválido."}), 400

            campos["TurnoID"] = turno_id

        # Setor: aceita IDSetor ou Setor textual
        if campo_enviado("IDSetor"):
            id_setor = valor("IDSetor")
            if id_setor is not None:
                id_setor = int(str(id_setor).strip())
                if id_setor == 4214:
                    id_setor = 4763
            campos["IDSetor"] = id_setor

        elif campo_enviado("Setor"):
            setor = str(valor("Setor") or "").strip().lower()
            mapa_setores = {
                "urdideira": 4213,
                "recobrideira": 4763,
                "tecelagem": 4215,
                "rachelina": 4216,
            }
            campos["IDSetor"] = mapa_setores.get(setor)

        # Numéricos
        for nome in ("Producao", "Meta", "OdomInicio", "OdomFim", "Eficiencia"):
            if campo_enviado(nome):
                v = valor(nome)
                if isinstance(v, str) and v.strip() != "":
                    v = float(v.replace(",", "."))
                elif v == "":
                    v = None
                campos[nome] = v

        # Parada
        if campo_enviado("CodParada"):
            campos["CodParada"] = valor("CodParada")

        # Compatibilidade com a tela:
        # se vier Inicio/Fim, grava em OdomInicio/OdomFim
        if campo_enviado("Inicio") and not campo_enviado("OdomInicio"):
            campos["OdomInicio"] = valor("Inicio")

        if campo_enviado("Fim") and not campo_enviado("OdomFim"):
            campos["OdomFim"] = valor("Fim")

        # Datas/horários de parada
        data_base = _parse_date_only(data_json.get("Data")) if data_json.get("Data") else None

        if campo_enviado("ParadaInicio"):
            campos["ParadaInicio"] = _parse_datetime_flexible(
                valor("ParadaInicio"),
                data_base
            )

        if campo_enviado("ParadaFim"):
            campos["ParadaFim"] = _parse_datetime_flexible(
                valor("ParadaFim"),
                data_base
            )

        # Duração normal
        if campo_enviado("Duracao"):
            campos["Duracao"] = valor("Duracao")

        # Duração da parada
        if campo_enviado("DuracaoParada"):
            campos["DuracaoParada"] = valor("DuracaoParada")

        # Recalcula duração se vier Inicio/Fim
        inicio_raw = data_json.get("Inicio")
        fim_raw = data_json.get("Fim")

        if inicio_raw and fim_raw:
            base = data_base or datetime.now().date()
            inicio_dt = _parse_datetime_flexible(inicio_raw, base)
            fim_dt = _parse_datetime_flexible(fim_raw, base)

            if inicio_dt and fim_dt:
                delta = fim_dt - inicio_dt
                if delta.total_seconds() < 0:
                    delta += timedelta(days=1)
                campos["Duracao"] = _format_timedelta(delta)

        # Recalcula duração da parada se vier início/fim da parada
        parada_inicio = campos.get("ParadaInicio")
        parada_fim = campos.get("ParadaFim")

        if parada_inicio and parada_fim:
            delta_p = parada_fim - parada_inicio
            if delta_p.total_seconds() < 0:
                delta_p += timedelta(days=1)
            campos["DuracaoParada"] = _format_timedelta(delta_p)

        if not campos:
            return jsonify({"error": "Nenhum campo válido para atualizar."}), 400

        set_clause = ", ".join([f"{campo} = ?" for campo in campos.keys()])
        valores = list(campos.values())
        valores.append(producao_id)

        sql_update = f"""
            UPDATE Stik_PCP_PREPARACAO
            SET {set_clause}
            WHERE ID = ?
        """

        cursor.execute(sql_update, valores)
        connection.commit()

        return jsonify({
            "message": "Produção atualizada com sucesso!",
            "id": producao_id,
            "campos_atualizados": list(campos.keys())
        }), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        if connection:
            connection.close()