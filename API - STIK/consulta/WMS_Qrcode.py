from flask import Blueprint, send_file, request, jsonify
import io
import time
import qrcode
import json
from PIL import Image, ImageDraw, ImageFont
from zpl import Label
# Certifique-se que o import da sua conexão está correto
from database.server import create_connection_tinturaria 

wms_etiquetas_bp = Blueprint('wms_etiquetas', __name__)
wms_objetos_bp = Blueprint('wms_objetos', __name__)

FILA_IMPRESSAO = []

def _gerar_imagem_etiqueta(cd_obj, nm_obj, cd_lot):
    try:
        LARGURA_PX, ALTURA_PX = 816, 576 
        img = Image.new('L', (LARGURA_PX, ALTURA_PX), 255)
        draw = ImageDraw.Draw(img)
        
        try:
            font_principal = ImageFont.truetype("arialbd.ttf", 45)
        except:
            font_principal = ImageFont.load_default()

        # --- CONTEÚDO DO QR CODE EM FORMATO JSON (Apenas códigos) ---
        dados_qr = {
            "CdObj": int(cd_obj),
            "Detalhe": int(cd_lot)
        }
        conteudo_qr = json.dumps(dados_qr)  # Transforma o dicionário em string JSON
        
        qr = qrcode.QRCode(version=1, box_size=10, border=0)
        qr.add_data(conteudo_qr)
        qr.make(fit=True)
        qr_img = qr.make_image(fill_color="black", back_color="white").convert('L')
        
        # Tamanho 180 e Centralização
        qr_size = 180
        qr_img = qr_img.resize((qr_size, qr_size), Image.Resampling.NEAREST)
        qr_x = (LARGURA_PX - qr_size) // 2
        qr_y = 60 
        img.paste(qr_img, (qr_x, qr_y))

        # Nome do Objeto (NmObj) visível para o humano ler na etiqueta
        txt_nm = str(nm_obj)
        bbox = draw.textbbox((0, 0), txt_nm, font=font_principal)
        texto_x = (LARGURA_PX - (bbox[2] - bbox[0])) // 2
        texto_y = qr_y + qr_size + 40
        draw.text((texto_x, texto_y), txt_nm, font=font_principal, fill=0)

        return img.point(lambda x: 0 if x < 128 else 255, '1')
    except Exception as e:
        print(f"Erro: {e}")
        raise

@wms_etiquetas_bp.route('/consulta/wms/gerar_etiqueta', methods=['GET'])
def gerar_etiqueta():
    cd = request.args.get('cd', '')
    nm = request.args.get('nm', '')
    lot = request.args.get('lot', '')
    img = _gerar_imagem_etiqueta(cd, nm, lot)
    img_io = io.BytesIO()
    img.save(img_io, 'PNG')
    img_io.seek(0)
    return send_file(img_io, mimetype='image/png')

@wms_etiquetas_bp.route('/consulta/wms/imprimir_etiqueta_api', methods=['POST'])
def imprimir_etiqueta_api():
    try:
        data = request.get_json()
        # Capturamos o CdLot enviado pelo Flutter
        img_pil = _gerar_imagem_etiqueta(data['cd'], data['nm'], data['cd_lot'])
        
        label = Label(width=102, height=72, dpmm=8)
        label.write_graphic(img_pil, width=102, height=72)
        
        FILA_IMPRESSAO.append({
            "id": int(time.time()), 
            "endereco": str(data['nm']), 
            "zpl": label.dumpZPL()
        })
        return jsonify({"status": "ok"})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@wms_etiquetas_bp.route('/consulta/wms/buscar_impressao', methods=['GET'])
def buscar_impressao():
    if FILA_IMPRESSAO:
        return jsonify(FILA_IMPRESSAO.pop(0))
    else:
        return jsonify(None), 204

@wms_objetos_bp.route('/consulta/wms/objeto/<int:grupo_id>', methods=['GET'])
def get_wms_objetos(grupo_id):
    conn = None
    try:
        conn = create_connection_tinturaria()
        cursor = conn.cursor()
        query = """
            SELECT CdObj, NmObj, NmLot 
            FROM dbo.TbObj Obj 
            JOIN dbo.TbArvObj Arv ON Arv.CdObjFil = Obj.CdObj 
            JOIN dbo.TbLot Lot ON Lot.CdObj = Obj.CdObj 
            WHERE Arv.CdObj = ?
        """
        cursor.execute(query, (grupo_id,))
        cols = [c[0] for c in cursor.description]
        results = [dict(zip(cols, r)) for r in cursor.fetchall()]
        return jsonify(results)
    finally:
        if conn:
            conn.close()