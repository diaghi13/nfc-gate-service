"""
Configurazione del sistema di logging
"""

import logging
import logging.handlers
from pathlib import Path

def setup_logging(config):
    """Configura il sistema di logging"""
    
    # Crea directory log se non esiste
    log_file = Path(config.LOG_FILE)
    log_file.parent.mkdir(parents=True, exist_ok=True)
    
    # Configurazione del root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(getattr(logging, config.LOG_LEVEL.upper()))
    
    # Rimuovi handler esistenti
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)
    
    # Formatter per i log
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    # Handler per file con rotazione
    file_handler = logging.handlers.RotatingFileHandler(
        config.LOG_FILE,
        maxBytes=config.LOG_MAX_SIZE,
        backupCount=config.LOG_BACKUP_COUNT
    )
    file_handler.setFormatter(formatter)
    file_handler.setLevel(getattr(logging, config.LOG_LEVEL.upper()))
    
    # Handler per console
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    
    # In modalità test, usa solo INFO sulla console
    if config.is_test_mode():
        console_handler.setLevel(logging.INFO)
    else:
        console_handler.setLevel(getattr(logging, config.LOG_LEVEL.upper()))
    
    # Aggiungi handler
    root_logger.addHandler(file_handler)
    root_logger.addHandler(console_handler)
    
    # Configura logger specifici per ridurre verbosità di alcune librerie
    logging.getLogger('websockets').setLevel(logging.WARNING)
    logging.getLogger('aiohttp').setLevel(logging.WARNING)
    logging.getLogger('asyncio').setLevel(logging.WARNING)
    
    # Logger per componenti hardware più verbose in modalità debug
    if config.LOG_LEVEL.upper() == 'DEBUG':
        logging.getLogger('src.nfc_reader').setLevel(logging.DEBUG)
        logging.getLogger('src.relay_controller').setLevel(logging.DEBUG)
    else:
        logging.getLogger('src.nfc_reader').setLevel(logging.INFO)
        logging.getLogger('src.relay_controller').setLevel(logging.INFO)
    
    logging.info(f"Logging configurato - Livello: {config.LOG_LEVEL} - File: {config.LOG_FILE}")