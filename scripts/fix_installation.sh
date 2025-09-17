#!/bin/bash

# Script per correggere problemi comuni post-installazione

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

TURNSTILE_HOME="/home/turnstile"

# Verifica permessi root
if [ "$EUID" -ne 0 ]; then
    log_error "Questo script deve essere eseguito come root (sudo)"
    exit 1
fi

log_info "Verifica e correzione installazione..."

# 1. Verifica utente turnstile
log_info "Verifica utente turnstile..."
if ! id "turnstile" &>/dev/null; then
    log_warn "Utente turnstile non trovato, creazione..."
    useradd -m -s /bin/bash turnstile
fi
usermod -a -G gpio,spi turnstile
log_info "Utente turnstile OK"

# 2. Verifica e crea struttura directory
log_info "Verifica struttura directory..."
mkdir -p $TURNSTILE_HOME/{app,logs,data,updates,backups,app/scripts,app/src}
chown -R turnstile:turnstile $TURNSTILE_HOME
log_info "Directory create"

# 3. Verifica virtual environment
log_info "Verifica virtual environment..."
if [ ! -d "$TURNSTILE_HOME/venv" ]; then
    log_warn "Virtual environment mancante, creazione..."
    sudo -u turnstile python3 -m venv $TURNSTILE_HOME/venv
    sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install --upgrade pip
fi
log_info "Virtual environment OK"

# 4. Crea file .env se mancante
if [ ! -f "$TURNSTILE_HOME/app/.env" ]; then
    log_warn "File .env mancante, creazione..."
    cat > "$TURNSTILE_HOME/app/.env" << 'EOF'
# Configurazione base tornello
DEVICE_ID=turnstile_001
DEVICE_TYPE=turnstile
ENVIRONMENT=production
BACKEND_URL=https://api.example.com
API_KEY=your_api_key_here
WEBSOCKET_URL=wss://api.example.com/ws
NFC_READER_IN_RST=22
NFC_READER_OUT_RST=24
RELAY_CHANNEL_1=18
RELAY_CHANNEL_2=19
SPI_BUS_IN=0
SPI_DEVICE_IN=0
SPI_BUS_OUT=0
SPI_DEVICE_OUT=1
RELAY_OPEN_DURATION=3.0
NFC_READ_TIMEOUT=5.0
CONNECTION_TIMEOUT=10.0
FALLBACK_MODE_ENABLED=true
MAX_OFFLINE_LOGS=1000
LOG_LEVEL=INFO
LOG_FILE=/home/turnstile/logs/turnstile.log
LOG_MAX_SIZE=10485760
LOG_BACKUP_COUNT=5
AUTO_UPDATE_ENABLED=true
UPDATE_CHECK_INTERVAL=3600
UPDATE_ENDPOINT=https://api.example.com/updates
WHITELIST_FILE=/home/turnstile/data/whitelist.json
OFFLINE_LOGS_FILE=/home/turnstile/data/offline_logs.json
EOF
    chown turnstile:turnstile "$TURNSTILE_HOME/app/.env"
    log_info "File .env creato"
fi

# 5. Crea script check_restart.sh se mancante
if [ ! -f "$TURNSTILE_HOME/app/scripts/check_restart.sh" ]; then
    log_warn "Script check_restart.sh mancante, creazione..."
    cat > "$TURNSTILE_HOME/app/scripts/check_restart.sh" << 'EOF'
#!/bin/bash
RESTART_FILE="/home/turnstile/data/restart_required"
LOG_FILE="/home/turnstile/logs/service.log"

log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

if [ -f "$RESTART_FILE" ]; then
    log_message "Riavvio richiesto dopo aggiornamento, rimozione flag"
    rm "$RESTART_FILE"
    sleep 5
    log_message "Proseguimento con avvio servizio"
fi

exit 0
EOF
    chmod +x "$TURNSTILE_HOME/app/scripts/check_restart.sh"
    chown turnstile:turnstile "$TURNSTILE_HOME/app/scripts/check_restart.sh"
    log_info "Script check_restart.sh creato"
fi

