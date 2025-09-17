#!/bin/bash

# Script per attivare/disattivare modalità test

ENV_FILE="/home/turnstile/app/.env"
SERVICE_NAME="turnstile"

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_usage() {
    echo "Usage: $0 [test|production|status]"
    echo ""
    echo "Comandi:"
    echo "  test        - Attiva modalità test"
    echo "  production  - Attiva modalità produzione"
    echo "  status      - Mostra modalità corrente"
    echo ""
}

get_current_mode() {
    if [ -f "$ENV_FILE" ]; then
        grep "^ENVIRONMENT=" "$ENV_FILE" | cut -d'=' -f2 | tr -d '"' | tr -d "'"
    else
        echo "unknown"
    fi
}

set_mode() {
    local mode=$1
    
    if [ ! -f "$ENV_FILE" ]; then
        log_error "File .env non trovato: $ENV_FILE"
        exit 1
    fi
    
    # Backup del file .env
    cp "$ENV_FILE" "$ENV_FILE.backup.$(date +%s)"
    
    # Modifica il file .env
    if grep -q "^ENVIRONMENT=" "$ENV_FILE"; then
        sed -i "s/^ENVIRONMENT=.*/ENVIRONMENT=$mode/" "$ENV_FILE"
    else
        echo "ENVIRONMENT=$mode" >> "$ENV_FILE"
    fi
    
    log_info "Modalità cambiata a: $mode"
    
    # Riavvia il servizio se è in esecuzione
    if systemctl is-active --quiet $SERVICE_NAME; then
        log_info "Riavvio servizio $SERVICE_NAME..."
        sudo systemctl restart $SERVICE_NAME
        sleep 3
        
        if systemctl is-active --quiet $SERVICE_NAME; then
            log_info "Servizio riavviato con successo"
        else
            log_error "Errore nel riavvio del servizio"
            log_error "Controlla i log: sudo journalctl -u $SERVICE_NAME -f"
        fi
    else
        log_warn "Servizio non in esecuzione, avvia con: sudo systemctl start $SERVICE_NAME"
    fi
}

show_status() {
    local current_mode=$(get_current_mode)
    
    echo ""
    echo "=== STATUS SISTEMA TORNELLO ==="
    echo "Modalità corrente: $current_mode"
    
    # Status servizio
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "Servizio: ${GREEN}ATTIVO${NC}"
    else
        echo -e "Servizio: ${RED}INATTIVO${NC}"
    fi
    
    # Mostra alcune configurazioni chiave
    if [ -f "$ENV_FILE" ]; then
        echo ""
        echo "Configurazioni principali:"
        echo "  Device ID: $(grep "^DEVICE_ID=" "$ENV_FILE" | cut -d'=' -f2)"
        echo "  Device Type: $(grep "^DEVICE_TYPE=" "$ENV_FILE" | cut -d'=' -f2)"
        echo "  Log Level: $(grep "^LOG_LEVEL=" "$ENV_FILE" | cut -d'=' -f2)"
        echo "  Backend URL: $(grep "^BACKEND_URL=" "$ENV_FILE" | cut -d'=' -f2)"
    fi
    
    # Test hardware se in modalità test
    if [ "$current_mode" = "test" ]; then
        echo ""
        echo "=== TEST HARDWARE ==="
        test_hardware
    fi
    
    echo ""
}

test_hardware() {
    # Test GPIO
    echo -n "Test GPIO: "
    if python3 -c "import RPi.GPIO as GPIO; GPIO.setmode(GPIO.BCM); GPIO.cleanup()" 2>/dev/null; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}ERRORE${NC}"
    fi
    
    # Test SPI
    echo -n "Test SPI: "
    if [ -e "/dev/spidev0.0" ] && [ -e "/dev/spidev0.1" ]; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${YELLOW}PARZIALE${NC} (alcuni dispositivi SPI mancanti)"
    fi
    
    # Test connessione internet
    echo -n "Test connettività: "
    if ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        echo -e "${GREEN}OK${NC}"
    else
        echo -e "${RED}ERRORE${NC}"
    fi
    
    # Test spazio disco
    echo -n "Spazio disco: "
    local usage=$(df /home/turnstile | awk 'NR==2 {print $5}' | sed 's/%//')
    if [ "$usage" -lt 80 ]; then
        echo -e "${GREEN}OK${NC} (${usage}% utilizzato)"
    elif [ "$usage" -lt 90 ]; then
        echo -e "${YELLOW}ATTENZIONE${NC} (${usage}% utilizzato)"
    else
        echo -e "${RED}CRITICO${NC} (${usage}% utilizzato)"
    fi
}

# Controllo parametri
if [ $# -eq 0 ]; then
    show_status
    exit 0
fi

case "$1" in
    "test")
        log_info "Attivazione modalità test..."
        set_mode "test"
        log_warn "MODALITÀ TEST ATTIVA - Hardware simulato"
        ;;
    "production")
        log_info "Attivazione modalità produzione..."
        set_mode "production"
        log_info "MODALITÀ PRODUZIONE ATTIVA - Hardware reale"
        ;;
    "status")
        show_status
        ;;
    *)
        log_error "Comando non riconosciuto: $1"
        show_usage
        exit 1
        ;;
esac

exit 0