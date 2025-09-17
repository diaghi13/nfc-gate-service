#!/bin/bash

# Script di installazione per sistema tornello Raspberry Pi 4
set -e

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Funzioni di logging
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verifica che sia eseguito come root
if [ "$EUID" -ne 0 ]; then
    log_error "Questo script deve essere eseguito come root (sudo)"
    exit 1
fi

log_info "Inizio installazione sistema tornello..."

# Aggiorna il sistema
log_info "Aggiornamento sistema..."
apt update && apt upgrade -y

# Installa dipendenze di sistema
log_info "Installazione dipendenze di sistema..."
apt install -y \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    python3-setuptools \
    git \
    curl \
    vim \
    htop \
    build-essential \
    libssl-dev \
    libffi-dev \
    libjpeg-dev \
    zlib1g-dev

# Abilita SPI
log_info "Configurazione SPI..."
if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
    echo "dtparam=spi=on" >> /boot/config.txt
    log_info "SPI abilitato in /boot/config.txt"
fi

# Crea utente turnstile
log_info "Gestione utente turnstile..."
if ! id "turnstile" &>/dev/null; then
    useradd -m -s /bin/bash turnstile
    log_info "Utente turnstile creato"
else
    log_info "Utente turnstile già esistente"
fi

# Aggiungi ai gruppi necessari (anche se utente già esiste)
usermod -a -G gpio,spi turnstile
log_info "Utente turnstile aggiunto ai gruppi gpio e spi"

# Crea struttura directory
log_info "Creazione struttura directory..."
TURNSTILE_HOME="/home/turnstile"
mkdir -p $TURNSTILE_HOME/{app,logs,data,updates,backups}
chown -R turnstile:turnstile $TURNSTILE_HOME

# Determina directory sorgente
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")"

log_info "Script directory: $SCRIPT_DIR"
log_info "Source directory: $SOURCE_DIR"

