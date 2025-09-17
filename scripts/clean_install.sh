#!/bin/bash

# ====================================================================
# SCRIPT INSTALLAZIONE PULITA SISTEMA TURNSTILE - VERSIONE DEFINITIVA
# Testato su Raspberry Pi OS Lite - Gennaio 2025
# ====================================================================

set -e  # Exit on any error

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Funzioni di logging
print_header() {
    echo -e "\n${BLUE}${BOLD}=== $1 ===${NC}\n"
}

print_step() {
    echo -e "${GREEN}[STEP $1/12]${NC} $2"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Verifica prerequisiti
check_prerequisites() {
    print_header "VERIFICA PREREQUISITI"
    
    # Root check
    if [ "$EUID" -ne 0 ]; then
        print_error "Esegui come root: sudo $0"
        exit 1
    fi
    
    # Sistema check
    if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
        print_warning "Non sembra un Raspberry Pi, continuo comunque..."
    fi
    
    # Connessione internet
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        print_warning "Connessione internet non disponibile, alcuni pacchetti potrebbero fallire"
    fi
    
    print_success "Prerequisiti verificati"
}

# Pulizia sistema precedente
cleanup_previous() {
    print_header "PULIZIA INSTALLAZIONE PRECEDENTE"
    
    # Ferma servizi esistenti
    systemctl stop turnstile 2>/dev/null || true
    systemctl disable turnstile 2>/dev/null || true
    
    # Rimuovi servizio systemd
    rm -f /etc/systemd/system/turnstile.service
    systemctl daemon-reload
    
    # Backup configurazione se esiste
    if [ -f "/home/turnstile/app/.env" ]; then
        cp /home/turnstile/app/.env /tmp/turnstile_env_backup_$(date +%s) 2>/dev/null || true
        print_info "Backup .env salvato in /tmp/"
    fi
    
    # Rimuovi directory (mantieni solo backup)
    rm -rf /home/turnstile
    
    print_success "Pulizia completata"
}

# Aggiornamento sistema
update_system() {
    print_step "1" "Aggiornamento sistema"
    
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get upgrade -y -qq
    
    print_success "Sistema aggiornato"
}

# Installazione pacchetti
install_packages() {
    print_step "2" "Installazione pacchetti di sistema"
    
    apt-get install -y -qq \
        python3 \
        python3-pip \
        python3-venv \
        python3-dev \
        python3-setuptools \
        git \
        curl \
        vim \
        build-essential \
        libssl-dev \
        libffi-dev
    
    print_success "Pacchetti installati"
}

# Configurazione hardware
setup_hardware() {
    print_step "3" "Configurazione hardware"
    
    # Abilita SPI
    if ! grep -q "^dtparam=spi=on" /boot/config.txt; then
        echo "dtparam=spi=on" >> /boot/config.txt
        print_info "SPI abilitato in /boot/config.txt"
    else
        print_info "SPI già abilitato"
    fi
    
    print_success "Hardware configurato (riavvio necessario per applicare)"
}

# Creazione utente
create_user() {
    print_step "4" "Configurazione utente turnstile"
    
    # Crea utente se non esiste
    if ! id "turnstile" &>/dev/null; then
        useradd -m -s /bin/bash turnstile
        print_info "Utente turnstile creato"
    else
        print_info "Utente turnstile già esistente"
    fi
    
    # Aggiungi ai gruppi necessari
    usermod -a -G gpio,spi turnstile 2>/dev/null || true
    
    print_success "Utente configurato"
}

# Creazione struttura directory
create_directories() {
    print_step "5" "Creazione struttura directory"
    
    # Crea tutte le directory necessarie
    mkdir -p /home/turnstile/{app,logs,data,updates,backups}
    mkdir -p /home/turnstile/app/{src,scripts}
    
    # Imposta ownership
    chown -R turnstile:turnstile /home/turnstile
    
    # Verifica creazione
    if [ -d "/home/turnstile/app" ]; then
        print_success "Struttura directory creata"
    else
        print_error "Errore nella creazione directory"
        exit 1
    fi
}

# Setup Python
setup_python() {
    print_step "6" "Configurazione ambiente Python"
    
    # Crea virtual environment
    sudo -u turnstile python3 -m venv /home/turnstile/venv
    
    # Verifica creazione
    if [ -f "/home/turnstile/venv/bin/python" ]; then
        print_info "Virtual environment creato"
    else
        print_error "Errore nella creazione virtual environment"
        exit 1
    fi
    
    # Aggiorna pip
    sudo -u turnstile /home/turnstile/venv/bin/pip install --upgrade pip -q
    
    # Installa dipendenze base
    sudo -u turnstile /home/turnstile/venv/bin/pip install -q \
        RPi.GPIO==0.7.1 \
        mfrc522==0.0.7 \
        spidev==3.5 \
        aiohttp==3.8.6 \
        aiofiles==23.2.1 \
        websockets==12.0 \
        python-dotenv==1.0.0
    
    print_success "Ambiente Python configurato"
}

# Creazione file applicazione
create_application_files() {
    print_step "7" "Creazione file applicazione"
    
    # main.py
    cat > /home/turnstile/app/main.py << 'EOF'
#!/usr/bin/env python3
"""
Sistema Controllo Turnstile/Porta - Versione Base
Per versione completa, sostituire con i moduli del progetto
"""

import asyncio
import logging
import signal
import sys
from pathlib import Path
import os

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/home/turnstile/logs/turnstile.log'),
        logging.StreamHandler()
    ]
)

