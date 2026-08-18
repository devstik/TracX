import threading
import time
import webbrowser
from flask import Flask, render_template
from flask_cors import CORS
from flask_compress import Compress
from flask_bcrypt import Bcrypt 

from consulta.embalagem import embalagem_bp
from consulta.tinturaria import tinturaria_bp
from consulta.movimentacao import movimentacao_bp
from consulta.usuarios import usuarios_bp 
from database.server import create_connection
from database.server import create_connection_tinturaria
from consulta.movimentacao import movimentacao_historico_bp
from consulta.TinturariaDados import tinturariaDados_bp, tinturariaOperador_bp
from consulta.WMS_Romaneio import wms_bp 
from consulta.WMS_Enderecos import wms_enderecos_bp
from consulta.WMS_Ruas import wms_ruas_bp
from consulta.WMS_Usuarios import wms_usuarios_bp
from consulta.WMS_Objetos import wms_objetos_bp
from consulta.WMS_Alocacao import wms_alocacao_bp
from consulta.WMS_Movimentos import wms_movimentos_bp
from consulta.WMS_Conferido import wms_conferido_bp
from consulta.WMS_Etiquetas import wms_etiquetas_bp
from consulta.WMS_ListarAlocacoes import wms_listar_alocacoes_bp
from consulta.WMS_Update import wms_update_bp
from consulta.WMS_Faturamento import wms_faturamento_bp
from consulta.WMS_Etiquetas_Separacao import wms_separacao_bp
from consulta.TRACX_Grafico import TRACX_Grafico_bp
from consulta.WMS_EtiquetaProduto import wms_etiqueta_produto_bp
from consulta.Update_PC import wms_update_pc_bp
from consulta.Consulta_Comissoes import comissoes_bp
from consulta.FyoX_Producao import fyox_producao_bp
from consulta.FyoX_ProducaoMaq import fyox_producaoMAQ_bp
from consulta.Fyox_ProducaoPost import fyox_producaoPost_bp
from consulta.Fyox_MaqArtigo import fyox_MaqArtigo_bp
from consulta.TracX_Apontamento import tracx_ApontamentoPost_bp
from consulta.TracX_MaqSetor import tracx_producaoSetorMAQ_bp
from consulta.WMS_Cancelados import wms_cancelados_bp
from consulta.WMS_Transferencia_palete_embalagem import wms_transferencia_embalagem_bp
from consulta.WMS_Autorizados import wms_autorizados_bp
from consulta.WMS_Separacao_Planejada import wms_separacao_planejada_bp
from consulta.WMS_Etiquetas_QrCode import WMS_Etiquetas_QrCode_bp
from consulta.WMS_Caixa import wms_caixa_bp



app = Flask(__name__, template_folder="template")
app.config['JSON_SORT_KEYS'] = False # Opcional: Mantém a ordem do JSON
CORS(app) 
Compress(app) 
bcrypt = Bcrypt(app) 

# Estabelece a conexão com o banco de dados para teste de conexão inicial
conn = create_connection()

if conn:
    print('Conexão com o banco de dados estabelecida com sucesso.')
    conn.close() 
else:
    print('Falha ao estabelecer conexão com o banco de dados.')


@app.route('/', methods=['GET'])
def home():
    # Renderiza o template home.html
    return render_template('home.html')

# Registro dos blueprints das rotas
app.register_blueprint(embalagem_bp)
app.register_blueprint(tinturaria_bp)
app.register_blueprint(movimentacao_bp)
app.register_blueprint(usuarios_bp)
app.register_blueprint(movimentacao_historico_bp)
app.register_blueprint(tinturariaDados_bp)
app.register_blueprint(tinturariaOperador_bp)
app.register_blueprint(wms_bp) 
app.register_blueprint(wms_enderecos_bp)
app.register_blueprint(wms_ruas_bp)
app.register_blueprint(wms_usuarios_bp)
app.register_blueprint(wms_objetos_bp)
app.register_blueprint(wms_alocacao_bp)
app.register_blueprint(wms_movimentos_bp)
app.register_blueprint(wms_conferido_bp)
app.register_blueprint(wms_etiquetas_bp)
app.register_blueprint(wms_listar_alocacoes_bp)
app.register_blueprint(wms_update_bp)
app.register_blueprint(wms_faturamento_bp)
app.register_blueprint(wms_separacao_bp)
app.register_blueprint(TRACX_Grafico_bp)
app.register_blueprint(wms_etiqueta_produto_bp)
app.register_blueprint(wms_update_pc_bp)
app.register_blueprint(comissoes_bp)
app.register_blueprint(fyox_producao_bp)
app.register_blueprint(fyox_producaoMAQ_bp)
app.register_blueprint(fyox_producaoPost_bp)
app.register_blueprint(fyox_MaqArtigo_bp)
app.register_blueprint(tracx_ApontamentoPost_bp)
app.register_blueprint(tracx_producaoSetorMAQ_bp)
app.register_blueprint(wms_cancelados_bp)
app.register_blueprint(wms_transferencia_embalagem_bp)
app.register_blueprint(wms_autorizados_bp)
app.register_blueprint(wms_separacao_planejada_bp)
app.register_blueprint(WMS_Etiquetas_QrCode_bp)
app.register_blueprint(wms_caixa_bp)



if __name__ == '__main__':
    # Inicia o servidor Flask
    app.run(host="0.0.0.0", port=5000, debug=False)

# Função para abrir navegador automaticamente (se desejar usar, descomente)
# def abrir_navegador():
#     time.sleep(1) # Espera o servidor iniciar
#     # Tenta pegar IP local da máquina
#     # hostname = socket.gethostname()
#     # local_ip = socket.gethostbyname(hostname)
#     # url_local = f"http://{local_ip}:5000"
#     # print(f"Abrindo navegador no endereço {url_local}")
#     # webbrowser.open(url_local)