# Copia file applicazione
log_info "Copia file applicazione..."
if [ -f "$SOURCE_DIR/main.py" ]; then
    # Copia tutti i file dalla directory principale
    cp -r "$SOURCE_DIR"/* "$TURNSTILE_HOME/app/" 2>/dev/null || true
    log_info "File copiati da: $SOURCE_DIR"
elif [ -d "$SOURCE_DIR/src" ]; then
    # Se i file sono in una sottodirectory src
    cp -r "$SOURCE_DIR"/* "$TURNSTILE_HOME/app/" 2>/dev/null || true
    log_info "File copiati da: $SOURCE_DIR"
else
    log_error "File sorgente non trovati. Assicurati che lo script sia nella directory del progetto"
    log_error "Directory corrente: $(pwd)"
    log_error "Script directory: $SCRIPT_DIR"
    log_error "Source directory: $SOURCE_DIR"
    exit 1
fi

# Imposta ownership corretti
chown -R turnstile:turnstile $TURNSTILE_HOME

# Crea virtual environment
log_info "Creazione virtual environment Python..."
sudo -u turnstile python3 -m venv $TURNSTILE_HOME/venv

# Installa dipendenze Python
log_info "Installazione dipendenze Python..."
if [ -f "$TURNSTILE_HOME/app/requirements.txt" ]; then
    sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install --upgrade pip
    sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install -r $TURNSTILE_HOME/app/requirements.txt
    log_info "Dipendenze Python installate"
else
    log_warn "File requirements.txt non trovato, installazione dipendenze base..."
    sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install --upgrade pip
    sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install RPi.GPIO==0.7.1 mfrc522==0.0.7 spidev==3.5 aiohttp==3.8.6 aiofiles==23.2.1 websockets==12.0 python-dotenv==1.0.0
fi

# Gestione file .env
log_info "Configurazione file .env..."
if [ -f "$TURNSTILE_HOME/app/.env.template" ]; then
    if [ ! -f "$TURNSTILE_HOME/app/.env" ]; then
        sudo -u turnstile cp "$TURNSTILE_HOME/app/.env.template" "$TURNSTILE_HOME/app/.env"
        log_info "File .env creato da template"
    else
        log_info "File .env già esistente, non sovrascritto"
    fi
else
    # Crea .env base se template non esiste
    log_warn "Template .env non trovato, creazione .env base..."
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
    log_info "File .env base creato"
fi

# Crea directory scripts se non esiste e copia script
log_info "Configurazione script di sistema..."
mkdir -p "$TURNSTILE_HOME/app/scripts"

# Crea script check_restart.sh se non esiste
if [ ! -f "$TURNSTILE_HOME/app/scripts/check_restart.sh" ]; then
    log_info "Creazione script check_restart.sh..."
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
    log_info "Script check_restart.sh creato"
fi

# Rendi eseguibili gli script
log_info "Impostazione permessi..."
chmod +x $TURNSTILE_HOME/app/main.py 2>/dev/null || true
chmod +x $TURNSTILE_HOME/app/scripts/*.sh 2>/dev/null || true
chown -R turnstile:turnstile $TURNSTILE_HOME

# Installa servizio systemd
log_info "Configurazione servizio systemd..."
if [ -f "$TURNSTILE_HOME/app/scripts/turnstile.service" ]; then
    cp "$TURNSTILE_HOME/app/scripts/turnstile.service" /etc/systemd/system/
    log_info "File servizio copiato da app/scripts/"
else
    # Crea servizio se non esiste
    log_info "Creazione file servizio systemd..."
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
fi

systemctl daemon-reload
systemctl enable turnstile.service
log_info "Servizio systemd configurato e abilitato"

# Crea file di versione se non esiste
if [ ! -f "$TURNSTILE_HOME/app/VERSION" ]; then
    echo "1.0.0" > $TURNSTILE_HOME/app/VERSION
    chown turnstile:turnstile $TURNSTILE_HOME/app/VERSION
fi

# Configurazione logrotate
log_info "Configurazione logrotate..."
cat > /etc/logrotate.d/turnstile << 'EOF'
/home/turnstile/logs/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 turnstile turnstile
    postrotate
        systemctl reload turnstile || true
    endscript
}
EOF

# Configurazione cron per pulizia automatica
log_info "Configurazione cron jobs..."
sudo -u turnstile crontab -l > /tmp/crontab_turnstile 2>/dev/null || true
if ! grep -q "cleanup_logs" /tmp/crontab_turnstile 2>/dev/null; then
    echo "0 2 * * * /home/turnstile/app/scripts/cleanup_logs.sh" >> /tmp/crontab_turnstile
fi
if ! grep -q "backup_data" /tmp/crontab_turnstile 2>/dev/null; then
    echo "0 3 * * 0 /home/turnstile/app/scripts/backup_data.sh" >> /tmp/crontab_turnstile
fi
sudo -u turnstile crontab /tmp/crontab_turnstile
rm -f /tmp/crontab_turnstile

# Configurazione rete (se necessario)
log_info "Configurazione di rete..."
# Disabilita WiFi power management per stabilità
if command -v iw &> /dev/null; then
    echo 'iw wlan0 set power_save off' >> /etc/rc.local
fi

# Test configurazione hardware
log_info "Test configurazione hardware..."
python3 -c "
import RPi.GPIO as GPIO
try:
    GPIO.setmode(GPIO.BCM)
    print('GPIO: OK')
    GPIO.cleanup()
except Exception as e:
    print(f'GPIO Error: {e}')
"

# Controlla SPI
if [ -e "/dev/spidev0.0" ]; then
    log_info "SPI: OK"
else
    log_warn "SPI: Dispositivo non trovato, riavvio necessario"
fi

log_info "Installazione completata!"
log_info ""
log_info "Passi successivi:"
log_info "1. Modifica /home/turnstile/app/.env con la tua configurazione"
log_info "2. Riavvia il Raspberry Pi per applicare le modificazioni hardware"
log_info "3. Testa l'installazione con: sudo systemctl start turnstile"
log_info "4. Controlla i log con: sudo journalctl -u turnstile -f"
log_info "5. Per modalità test, modifica ENVIRONMENT=test nel file .env"
log_info ""
log_warn "RIAVVIO NECESSARIO per applicare le configurazioni hardware!"

exit 0