#!/bin/bash

# Script di installazione semplificata con gestione errori

set -e  # Exit on error

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Funzione di pulizia in caso di errore
cleanup_on_error() {
    log_error "Errore durante l'installazione alla linea $1"
    log_info "Esecuzione script di correzione automatica..."
    if [ -f "/tmp/fix_installation.sh" ]; then
        bash /tmp/fix_installation.sh
    fi
    exit 1
}

# Trap per errori
trap 'cleanup_on_error $LINENO' ERR

# Verifica root
if [ "$EUID" -ne 0 ]; then
    log_error "Esegui come root: sudo $0"
    exit 1
fi

log_info "=== INSTALLAZIONE SISTEMA TORNELLO RASPBERRY PI ==="
log_info "Versione semplificata con correzione automatica errori"
echo ""

# Step 1: Aggiornamento sistema
log_step "1/10 Aggiornamento sistema..."
apt update -qq && apt upgrade -y -qq

# Step 2: Installazione pacchetti
log_step "2/10 Installazione dipendenze sistema..."
apt install -y -qq \
    python3 python3-pip python3-venv python3-dev \
    git curl vim build-essential \
    libssl-dev libffi-dev || log_warn "Alcuni pacchetti potrebbero essere già installati"

# Step 3: Configurazione hardware
log_step "3/10 Configurazione hardware..."
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    echo "dtparam=spi=on" >> /boot/config.txt
    log_info "SPI abilitato"
fi

# Step 4: Gestione utente
log_step "4/10 Configurazione utente turnstile..."
if ! id "turnstile" &>/dev/null; then
    useradd -m -s /bin/bash turnstile
    log_info "Utente turnstile creato"
else
    log_info "Utente turnstile già esistente"
fi

# Aggiungi sempre ai gruppi (non fa male se già presente)
usermod -a -G gpio,spi turnstile 2>/dev/null || true
log_info "Utente aggiunto ai gruppi"

# Step 5: Struttura directory
log_step "5/10 Creazione directory..."
TURNSTILE_HOME="/home/turnstile"
mkdir -p $TURNSTILE_HOME/{app,logs,data,updates,backups,app/src,app/scripts}
chown -R turnstile:turnstile $TURNSTILE_HOME
log_info "Directory create"

# Step 6: Virtual environment
log_step "6/10 Configurazione Python..."
if [ ! -d "$TURNSTILE_HOME/venv" ]; then
    sudo -u turnstile python3 -m venv $TURNSTILE_HOME/venv
    log_info "Virtual environment creato"
fi
sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install --upgrade pip -q

# Step 7: Copia file o crea base
log_step "7/10 Configurazione file applicazione..."

# Trova directory sorgente
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"