logger = logging.getLogger(__name__)

class TurnstileSystem:
    def __init__(self):
        self.running = False
        self.load_config()
    
    def load_config(self):
        """Carica configurazione da .env"""
        from dotenv import load_dotenv
        load_dotenv('/home/turnstile/app/.env')
        
        self.device_id = os.getenv('DEVICE_ID', 'turnstile_001')
        self.device_type = os.getenv('DEVICE_TYPE', 'turnstile')
        self.environment = os.getenv('ENVIRONMENT', 'production')
        
        logger.info(f"Configurazione caricata: {self.device_id} ({self.device_type}) [{self.environment}]")
    
    def setup_signal_handlers(self):
        """Configura gestione segnali"""
        def signal_handler(signum, frame):
            logger.info(f"Ricevuto segnale {signum}, arresto sistema...")
            self.running = False
        
        signal.signal(signal.SIGINT, signal_handler)
        signal.signal(signal.SIGTERM, signal_handler)
    
    async def start(self):
        """Avvia sistema"""
        logger.info("=== AVVIO SISTEMA TURNSTILE ===")
        logger.info(f"Device: {self.device_id}")
        logger.info(f"Tipo: {self.device_type}")
        logger.info(f"Modalità: {self.environment}")
        
        if self.environment == 'test':
            logger.warning("MODALITÀ TEST - Hardware simulato")
        else:
            logger.info("MODALITÀ PRODUZIONE - Hardware reale")
        
        self.setup_signal_handlers()
        self.running = True
        
        try:
            counter = 0
            while self.running:
                counter += 1
                if counter % 10 == 0:  # Log ogni 5 minuti
                    logger.info(f"Sistema operativo da {counter//2} minuti")
                
                if self.environment == 'test':
                    # Simula attività in modalità test
                    if counter % 60 == 0:  # Ogni 30 minuti
                        logger.info("Simulazione lettura card di test")
                
                await asyncio.sleep(30)  # 30 secondi
                
        except Exception as e:
            logger.error(f"Errore durante esecuzione: {e}")
        finally:
            await self.stop()
    
    async def stop(self):
        """Arresta sistema"""
        self.running = False
        logger.info("Sistema arrestato correttamente")

async def main():
    """Funzione principale"""
    # Crea directory log se non esiste
    Path('/home/turnstile/logs').mkdir(exist_ok=True)
    
    system = TurnstileSystem()
    try:
        await system.start()
    except KeyboardInterrupt:
        logger.info("Interruzione da tastiera")
    except Exception as e:
        logger.error(f"Errore fatale: {e}")
        sys.exit(1)

if __name__ == "__main__":
    asyncio.run(main())
