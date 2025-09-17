#!/bin/bash

# Script per controllare se è richiesto un riavvio dopo aggiornamento

RESTART_FILE="/home/turnstile/data/restart_required"
LOG_FILE="/home/turnstile/logs/service.log"

# Funzione di logging
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Controlla se esiste il file di riavvio richiesto
if [ -f "$RESTART_FILE" ]; then
    log_message "Riavvio richiesto dopo aggiornamento, rimozione flag"
    rm "$RESTART_FILE"
    
    # Attendi qualche secondo per permettere al processo precedente di terminare
    sleep 5
    
    log_message "Proseguimento con avvio servizio"
fi

exit 0