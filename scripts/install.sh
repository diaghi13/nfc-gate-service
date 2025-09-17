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
log_info "Creazione utente turnstile..."
if ! id "turnstile" &>/dev/null; then
    useradd -m -s /bin/bash turnstile
    usermod -a -G gpio,spi turnstile
    log_info "Utente turnstile creato e aggiunto ai gruppi gpio e spi"
else
    log_info "Utente turnstile già esistente"
fi

# Crea struttura directory
log_info "Creazione struttura directory..."
TURNSTILE_HOME="/home/turnstile"
sudo -u turnstile mkdir -p $TURNSTILE_HOME/{app,logs,data,updates,backups}

# Crea virtual environment
log_info "Creazione virtual environment Python..."
sudo -u turnstile python3 -m venv $TURNSTILE_HOME/venv

# Copia file applicazione se presenti
if [ -d "$(dirname $0)/../src" ]; then
    log_info "Copia file applicazione..."
    cp -r $(dirname $0)/../* $TURNSTILE_HOME/app/
    chown -R turnstile:turnstile $TURNSTILE_HOME/app
fi

# Installa dipendenze Python
if [ -f "$TURNSTILE_HOME/app/requirements.txt" ]; then
    log_info "Installazione dipendenze Python..."
    sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install --upgrade pip
    sudo -u turnstile $TURNSTILE_HOME/venv/bin/pip install -r $TURNSTILE_HOME/app/requirements.txt
fi

# Copia template .env se non esiste
if [ -f "$TURNSTILE_HOME/app/.env.template" ] && [ ! -f "$TURNSTILE_HOME/app/.env" ]; then
    log_info "Copia template configurazione..."
    sudo -u turnstile cp $TURNSTILE_HOME/app/.env.template $TURNSTILE_HOME/app/.env
    log_warn "IMPORTANTE: Modifica il file $TURNSTILE_HOME/app/.env con la tua configurazione"
fi

# Rendi eseguibili gli script
log_info "Impostazione permessi script..."
chmod +x $TURNSTILE_HOME/app/scripts/*.sh
chmod +x $TURNSTILE_HOME/app/main.py

# Installa servizio systemd
log_info "Installazione servizio systemd..."
cp $TURNSTILE_HOME/app/scripts/turnstile.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable turnstile.service

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