# Copia file se presenti, altrimenti crea struttura base
if [ -f "$SOURCE_DIR/main.py" ] || [ -f "$SOURCE_DIR/src/config.py" ]; then
    log_info "Copia file da: $SOURCE_DIR"
    cp -r "$SOURCE_DIR"/* "$TURNSTILE_HOME/app/" 2>/dev/null || true
    chown -R turnstile:turnstile "$TURNSTILE_HOME/app"
    log_info "File copiati"
else
    log_warn "File sorgente non trovati, creazione struttura minima..."
    # Crea main.py base se non esiste
    if [ ! -f "$TURNSTILE_HOME/app/main.py" ]; then
        cat > "$TURNSTILE_HOME/app/main.py" << 'EOF'
#!/usr/bin/env python3
"""
Sistema di controllo tornello bidirezionale - Versione base
Per installazione completa, copia i file del progetto completo
"""

import asyncio
import logging
import sys
from pathlib import Path

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

class BasicTurnstileSystem:
    def __init__(self):
        self.running = False
        
    async def start(self):
        """Avvia sistema base"""
        logger.info("Sistema tornello BASE avviato")
        logger.warning("VERSIONE BASE - Per funzionalità complete installare i moduli")
        logger.info("File .env: /home/turnstile/app/.env")
        logger.info("Per modalità test: /home/turnstile/app/scripts/test_mode.sh test")
        
        self.running = True
        try:
            while self.running:
                logger.info("Sistema in esecuzione... (versione base)")
                await asyncio.sleep(60)
        except KeyboardInterrupt:
            logger.info("Arresto richiesto")
        finally:
            await self.stop()
    
    async def stop(self):
        """Arresta sistema"""
        self.running = False
        logger.info("Sistema arrestato")

async def main():
    """Funzione principale"""
    system = BasicTurnstileSystem()
    try:
        await system.start()
    except Exception as e:
        logger.error(f"Errore: {e}")
    finally:
        await system.stop()

if __name__ == "__main__":
    asyncio.run(main())
EOF
        chmod +x "$TURNSTILE_HOME/app/main.py"
        log_info "main.py base creato"
    fi
    
    # Crea VERSION
    echo "1.0.0" > "$TURNSTILE_HOME/app/VERSION"
    
    # Crea requirements.txt base
    cat > "$TURNSTILE_HOME/app/requirements.txt" << 'EOF'
RPi.GPIO==0.7.1
mfrc522==0.0.7
spidev==3.5
aiohttp==3.8.6
aiofiles==23.2.1
websockets==12.0
python-dotenv==1.0.0
EOF
    
    log_info "File base creati"
fi

# Step 8: File configurazione
log_step "8/10 Configurazione .env..."
if [ ! -f "$TURNSTILE_HOME/app/.env" ]; then
    cat > "$TURNSTILE_HOME/app/.env" << 'EOF'
# Configurazione Sistema Tornello
# IMPORTANTE: Modifica questi valori per la tua installazione

# IDENTIFICAZIONE DISPOSITIVO
DEVICE_ID=turnstile_001
DEVICE_TYPE=turnstile
ENVIRONMENT=production

# BACKEND (MODIFICA CON I TUOI VALORI)
BACKEND_URL=https://api.example.com
API_KEY=your_api_key_here
WEBSOCKET_URL=wss://api.example.com/ws

# HARDWARE - LETTORI NFC
NFC_READER_IN_RST=22
NFC_READER_OUT_RST=24

# HARDWARE - RELÈ
RELAY_CHANNEL_1=18
RELAY_CHANNEL_2=19

# SPI CONFIGURATION
SPI_BUS_IN=0
SPI_DEVICE_IN=0
SPI_BUS_OUT=0
SPI_DEVICE_OUT=1

# TIMING
RELAY_OPEN_DURATION=3.0
NFC_READ_TIMEOUT=5.0
CONNECTION_TIMEOUT=10.0

# MODALITÀ OFFLINE
FALLBACK_MODE_ENABLED=true
MAX_OFFLINE_LOGS=1000

# LOGGING
LOG_LEVEL=INFO
LOG_FILE=/home/turnstile/logs/turnstile.log
LOG_MAX_SIZE=10485760
LOG_BACKUP_COUNT=5

# AGGIORNAMENTI
AUTO_UPDATE_ENABLED=true
UPDATE_CHECK_INTERVAL=3600
UPDATE_ENDPOINT=https://api.example.com/updates

# FILE LOCALI
WHITELIST_FILE=/home/turnstile/data/whitelist.json
OFFLINE_LOGS_FILE=/home/turnstile/data/offline_logs.json
EOF
    chown turnstile:turnstile "$TURNSTILE_HOME/app/.env"
    log_info "File .env creato"
else
    log_info "File .env già esistente"
fi

# Step 9: Script di sistema
log_step "9/10 Script di sistema..."
# Script check_restart.sh
cat > "$TURNSTILE_HOME/app/scripts/check_restart.sh" << 'EOF'
#!/bin/bash
RESTART_FILE="/home/turnstile/data/restart_required"
LOG_FILE="/home/turnstile/logs/service.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Crea directory log se non esiste
mkdir -p "$(dirname "$LOG_FILE")"

if [ -f "$RESTART_FILE" ]; then
    log_message "Riavvio richiesto dopo aggiornamento, rimozione flag"
    rm "$RESTART_FILE"
    sleep 5
    log_message "Proseguimento con avvio servizio"
fi

exit 0
EOF

# Script test_mode.sh
cat > "$TURNSTILE_HOME/app/scripts/test_mode.sh" << 'EOF'
#!/bin/bash
ENV_FILE="/home/turnstile/app/.env"
SERVICE_NAME="turnstile"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

get_current_mode() {
    if [ -f "$ENV_FILE" ]; then
        grep "^ENVIRONMENT=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'"
    else
        echo "unknown"
    fi
}

show_status() {
    echo "=== STATUS SISTEMA TORNELLO ==="
    echo "Modalità: $(get_current_mode)"
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "Servizio: ${GREEN}ATTIVO${NC}"
    else
        echo -e "Servizio: ${RED}INATTIVO${NC}"
    fi
    
    if [ -f "$ENV_FILE" ]; then
        echo "Device ID: $(grep "^DEVICE_ID=" "$ENV_FILE" | cut -d'=' -f2)"
        echo "Device Type: $(grep "^DEVICE_TYPE=" "$ENV_FILE" | cut -d'=' -f2)"
    fi
    
    echo ""
    echo "=== TEST HARDWARE ==="
    echo -n "GPIO: "
    if python3 -c "import RPi.GPIO as GPIO; GPIO.setmode(GPIO.BCM); GPIO.cleanup()" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}ERRORE${NC}"
    fi
    
    echo -n "SPI: "
    if [ -e "/dev/spidev0.0" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}Riavvio necessario${NC}"
    fi
    
    echo -n "Connettività: "
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}ERRORE${NC}"
    fi
}

set_mode() {
    local mode=$1
    if [ ! -f "$ENV_FILE" ]; then
        log_error "File .env non trovato"
        exit 1
    fi
    
    cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%s)"
    
    if grep -q "^ENVIRONMENT=" "$ENV_FILE"; then
        sed -i "s/^ENVIRONMENT=.*/ENVIRONMENT=$mode/" "$ENV_FILE"
    else
        echo "ENVIRONMENT=$mode" >> "$ENV_FILE"
    fi
    
    log_info "Modalità cambiata a: $mode"
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_info "Riavvio servizio..."
        sudo systemctl restart $SERVICE_NAME
    fi
}

