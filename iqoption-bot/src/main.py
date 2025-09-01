import logging
import requests
import pandas as pd
import pandas_ta as ta
from datetime import datetime
import json
import time
import random
import threading
from fastapi import FastAPI
import uvicorn
from fastapi.responses import HTMLResponse
from fastapi import Request

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# ==================== CONFIGURAÇÕES ====================
CONFIG_PATH = "./iqo.json"

def carregar_configuracoes():
    """Carrega configurações do arquivo JSON"""
    try:
        with open(CONFIG_PATH, 'r') as f:
            config = json.load(f)
        return config
    except:
        return {
            "IQ_EMAIL": "julianoas@gmail.com",
            "IQ_SENHA": "i+J@$.2305*"
        }

config = carregar_configuracoes()
IQ_EMAIL = config['IQ_EMAIL']
IQ_SENHA = config['IQ_SENHA']
ENDPOINT_LOGIN = "https://auth.iqoption.com/api/v1.0/login"

ATIVOS = ["EURUSD-OTC", "GBPUSD-OTC", "USDJPY-OTC"]
TIMEFRAME = 1  # minutos
EXPIRACAO_ENTRADA = 1  # minutos
VALOR_ENTRADA = 6

# Parâmetros da Estratégia
MA_FAST_PERIOD = 5
MA_SLOW_PERIOD = 20
RSI_PERIOD = 7
# ======================================================