# 6. Crea main.py base se mancante
if [ ! -f "$TURNSTILE_HOME/app/main.py" ]; then
    log_warn "main.py mancante, creazione versione base..."
    cat > "$TURNSTILE_HOME/app/main.py" << 'EOF'
#!/usr/bin/env python3
"""
Sistema di controllo tornello bidirezionale - Versione base
"""

import asyncio
import logging
import sys
import time
from pathlib import Path

# Setup logging base
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

logger = logging.getLogger(__name__)

async def main():
    """Funzione principale base"""
    logger.info("Sistema tornello avviato (versione base)")
    logger.warning("ATTENZIONE: Questa è una versione base di fallback")
    logger.warning("Installare i moduli completi per funzionalità complete")
    
    # Loop base
    try:
        while True:
            logger.info("Sistema in esecuzione...")
            await asyncio.sleep(30)
    except KeyboardInterrupt:
        logger.info("Arresto sistema...")

if __name__ == "__main__":
    asyncio.run(main())
EOF
    chmod +x "$TURNSTILE_HOME/app/main.py"
    chown turnstile:turnstile "$TURNSTILE_HOME/app/main.py"
    log_info "main.py base creato"
fi

# 7. Verifica servizio systemd
log_info "Verifica servizio systemd..."
if [ ! -f "/etc/systemd/system/turnstile.service" ]; then
    log_warn "File servizio mancante, creazione..."
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
ExecStart=/home/turnstile/venv/bin/python /home/turnstile/app/main.py
ExecStartPre=/home/turnstile/app/scripts/check_restart.sh
ExecReload=/bin/kill -HUP $MAINPID
Restart=always
RestartSec=10

# Limiti di risorse
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
    systemctl daemon-reload
    systemctl enable turnstile.service
    log_info "Servizio systemd ricreato"
fi

# 8. Crea file VERSION
if [ ! -f "$TURNSTILE_HOME/app/VERSION" ]; then
    echo "1.0.0" > "$TURNSTILE_HOME/app/VERSION"
    chown turnstile:turnstile "$TURNSTILE_HOME/app/VERSION"
    log_info "File VERSION creato"
fi

# 9. Crea file dati vuoti
touch "$TURNSTILE_HOME/data/whitelist.json"
touch "$TURNSTILE_HOME/data/offline_logs.json"
echo "[]" > "$TURNSTILE_HOME/data/whitelist.json"
echo "[]" > "$TURNSTILE_HOME/data/offline_logs.json"
chown turnstile:turnstile "$TURNSTILE_HOME/data"/*.json

# 10. Imposta tutti i permessi
chown -R turnstile:turnstile $TURNSTILE_HOME
chmod +x "$TURNSTILE_HOME/app/main.py" 2>/dev/null || true
chmod +x "$TURNSTILE_HOME/app/scripts"/*.sh 2>/dev/null || true

# 11. Test finale
log_info "Test configurazione..."

# Test utente
if sudo -u turnstile whoami >/dev/null 2>&1; then
    log_info "✓ Utente turnstile OK"
else
    log_error "✗ Problema con utente turnstile"
fi

# Test virtual environment
if sudo -u turnstile $TURNSTILE_HOME/venv/bin/python --version >/dev/null 2>&1; then
    log_info "✓ Virtual environment OK"
else
    log_error "✗ Problema con virtual environment"
fi

# Test script principale
if [ -x "$TURNSTILE_HOME/app/main.py" ]; then
    log_info "✓ main.py eseguibile"
else
    log_error "✗ main.py non eseguibile"
fi

# Test servizio
if systemctl is-enabled turnstile >/dev/null 2>&1; then
    log_info "✓ Servizio abilitato"
else
    log_error "✗ Servizio non abilitato"
fi

log_info "Correzioni completate!"
log_info ""
log_info "Prossimi passi:"
log_info "1. Modifica /home/turnstile/app/.env con la tua configurazione"
log_info "2. Installa i moduli Python completi se necessario"
log_info "3. Testa il servizio: sudo systemctl start turnstile"
log_info "4. Controlla i log: sudo journalctl -u turnstile -f"

exit 0