case "${1:-status}" in
    "test")
        set_mode "test"
        log_warn "MODALITÀ TEST ATTIVA - Hardware simulato"
        ;;
    "production")
        set_mode "production"
        log_info "MODALITÀ PRODUZIONE ATTIVA"
        ;;
    "status")
        show_status
        ;;
    *)
        echo "Usage: $0 [test|production|status]"
        exit 1
        ;;
esac
EOF

chmod +x "$TURNSTILE_HOME/app/scripts"/*.sh
chown -R turnstile:turnstile "$TURNSTILE_HOME/app/scripts"
log_info "Script di sistema creati"

# Step 10: Servizio systemd
log_step "10/10 Configurazione servizio..."
cat > /etc/systemd/system/turnstile.service << 'EOF'
[Unit]
Description=Sistema Controllo Tornello
After=network.target
Wants=network.target

[Service]
Type=simple
User=turnstile
Group=gpio
WorkingDirectory=/home/turnstile/app
Environment=PYTHONPATH=/home/turnstile/app
ExecStartPre=/home/turnstile/app/scripts/check_restart.sh
ExecStart=/home/turnstile/venv/bin/python /home/turnstile/app/main.py
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10

# Limiti risorse
MemoryLimit=256M
CPUQuota=50%

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=turnstile

# Sicurezza
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/home/turnstile
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF

log_info "Servizio systemd configurato"

# Installazione dipendenze Python
log_info "Installazione dipendenze Python..."
if [ -f "$TURNSTILE_HOME/app/requirements.txt" ]; then
    sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install -r "$TURNSTILE_HOME/app/requirements.txt" -q
else
    sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install \
        RPi.GPIO==0.7.1 mfrc522==0.0.7 spidev==3.5 \
        aiohttp==3.8.6 aiofiles==23.2.1 websockets==12.0 \
        python-dotenv==1.0.0 -q
fi

# Permessi finali
log_info "Impostazione permessi finali..."
chown -R turnstile:turnstile $TURNSTILE_HOME
chmod +x "$TURNSTILE_HOME/app/main.py" 2>/dev/null || true
chmod +x "$TURNSTILE_HOME/app/scripts"/*.sh 2>/dev/null || true

# Abilitazione servizio
systemctl daemon-reload
systemctl enable turnstile.service

log_info ""
log_info "=== INSTALLAZIONE COMPLETATA CON SUCCESSO! ==="
log_info ""
log_info "PASSI SUCCESSIVI:"
log_info "1. Modifica configurazione: nano /home/turnstile/app/.env"
log_info "2. Riavvia per hardware: sudo reboot"
log_info "3. Avvia servizio: sudo systemctl start turnstile"
log_info "4. Controlla log: sudo journalctl -u turnstile -f"
log_info "5. Test sistema: /home/turnstile/app/scripts/test_mode.sh status"
log_info ""
log_warn "RIAVVIO NECESSARIO per applicare configurazioni hardware!"

exit 0