class IQOptionBot:
    def __init__(self):
        self.ssid = None
        self.connected = False
        self.balance = 10000
        self.ultimos_timestamps = {ativo: 0 for ativo in ATIVOS}
        self.estatisticas = {
            'inicio': datetime.now(),
            'operacoes_total': 0,
            'operacoes_win': 0,
            'operacoes_loss': 0,
            'lucro_total': 0,
            'prejuizo_total': 0,
            'saldo_inicial': 10000,
            'saldo_atual': 10000,
            'ativos': {},
            'historico_operacoes': [],
            'ultimo_relatorio': datetime.now(),
            'velas_recebidas': 0,
            'sinais_gerados': 0,
            'status': 'iniciando',
            'ultima_atualizacao': datetime.now()
        }
        
        for ativo in ATIVOS:
            self.estatisticas['ativos'][ativo] = {
                'operacoes': 0,
                'wins': 0,
                'losses': 0,
                'lucro': 0,
                'fractais_detectados': 0,
                'velas_recebidas': 0,
                'ultimo_sinal': None,
                'ultimo_preco': None
            }
        
        # Inicializar FastAPI
        self.app = FastAPI(title="IQ Option Bot Dashboard", version="1.0.0")
        self.setup_routes()
        
    def setup_routes(self):
        """Configura as rotas da API"""
        
        @self.app.get("/", response_class=HTMLResponse)
        async def dashboard(request: Request):
            return self.gerar_dashboard_html()
        
        @self.app.get("/api/estatisticas")
        async def get_estatisticas():
            return self.estatisticas
        
        @self.app.get("/api/operacoes")
        async def get_operacoes(limit: int = 20):
            return self.estatisticas['historico_operacoes'][-limit:]
        
        @self.app.get("/api/ativo/{nome_ativo}")
        async def get_ativo(nome_ativo: str):
            if nome_ativo in self.estatisticas['ativos']:
                return self.estatisticas['ativos'][nome_ativo]
            return {"error": "Ativo não encontrado"}
        
        @self.app.get("/health")
        async def health_check():
            return {"status": "online", "timestamp": datetime.now().isoformat()}
    
    def gerar_dashboard_html(self):
        """Gera HTML para o dashboard"""
        stats = self.estatisticas
        total_ops = stats['operacoes_total']
        wins = stats['operacoes_win']
        losses = stats['operacoes_loss']
        win_rate = (wins / total_ops * 100) if total_ops > 0 else 0
        lucro_liquido = stats['lucro_total'] - stats['prejuizo_total']
        
        html = f"""
        <!DOCTYPE html>
        <html lang="pt-BR">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>IQ Option Bot Dashboard</title>
            <style>
                body {{ font-family: Arial, sans-serif; margin: 20px; background-color: #f5f5f5; }}
                .container {{ max-width: 1200px; margin: 0 auto; }}
                .card {{ background: white; padding: 20px; margin: 10px 0; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }}
                .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }}
                .stat {{ text-align: center; padding: 15px; }}
                .stat-value {{ font-size: 24px; font-weight: bold; color: #333; }}
                .stat-label {{ color: #666; }}
                .positive {{ color: #28a745; }}
                .negative {{ color: #dc3545; }}
                .neutral {{ color: #007bff; }}
                table {{ width: 100%; border-collapse: collapse; margin: 10px 0; }}
                th, td {{ padding: 8px; text-align: left; border-bottom: 1px solid #ddd; }}
                th {{ background-color: #f8f9fa; }}
                .ativo-row:hover {{ background-color: #f8f9fa; }}
            </style>
        </head>
        <body>
            <div class="container">
                <h1>🤖 IQ Option Bot Dashboard</h1>
                
                <div class="card">
                    <h2>📊 Estatísticas Gerais</h2>
                    <div class="grid">
                        <div class="stat">
                            <div class="stat-value">{total_ops}</div>
                            <div class="stat-label">Total de Operações</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value {'' if total_ops > 0 else 'neutral'}">{win_rate:.1f}%</div>
                            <div class="stat-label">Win Rate</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value {'' if wins > 0 else 'neutral'}">{wins}</div>
                            <div class="stat-label">Wins</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value {'' if losses > 0 else 'neutral'}">{losses}</div>
                            <div class="stat-label">Losses</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value {'' if lucro_liquido >= 0 else 'negative'}">${lucro_liquido:.2f}</div>
                            <div class="stat-label">Lucro Líquido</div>
                        </div>
                        <div class="stat">
                            <div class="stat-value">${stats['saldo_atual']:.2f}</div>
                            <div class="stat-label">Saldo Atual</div>
                        </div>
                    </div>
                </div>

                <div class="card">
                    <h2>📈 Desempenho por Ativo</h2>
                    <table>
                        <tr>
                            <th>Ativo</th>
                            <th>Operações</th>
                            <th>Wins</th>
                            <th>Win Rate</th>
                            <th>Lucro</th>
                            <th>Fractais</th>
                        </tr>
        """
        
        for ativo, dados in stats['ativos'].items():
            ativo_win_rate = (dados['wins'] / dados['operacoes'] * 100) if dados['operacoes'] > 0 else 0
            lucro_class = "positive" if dados['lucro'] >= 0 else "negative"
            
            html += f"""
                        <tr class="ativo-row">
                            <td><strong>{ativo}</strong></td>
                            <td>{dados['operacoes']}</td>
                            <td>{dados['wins']}</td>
                            <td>{ativo_win_rate:.1f}%</td>
                            <td class="{lucro_class}">${dados['lucro']:.2f}</td>
                            <td>{dados['fractais_detectados']}</td>
                        </tr>
            """
        
        html += """
                    </table>
                </div>

                <div class="card">
                    <h2>🕐 Informações do Sistema</h2>
                    <p><strong>Status:</strong> <span style="color: green;">●</span> Online</p>
                    <p><strong>Iniciado em:</strong> """ + stats['inicio'].strftime('%d/%m/%Y %H:%M:%S') + """</p>
                    <p><strong>Última atualização:</strong> """ + stats['ultima_atualizacao'].strftime('%d/%m/%Y %H:%M:%S') + """</p>
                    <p><strong>Velas processadas:</strong> """ + str(stats['velas_recebidas']) + """</p>
                    <p><strong>Sinais gerados:</strong> """ + str(stats['sinais_gerados']) + """</p>
                </div>

                <div class="card">
                    <h2>🔗 Endpoints da API</h2>
                    <ul>
                        <li><a href="/api/estatisticas" target="_blank">/api/estatisticas</a> - Estatísticas completas (JSON)</li>
                        <li><a href="/api/operacoes" target="_blank">/api/operacoes</a> - Últimas operações (JSON)</li>
                        <li><a href="/health" target="_blank">/health</a> - Status do serviço</li>
                    </ul>
                </div>
            </div>

            <script>
                // Auto-refresh a cada 10 segundos
                setTimeout(() => {{ location.reload(); }}, 10000);
            </script>
        </body>
        </html>
        """
        return html

    def conectar_iq(self):
        """Conexão direta com a API da IQ Option"""
        logging.info("🔐 Conectando à IQ Option via API moderna...")
        try:
            payload = {
                "email": IQ_EMAIL,
                "password": IQ_SENHA
            }
            
            headers = {
                "Content-Type": "application/json",
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            }
            
            response = requests.post(ENDPOINT_LOGIN, json=payload, headers=headers, timeout=30)
            
            if response.status_code == 200:
                data = response.json()
                if 'data' in data and 'ssid' in data['data']:
                    self.ssid = data['data']['ssid']
                    logging.info("✅ Login bem-sucedido!")
                    logging.info(f"🔑 SSID: {self.ssid}")
                    self.connected = True
                    return True
                else:
                    logging.error(f"❌ Resposta inesperada: {data}")
            else:
                logging.error(f"❌ Falha no login: Status {response.status_code}")
            
            return False
            
        except Exception as e:
            logging.error(f"💥 Erro na conexão: {e}")
            return False
    
    def obter_candles_simulados(self, ativo, count):
        """Gera candles simulados para demo"""
        try:
            candles = []
            base_price = 1.10000 if "EURUSD" in ativo else 1.25000 if "GBPUSD" in ativo else 110.000
            current_time = int(time.time())
            
            for i in range(count):
                open_price = base_price + random.uniform(-0.001, 0.001)
                close_price = open_price + random.uniform(-0.0005, 0.0005)
                high_price = max(open_price, close_price) + random.uniform(0, 0.0003)
                low_price = min(open_price, close_price) - random.uniform(0, 0.0003)
                
                candle = {
                    'open': round(open_price, 5),
                    'high': round(high_price, 5),
                    'low': round(low_price, 5),
                    'close': round(close_price, 5),
                    'volume': random.randint(50, 150),
                    'from': current_time - (count - i) * TIMEFRAME * 60
                }
                candles.append(candle)
            
            return candles
            
        except Exception as e:
            logging.error(f"❌ Erro ao gerar candles: {e}")
            return None
    
    def processar_ativo(self, ativo):
        """Processa um ativo para análise"""
        try:
            candles = self.obter_candles_simulados(ativo, 10)
            if not candles or len(candles) < 5:
                return
            
            # Verificar nova vela
            current_timestamp = candles[-1].get('from', 0)
            if current_timestamp <= self.ultimos_timestamps.get(ativo, 0):
                return
                
            self.ultimos_timestamps[ativo] = current_timestamp
            self.estatisticas['velas_recebidas'] += 1
            self.estatisticas['ativos'][ativo]['velas_recebidas'] += 1
            
            # Log da nova vela
            logging.info(f"🕯️ {ativo}: O:{candles[-1]['open']:.5f} H:{candles[-1]['high']:.5f} L:{candles[-1]['low']:.5f} C:{candles[-1]['close']:.5f}")
            
            # Gerar sinal
            sinal = self.gerar_sinal(candles, ativo)
            if sinal:
                self.executar_operacao(ativo, sinal)
                
        except Exception as e:
            logging.error(f"❌ Erro processando {ativo}: {e}")
    
    def detectar_fractal_3_velas(self, candles):
        """Detecta fractal de 3 velas"""
        try:
            if len(candles) < 3:
                return None, None
            
            # Últimas 3 velas
            high_ant = candles[-3].get('high', 0)
            high_meio = candles[-2].get('high', 0)
            high_atual = candles[-1].get('high', 0)
            
            low_ant = candles[-3].get('low', 0)
            low_meio = candles[-2].get('low', 0)
            low_atual = candles[-1].get('low', 0)
            
            fractal_alta = (high_meio > high_ant and high_meio > high_atual)
            fractal_baixa = (low_meio < low_ant and low_meio < low_atual)
            
            if fractal_alta:
                logging.info(f"🎯 FRACTAL ALTA detectado!")
            if fractal_baixa:
                logging.info(f"🎯 FRACTAL BAIXA detectado!")
            
            return fractal_alta, fractal_baixa
            
        except Exception as e:
            logging.error(f"❌ Erro ao detectar fractal: {e}")
            return None, None
    
    def calcular_indicadores(self, candles):
        """Calcula indicadores técnicos"""
        try:
            if len(candles) < 10:
                return None
                
            # Converter para DataFrame
            df = pd.DataFrame(candles)
            
            # Médias Móveis
            df['SMA_7'] = ta.sma(df['close'], length=MA_FAST_PERIOD)
            df['SMA_21'] = ta.sma(df['close'], length=MA_SLOW_PERIOD)
            
            # RSI
            df['RSI'] = ta.rsi(df['close'], length=RSI_PERIOD)
            
            return df
            
        except Exception as e:
            logging.error(f"❌ Erro ao calcular indicadores: {e}")
            return None
    
    def gerar_sinal(self, candles, asset):
        """Gera sinal de trading"""
        try:
            df = self.calcular_indicadores(candles)
            if df is None or len(df) < 5:
                return None
            
            ultimo = df.iloc[-1]
            
            if pd.isna(ultimo['SMA_7']) or pd.isna(ultimo['SMA_21']) or pd.isna(ultimo['RSI']):
                return None
            
            # Detectar fractais
            fractal_alta, fractal_baixa = self.detectar_fractal_3_velas(candles)
            
            if fractal_alta:
                logging.info(f"🎯 {asset} - FRACTAL ALTA detectado")
                self.estatisticas['ativos'][asset]['fractais_detectados'] += 1
            
            if fractal_baixa:
                logging.info(f"🎯 {asset} - FRACTAL BAIXA detectado")
                self.estatisticas['ativos'][asset]['fractais_detectados'] += 1
            
            # Estratégia: Cruzamento de Médias + RSI + Fractal
            call_conditions = [
                ultimo['SMA_7'] > ultimo['SMA_21'],
                ultimo['RSI'] > 50,
                fractal_baixa
            ]
            
            put_conditions = [
                ultimo['SMA_7'] < ultimo['SMA_21'],
                ultimo['RSI'] < 50,
                fractal_alta
            ]
            
            if all(call_conditions):
                logging.info(f"📈 {asset} - SINAL CALL CONFIRMADO!")
                self.estatisticas['sinais_gerados'] += 1
                return "call"
                
            elif all(put_conditions):
                logging.info(f"📉 {asset} - SINAL PUT CONFIRMADO!")
                self.estatisticas['sinais_gerados'] += 1
                return "put"
                
            return None
            
        except Exception as e:
            logging.error(f"❌ Erro ao gerar sinal: {e}")
            return None
    
    def executar_operacao(self, asset, direcao):
        """Executa operação de trading simulada"""
        try:
            if self.balance < VALOR_ENTRADA:
                logging.warning("⚠️ Saldo insuficiente para operar")
                return
            
            # Registrar operação
            operacao_id = len(self.estatisticas['historico_operacoes']) + 1
            operacao = {
                'id': operacao_id,
                'timestamp': datetime.now(),
                'ativo': asset,
                'direcao': direcao,
                'valor': VALOR_ENTRADA,
                'status': 'pending'
            }
            self.estatisticas['historico_operacoes'].append(operacao)
            self.estatisticas['operacoes_total'] += 1
            self.estatisticas['ativos'][asset]['operacoes'] += 1
            
            # Simular operação (60% de chance de win para demo)
            resultado = random.random() < 0.6
            lucro = VALOR_ENTRADA * 0.8 if resultado else -VALOR_ENTRADA
            
            logging.info(f"🎯 Ordem #{operacao_id}: {direcao.upper()} {asset} - ${VALOR_ENTRADA}")
            
            if resultado:
                logging.info(f"💰 WIN! Lucro: ${lucro:.2f}")
                self.estatisticas['operacoes_win'] += 1
                self.estatisticas['lucro_total'] += lucro
                self.estatisticas['ativos'][asset]['wins'] += 1
                self.estatisticas['ativos'][asset]['lucro'] += lucro
            else:
                logging.info(f"❌ LOSS! Prejuízo: ${abs(lucro):.2f}")
                self.estatisticas['operacoes_loss'] += 1
                self.estatisticas['prejuizo_total'] += abs(lucro)
                self.estatisticas['ativos'][asset]['losses'] += 1
                self.estatisticas['ativos'][asset]['lucro'] += lucro
            
            # Atualizar saldo
            self.balance += lucro
            self.estatisticas['saldo_atual'] = self.balance
            self.estatisticas['ultima_atualizacao'] = datetime.now()
            
        except Exception as e:
            logging.error(f"❌ Erro ao executar operação: {e}")
    
    def exibir_estatisticas(self):
        """Exibe estatísticas do bot"""
        try:
            agora = datetime.now()
            if (agora - self.estatisticas['ultimo_relatorio']).total_seconds() < 30:
                return
                
            self.estatisticas['ultimo_relatorio'] = agora
            self.estatisticas['ultima_atualizacao'] = agora
            
            total_ops = self.estatisticas['operacoes_total']
            wins = self.estatisticas['operacoes_win']
            losses = self.estatisticas['operacoes_loss']
            
            print("\n" + "="*80)
            print("📊 ESTATÍSTICAS DO BOT - MODO DEMO")
            print("="*80)
            print(f"⏰ Tempo de operação: {agora - self.estatisticas['inicio']}")
            print(f"📈 Total de operações: {total_ops}")
            print(f"🎯 Sinais gerados: {self.estatisticas['sinais_gerados']}")
            print(f"🕯️ Velas recebidas: {self.estatisticas['velas_recebidas']}")
            
            if total_ops > 0:
                win_rate = (wins / total_ops) * 100
                lucro_liquido = self.estatisticas['lucro_total'] - self.estatisticas['prejuizo_total']
                variacao_saldo = ((self.estatisticas['saldo_atual'] - self.estatisticas['saldo_inicial']) / 
                                 self.estatisticas['saldo_inicial']) * 100
                
                print(f"✅ Wins: {wins} | ❌ Losses: {losses}")
                print(f"🎯 Win Rate: {win_rate:.1f}%")
                print(f"💰 Lucro total: ${self.estatisticas['lucro_total']:.2f}")
                print(f"💸 Prejuízo total: ${self.estatisticas['prejuizo_total']:.2f}")
                print(f"💵 Lucro líquido: ${lucro_liquido:.2f}")
                print(f"🏦 Saldo inicial: ${self.estatisticas['saldo_inicial']:.2f}")
                print(f"🏦 Saldo atual: ${self.estatisticas['saldo_atual']:.2f}")
                print(f"📊 Variação do saldo: {variacao_saldo:+.1f}%")
            else:
                print("📭 Nenhuma operação executada ainda")
                print(f"🏦 Saldo atual: ${self.estatisticas['saldo_atual']:.2f}")
            
            fractais_totais = sum(stats['fractais_detectados'] for stats in self.estatisticas['ativos'].values())
            print(f"🎯 Fractais detectados: {fractais_totais}")
            
            print("\n📈 Desempenho por Ativo:")
            for ativo, stats in self.estatisticas['ativos'].items():
                if stats['velas_recebidas'] > 0:
                    ativo_win_rate = (stats['wins'] / stats['operacoes']) * 100 if stats['operacoes'] > 0 else 0
                    print(f"   {ativo}:")
                    print(f"     Velas: {stats['velas_recebidas']}")
                    print(f"     Fractais: {stats['fractais_detectados']}")
                    print(f"     Operações: {stats['operacoes']}")
                    print(f"     Win Rate: {ativo_win_rate:.1f}%")
                    print(f"     Lucro: ${stats['lucro']:.2f}")
            
            print("="*80 + "\n")
                
        except Exception as e:
            logging.error(f"❌ Erro ao exibir estatísticas: {e}")
    
    def monitorar_ativos(self):
        """Monitoramento principal"""
        logging.info("🤖 Iniciando monitoramento de ativos...")
        logging.info(f"📊 Ativos: {ATIVOS}")
        logging.info(f"💰 Valor entrada: ${VALOR_ENTRADA}")
        logging.info(f"⏰ Timeframe: M{TIMEFRAME}")
        logging.info("🎯 Estratégia: Fractal + Médias Móveis + RSI")
        
        ciclo = 0
        
        try:
            while True:
                ciclo += 1
                
                if ciclo % 5 == 0:
                    logging.info("🔍 Analisando ativos...")
                
                for ativo in ATIVOS:
                    try:
                        self.processar_ativo(ativo)
                        time.sleep(1)
                    except Exception as e:
                        logging.error(f"❌ Erro em {ativo}: {e}")
                        time.sleep(2)
                
                self.exibir_estatisticas()
                time.sleep(10)  # Verificar a cada 10 segundos
                
        except KeyboardInterrupt:
            logging.info("⏹️ Bot interrompido pelo usuário")
        except Exception as e:
            logging.error(f"💥 Erro fatal: {e}")
    
    def iniciar_bot(self):
        """Inicia o bot de trading"""
        logging.info("🤖 Iniciando IQ Option Bot com Estratégia Fractal")
        
        # Iniciar servidor HTTP em thread separada
        def run_server():
            uvicorn.run(self.app, host="0.0.0.0", port=5000, log_level="info")
        
        server_thread = threading.Thread(target=run_server, daemon=True)
        server_thread.start()
        logging.info("🌐 Servidor HTTP iniciado em http://0.0.0.0:5000")
        
        # Tentar conexão real, se falhar usar modo demo
        if not self.conectar_iq():
            logging.info("🔄 Usando modo demo com dados simulados")
            self.connected = True  # Forçar conexão para modo demo
        
        logging.info("🎯 Bot em execução. Pressione Ctrl+C para parar.")
        self.monitorar_ativos()

# Executar o bot
if __name__ == "__main__":
    bot = IQOptionBot()
    bot.iniciar_bot()