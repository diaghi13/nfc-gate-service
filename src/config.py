"""
Modulo di configurazione per il sistema tornello
"""

import os
from pathlib import Path
from dotenv import load_dotenv
import json

class Config:
    def __init__(self, env_file=None):
        # Carica file .env
        if env_file is None:
            env_file = Path(__file__).parent.parent / '.env'
        
        load_dotenv(env_file)
        
        # Configurazione generale
        self.DEVICE_ID = os.getenv('DEVICE_ID', 'turnstile_001')
        self.DEVICE_TYPE = os.getenv('DEVICE_TYPE', 'turnstile')  # turnstile or door
        self.ENVIRONMENT = os.getenv('ENVIRONMENT', 'production')  # test or production
        
        # Configurazione backend
        self.BACKEND_URL = os.getenv('BACKEND_URL', 'https://api.example.com')
        self.API_KEY = os.getenv('API_KEY', '')
        self.WEBSOCKET_URL = os.getenv('WEBSOCKET_URL', 'wss://api.example.com/ws')
        
        # Configurazione GPIO
        self.NFC_READER_IN_RST = int(os.getenv('NFC_READER_IN_RST', '22'))
        self.NFC_READER_OUT_RST = int(os.getenv('NFC_READER_OUT_RST', '24')) if self.DEVICE_TYPE == 'turnstile' else None
        self.RELAY_CHANNEL_1 = int(os.getenv('RELAY_CHANNEL_1', '18'))
        self.RELAY_CHANNEL_2 = int(os.getenv('RELAY_CHANNEL_2', '19')) if self.DEVICE_TYPE == 'turnstile' else None
        
        # Configurazione SPI per RC522
        self.SPI_BUS_IN = int(os.getenv('SPI_BUS_IN', '0'))
        self.SPI_DEVICE_IN = int(os.getenv('SPI_DEVICE_IN', '0'))
        self.SPI_BUS_OUT = int(os.getenv('SPI_BUS_OUT', '0')) if self.DEVICE_TYPE == 'turnstile' else None
        self.SPI_DEVICE_OUT = int(os.getenv('SPI_DEVICE_OUT', '1')) if self.DEVICE_TYPE == 'turnstile' else None
        
        # Configurazione timing
        self.RELAY_OPEN_DURATION = float(os.getenv('RELAY_OPEN_DURATION', '3.0'))
        self.NFC_READ_TIMEOUT = float(os.getenv('NFC_READ_TIMEOUT', '5.0'))
        self.CONNECTION_TIMEOUT = float(os.getenv('CONNECTION_TIMEOUT', '10.0'))
        
        # Configurazione fallback
        self.FALLBACK_MODE_ENABLED = os.getenv('FALLBACK_MODE_ENABLED', 'true').lower() == 'true'
        self.MAX_OFFLINE_LOGS = int(os.getenv('MAX_OFFLINE_LOGS', '1000'))
        
        # Configurazione logging
        self.LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO')
        self.LOG_FILE = os.getenv('LOG_FILE', '/home/turnstile/logs/turnstile.log')
        self.LOG_MAX_SIZE = int(os.getenv('LOG_MAX_SIZE', '10485760'))  # 10MB
        self.LOG_BACKUP_COUNT = int(os.getenv('LOG_BACKUP_COUNT', '5'))
        
        # Configurazione aggiornamenti
        self.AUTO_UPDATE_ENABLED = os.getenv('AUTO_UPDATE_ENABLED', 'true').lower() == 'true'
        self.UPDATE_CHECK_INTERVAL = int(os.getenv('UPDATE_CHECK_INTERVAL', '3600'))  # 1 ora
        self.UPDATE_ENDPOINT = os.getenv('UPDATE_ENDPOINT', f'{self.BACKEND_URL}/updates')
        
        # File di configurazione locali
        self.WHITELIST_FILE = Path(os.getenv('WHITELIST_FILE', '/home/turnstile/data/whitelist.json'))
        self.OFFLINE_LOGS_FILE = Path(os.getenv('OFFLINE_LOGS_FILE', '/home/turnstile/data/offline_logs.json'))
        
        # Validazione configurazione
        self._validate_config()
    
    def _validate_config(self):
        """Valida la configurazione"""
        required_vars = ['DEVICE_ID', 'BACKEND_URL', 'API_KEY']
        
        for var in required_vars:
            if not getattr(self, var):
                raise ValueError(f"Variabile di configurazione mancante: {var}")
        
        if self.DEVICE_TYPE not in ['turnstile', 'door']:
            raise ValueError("DEVICE_TYPE deve essere 'turnstile' o 'door'")
        
        if self.ENVIRONMENT not in ['test', 'production']:
            raise ValueError("ENVIRONMENT deve essere 'test' o 'production'")
        
        # Crea directory necessarie
        self.WHITELIST_FILE.parent.mkdir(parents=True, exist_ok=True)
        self.OFFLINE_LOGS_FILE.parent.mkdir(parents=True, exist_ok=True)
        Path(self.LOG_FILE).parent.mkdir(parents=True, exist_ok=True)
    
    def is_test_mode(self):
        """Verifica se siamo in modalità test"""
        return self.ENVIRONMENT == 'test'
    
    def is_turnstile(self):
        """Verifica se il dispositivo è un tornello (bidirezionale)"""
        return self.DEVICE_TYPE == 'turnstile'
    
    def get_whitelist(self):
        """Carica la whitelist locale"""
        try:
            if self.WHITELIST_FILE.exists():
                with open(self.WHITELIST_FILE, 'r') as f:
                    return json.load(f)
        except Exception as e:
            print(f"Errore nel caricamento whitelist: {e}")
        return []
    
    def update_whitelist(self, whitelist):
        """Aggiorna la whitelist locale"""
        try:
            with open(self.WHITELIST_FILE, 'w') as f:
                json.dump(whitelist, f, indent=2)
        except Exception as e:
            print(f"Errore nell'aggiornamento whitelist: {e}")
    
    def to_dict(self):
        """Converte la configurazione in dizionario per debug"""
        return {k: v for k, v in self.__dict__.items() if not k.startswith('_')}