EOF
    
    # Rendi eseguibile
    chmod +x /home/turnstile/app/main.py
    
    print_success "main.py creato"
}

# Creazione file configurazione
create_config_files() {
    print_step "8" "Creazione file di configurazione"
    
    # .env
    cat > /home/turnstile/app/.env << 'EOF'
# ===============================
# SISTEMA CONTROLLO TURNSTILE
# ===============================

# Identificazione dispositivo
DEVICE_ID=turnstile_001
DEVICE_TYPE=turnstile
ENVIRONMENT=production

# Backend (MODIFICA CON I TUOI VALORI)
BACKEND_URL=https://api.example.com
API_KEY=your_api_key_here
WEBSOCKET_URL=wss://api.example.com/ws

# Hardware - Lettori NFC
NFC_READER_IN_RST=22
NFC_READER_OUT_RST=24

# Hardware - Relè
RELAY_CHANNEL_1=18
RELAY_CHANNEL_2=19

# Configurazione SPI
SPI_BUS_IN=0
SPI_DEVICE_IN=0
SPI_BUS_OUT=0
SPI_DEVICE_OUT=1

# Timing
RELAY_OPEN_DURATION=3.0
NFC_READ_TIMEOUT=5.0
CONNECTION_TIMEOUT=10.0

# Modalità offline
FALLBACK_MODE_ENABLED=true
MAX_OFFLINE_LOGS=1000

# Logging
LOG_LEVEL=INFO
LOG_FILE=/home/turnstile/logs/turnstile.log
LOG_MAX_SIZE=10485760
LOG_BACKUP_COUNT=5

# Aggiornamenti
AUTO_UPDATE_ENABLED=true
UPDATE_CHECK_INTERVAL=3600
UPDATE_ENDPOINT=https://api.example.com/updates

# File locali
WHITELIST_FILE=/home/turnstile/data/whitelist.json
OFFLINE_LOGS_FILE=/home/turnstile/data/offline_logs.json
EOF
    
    # requirements.txt
    cat > /home/turnstile/app/requirements.txt << 'EOF'
RPi.GPIO==0.7.1
mfrc522==0.0.7
spidev==3.5
aiohttp==3.8.6
aiofiles==23.2.1
websockets==12.0
python-dotenv==1.0.0
EOF
    
    # VERSION
    echo "1.0.0" > /home/turnstile/app/VERSION
    
    print_success "File di configurazione creati"
}

# Creazione script di utilità
create_utility_scripts() {
    print_step "9" "Creazione script di utilità"
    
    # Script test_mode.sh
    cat > /home/turnstile/app/scripts/test_mode.sh << 'EOF'
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
    echo ""
    echo "=== STATUS SISTEMA TURNSTILE ==="
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
    
    echo -n "Python venv: "
    if /home/turnstile/venv/bin/python --version >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}ERRORE${NC}"
    fi
    
    echo ""
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
        sleep 3
        if systemctl is-active --quiet $SERVICE_NAME; then
            log_info "Servizio riavviato con successo"
        else
            log_error "Errore nel riavvio servizio"
        fi
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
        echo ""
        echo "test       - Attiva modalità test (hardware simulato)"
        echo "production - Attiva modalità produzione (hardware reale)"
        echo "status     - Mostra status del sistema"
        exit 1
        ;;
esac
EOF
    
    chmod +x /home/turnstile/app/scripts/test_mode.sh
    
    print_success "Script di utilità creati"
}

# Creazione servizio systemd
create_systemd_service() {
    print_step "10" "Configurazione servizio systemd"
    
    # Servizio SEMPLICE e FUNZIONANTE
    cat > /etc/systemd/system/turnstile.service << 'EOF'
[Unit]
Description=Sistema Controllo Turnstile/Porta
Documentation=https://github.com/your-username/turnstile-system
After=network.target
Wants=network.target

[Service]
Type=simple
User=turnstile
Group=gpio
WorkingDirectory=/home/turnstile/app
Environment=PYTHONPATH=/home/turnstile/app
Environment=PYTHONUNBUFFERED=1
ExecStart=/home/turnstile/venv/bin/python /home/turnstile/app/main.py
ExecReload=/bin/kill -HUP $MAINPID

# Restart policy
Restart=always
RestartSec=10
StartLimitInterval=60
StartLimitBurst=3

# Resource limits
MemoryLimit=256M
CPUQuota=50%

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=turnstile

# Security settings
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/home/turnstile
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
    
    print_success "Servizio systemd creato"
}

