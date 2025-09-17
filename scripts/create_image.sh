#!/bin/bash

# Script per creare un'immagine SD pronta per la distribuzione

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Configurazioni
IMAGE_NAME="turnstile-system-$(date +%Y%m%d).img"
MOUNT_POINT="/mnt/pi-image"
OUTPUT_DIR="/home/pi/images"

show_usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Opzioni:"
    echo "  -d DEVICE    Dispositivo SD (es. /dev/sdb)"
    echo "  -o OUTPUT    Directory output (default: $OUTPUT_DIR)"
    echo "  -n NAME      Nome immagine (default: $IMAGE_NAME)"
    echo "  -h           Mostra questo aiuto"
    echo ""
    echo "ATTENZIONE: Questo script deve essere eseguito su un sistema con il"
    echo "software del tornello già installato e configurato."
}

cleanup_and_prepare() {
    log_info "Pulizia sistema per creazione immagine..."
    
    # Ferma servizi non necessari
    systemctl stop turnstile 2>/dev/null || true
    
    # Pulisci log
    find /home/turnstile/logs -name "*.log*" -delete 2>/dev/null
    find /var/log -name "*.log.*" -delete 2>/dev/null
    journalctl --vacuum-time=1d
    
    # Pulisci cache e temporanei
    apt-get clean
    rm -rf /var/lib/apt/lists/*
    rm -rf /tmp/*
    rm -rf /var/tmp/*
    
    # Pulisci dati specifici del dispositivo
    > /home/turnstile/data/offline_logs.json
    > /home/turnstile/data/whitelist.json
    rm -rf /home/turnstile/updates/*
    rm -rf /home/turnstile/backups/data/*
    
    # Reset configurazione a template
    if [ -f "/home/turnstile/app/.env" ]; then
        mv /home/turnstile/app/.env /home/turnstile/app/.env.configured
        cp /home/turnstile/app/.env.template /home/turnstile/app/.env
    fi
    
    # Pulisci SSH keys (verranno rigenerati al primo boot)
    rm -f /etc/ssh/ssh_host_*
    
    # Pulisci history
    history -c
    > /home/pi/.bash_history
    > /home/turnstile/.bash_history
    > /root/.bash_history
    
    log_info "Sistema pulito per imaging"
}

configure_first_boot() {
    log_info "Configurazione script primo avvio..."
    
    # Crea script per il primo boot
    cat > /home/turnstile/scripts/first_boot.sh << 'EOF'
#!/bin/bash

FIRST_BOOT_FLAG="/boot/turnstile_first_boot"
LOG_FILE="/home/turnstile/logs/first_boot.log"

if [ -f "$FIRST_BOOT_FLAG" ]; then
    echo "$(date): Primo avvio completato, generazione SSH keys..." >> "$LOG_FILE"
    
    # Rigenera SSH host keys
    ssh-keygen -A
    
    # Genera ID dispositivo unico se non configurato
    if grep -q "DEVICE_ID=turnstile_001" /home/turnstile/app/.env; then
        NEW_ID="turnstile_$(openssl rand -hex 3)"
        sed -i "s/DEVICE_ID=turnstile_001/DEVICE_ID=$NEW_ID/" /home/turnstile/app/.env
        echo "$(date): ID dispositivo generato: $NEW_ID" >> "$LOG_FILE"
    fi
    
    # Rimuovi flag primo boot
    rm -f "$FIRST_BOOT_FLAG"
    
    # Riavvia SSH
    systemctl restart ssh
    
    echo "$(date): Primo avvio completato" >> "$LOG_FILE"
    
    # Abilita e avvia servizio turnstile
    systemctl enable turnstile
    systemctl start turnstile
fi
EOF
    
    chmod +x /home/turnstile/scripts/first_boot.sh
    
    # Aggiungi al boot
    if ! grep -q "first_boot.sh" /etc/rc.local; then
        sed -i '/^exit 0/i\/home/turnstile/scripts/first_boot.sh' /etc/rc.local
    fi
    
    # Crea flag primo boot
    touch /boot/turnstile_first_boot
    
    log_info "Script primo avvio configurato"
}

create_documentation() {
    log_info "Creazione documentazione..."
    
    cat > /home/turnstile/README.txt << 'EOF'
=== SISTEMA TORNELLO RASPBERRY PI ===

Questa immagine contiene un sistema pronto per il controllo di tornelli
bidirezionali o porte di accesso con lettori NFC.

PRIMO AVVIO:
1. Inserire la SD nel Raspberry Pi 4
2. Collegare i componenti hardware secondo lo schema
3. Accendere il sistema
4. Attendere il completamento del primo boot (LED attività si ferma)
5. Connettersi via SSH: ssh turnstile@<IP_RASPBERRY>
6. Modificare /home/turnstile/app/.env con la propria configurazione
7. Riavviare il servizio: sudo systemctl restart turnstile

COMPONENTI HARDWARE:
- 2x Lettori NFC RC522 (solo 1 per porte)
- 1x Relè a 2 canali (solo 1 canale per porte)
- Collegamenti GPIO secondo configurazione in .env

CONFIGURAZIONE:
- File principale: /home/turnstile/app/.env
- Log: /home/turnstile/logs/
- Dati: /home/turnstile/data/

MODALITÀ TEST:
Per testare senza hardware: /home/turnstile/app/scripts/test_mode.sh test

SUPPORTO:
- Log sistema: sudo journalctl -u turnstile -f
- Status: /home/turnstile/app/scripts/test_mode.sh status
- Test hardware incluso in modalità test

Versione sistema: $(cat /home/turnstile/app/VERSION 2>/dev/null || echo "1.0.0")
Data creazione: $(date)
EOF

    log_info "Documentazione creata"
}

# Parsing opzioni
while getopts "d:o:n:h" opt; do
    case $opt in
        d) DEVICE="$OPTARG";;
        o) OUTPUT_DIR="$OPTARG";;
        n) IMAGE_NAME="$OPTARG";;
        h) show_usage; exit 0;;
        *) show_usage; exit 1;;
    esac
done

# Verifica permessi root
if [ "$EUID" -ne 0 ]; then
    log_error "Questo script deve essere eseguito come root"
    exit 1
fi

# Verifica che siamo su Raspberry Pi
if ! grep -q "Raspberry Pi" /proc/cpuinfo; then
    log_warn "Non sembra un Raspberry Pi, continuo comunque..."
fi

# Crea directory output
mkdir -p "$OUTPUT_DIR"

log_info "Creazione immagine sistema tornello"
log_info "Output: $OUTPUT_DIR/$IMAGE_NAME"

# Prepara sistema
cleanup_and_prepare
configure_first_boot  
create_documentation

if [ -n "$DEVICE" ]; then
    log_info "Creazione immagine da dispositivo $DEVICE..."
    
    # Verifica che il dispositivo esista
    if [ ! -b "$DEVICE" ]; then
        log_error "Dispositivo $DEVICE non trovato"
        exit 1
    fi
    
    # Crea immagine
    log_info "Creazione immagine (potrebbe richiedere tempo)..."
    dd if="$DEVICE" of="$OUTPUT_DIR/$IMAGE_NAME" bs=4M status=progress
    
    # Comprimi immagine
    log_info "Compressione immagine..."
    gzip -f "$OUTPUT_DIR/$IMAGE_NAME"
    IMAGE_NAME="$IMAGE_NAME.gz"
    
else
    log_info "Preparazione sistema completata"
    log_info "Per creare l'immagine:"
    log_info "1. Spegni il Raspberry Pi"
    log_info "2. Inserisci la SD in un computer Linux"
    log_info "3. Esegui: sudo $0 -d /dev/sdX"
fi

# Statistiche finali
if [ -f "$OUTPUT_DIR/$IMAGE_NAME" ]; then
    SIZE=$(du -h "$OUTPUT_DIR/$IMAGE_NAME" | cut -f1)
    log_info "Immagine creata: $OUTPUT_DIR/$IMAGE_NAME ($SIZE)"
    log_info ""
    log_info "Per deployare l'immagine:"
    log_info "sudo dd if=$OUTPUT_DIR/$IMAGE_NAME of=/dev/sdX bs=4M status=progress"
    log_info "(sostituisci /dev/sdX con il dispositivo SD corretto)"
fi

log_info "Completato!"
exit 0