# Finalizzazione
finalize_installation() {
    print_step "11" "Finalizzazione installazione"
    
    # Imposta ownership corretti
    chown -R turnstile:turnstile /home/turnstile
    
    # Crea file dati vuoti
    echo "[]" > /home/turnstile/data/whitelist.json
    echo "[]" > /home/turnstile/data/offline_logs.json
    chown turnstile:turnstile /home/turnstile/data/*.json
    
    # Configura logrotate
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
    
    # Ricarica systemd e abilita servizio
    systemctl daemon-reload
    systemctl enable turnstile
    
    print_success "Installazione finalizzata"
}

# Test installazione
test_installation() {
    print_step "12" "Test installazione"
    
    local errors=0
    
    # Test 1: Utente
    if id turnstile >/dev/null 2>&1; then
        print_info "✓ Utente turnstile: OK"
    else
        print_error "✗ Utente turnstile: ERRORE"
        errors=$((errors + 1))
    fi
    
    # Test 2: Directory
    if [ -d "/home/turnstile/app" ]; then
        print_info "✓ Directory applicazione: OK"
    else
        print_error "✗ Directory applicazione: ERRORE"
        errors=$((errors + 1))
    fi
    
    # Test 3: Virtual environment
    if [ -f "/home/turnstile/venv/bin/python" ]; then
        print_info "✓ Virtual environment: OK"
    else
        print_error "✗ Virtual environment: ERRORE"
        errors=$((errors + 1))
    fi
    
    # Test 4: File principali
    if [ -f "/home/turnstile/app/main.py" ] && [ -f "/home/turnstile/app/.env" ]; then
        print_info "✓ File applicazione: OK"
    else
        print_error "✗ File applicazione: ERRORE"
        errors=$((errors + 1))
    fi
    
    # Test 5: Servizio
    if systemctl is-enabled turnstile >/dev/null 2>&1; then
        print_info "✓ Servizio systemd: OK"
    else
        print_error "✗ Servizio systemd: ERRORE"
        errors=$((errors + 1))
    fi
    
    # Test 6: Python
    if sudo -u turnstile /home/turnstile/venv/bin/python -c "import sys; print('Python OK')" >/dev/null 2>&1; then
        print_info "✓ Python environment: OK"
    else
        print_error "✗ Python environment: ERRORE"
        errors=$((errors + 1))
    fi
    
    if [ $errors -eq 0 ]; then
        print_success "Tutti i test superati!"
        return 0
    else
        print_error "$errors test falliti"
        return 1
    fi
}

# Funzione principale
main() {
    print_header "INSTALLAZIONE SISTEMA TURNSTILE - VERSIONE PULITA"
    
    check_prerequisites
    cleanup_previous
    update_system
    install_packages
    setup_hardware
    create_user
    create_directories
    setup_python
    create_application_files
    create_config_files
    create_utility_scripts
    create_systemd_service
    finalize_installation
    
    if test_installation; then
        print_header "INSTALLAZIONE COMPLETATA CON SUCCESSO!"
        echo ""
        print_info "Prossimi passi:"
        print_info "1. Riavvia il sistema: sudo reboot"
        print_info "2. Configura .env: sudo nano /home/turnstile/app/.env"
        print_info "3. Avvia servizio: sudo systemctl start turnstile"
        print_info "4. Controlla status: /home/turnstile/app/scripts/test_mode.sh status"
        print_info "5. Log in tempo reale: sudo journalctl -u turnstile -f"
        echo ""
        print_warning "RIAVVIO NECESSARIO per abilitare SPI!"
    else
        print_error "Installazione completata con errori. Controlla i log sopra."
        exit 1
    fi
}

# Esecuzione script
main "$@"