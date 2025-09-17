"""
Gestione lettori NFC RC522
"""

import asyncio
import logging
from typing import Optional, Dict
import RPi.GPIO as GPIO
from mfrc522 import SimpleMFRC522

class NFCReader:
    def __init__(self, name: str, bus: int, device: int, rst_pin: int):
        self.name = name
        self.bus = bus
        self.device = device
        self.rst_pin = rst_pin
        self.reader = None
        self.logger = logging.getLogger(f"{__name__}.{name}")
    
    async def initialize(self):
        """Inizializza il lettore NFC"""
        try:
            GPIO.setmode(GPIO.BCM)
            GPIO.setup(self.rst_pin, GPIO.OUT)
            GPIO.output(self.rst_pin, GPIO.HIGH)
            
            # Inizializza il lettore MFRC522
            self.reader = SimpleMFRC522()
            
            self.logger.info(f"Lettore NFC {self.name} inizializzato (RST pin: {self.rst_pin})")
        except Exception as e:
            self.logger.error(f"Errore nell'inizializzazione lettore {self.name}: {e}")
            raise
    
    async def read_card(self, timeout: float = 5.0) -> Optional[str]:
        """Legge una card NFC con timeout"""
        try:
            # Usa un thread executor per non bloccare l'event loop
            loop = asyncio.get_event_loop()
            
            def read_sync():
                try:
                    # Leggi la card senza bloccare
                    id, text = self.reader.read_no_block()
                    if id:
                        return str(id)
                    return None
                except Exception as e:
                    self.logger.error(f"Errore nella lettura card: {e}")
                    return None
            
            # Esegui la lettura in un thread separato con timeout
            result = await asyncio.wait_for(
                loop.run_in_executor(None, read_sync),
                timeout=timeout
            )
            
            if result:
                self.logger.debug(f"Card letta dal lettore {self.name}: {result[:8]}...")
            
            return result
            
        except asyncio.TimeoutError:
            return None
        except Exception as e:
            self.logger.error(f"Errore nella lettura card dal lettore {self.name}: {e}")
            return None
    
    def cleanup(self):
        """Pulisce le risorse del lettore"""
        try:
            if self.rst_pin:
                GPIO.output(self.rst_pin, GPIO.LOW)
            self.logger.info(f"Lettore {self.name} pulito")
        except Exception as e:
            self.logger.error(f"Errore nella pulizia lettore {self.name}: {e}")

class NFCReaderManager:
    def __init__(self, config):
        self.config = config
        self.logger = logging.getLogger(__name__)
        self.readers: Dict[str, NFCReader] = {}
        
        # Configurazione lettori basata sul tipo di dispositivo
        self._setup_readers()
    
    def _setup_readers(self):
        """Configura i lettori in base al tipo di dispositivo"""
        # Lettore di ingresso (sempre presente)
        self.readers['in'] = NFCReader(
            name='in',
            bus=self.config.SPI_BUS_IN,
            device=self.config.SPI_DEVICE_IN,
            rst_pin=self.config.NFC_READER_IN_RST
        )
        
        # Lettore di uscita (solo per tornello)
        if self.config.is_turnstile() and self.config.NFC_READER_OUT_RST:
            self.readers['out'] = NFCReader(
                name='out',
                bus=self.config.SPI_BUS_OUT,
                device=self.config.SPI_DEVICE_OUT,
                rst_pin=self.config.NFC_READER_OUT_RST
            )
    
    async def initialize(self):
        """Inizializza tutti i lettori"""
        self.logger.info("Inizializzazione lettori NFC...")
        
        for name, reader in self.readers.items():
            try:
                await reader.initialize()
            except Exception as e:
                self.logger.error(f"Impossibile inizializzare lettore {name}: {e}")
                # In modalità test, continua anche se un lettore fallisce
                if not self.config.is_test_mode():
                    raise
        
        self.logger.info(f"Inizializzati {len(self.readers)} lettori NFC")
    
    async def read_card(self, reader_name: str) -> Optional[str]:
        """Legge una card da un lettore specifico"""
        if reader_name not in self.readers:
            self.logger.error(f"Lettore {reader_name} non trovato")
            return None
        
        # In modalità test, simula lettura card
        if self.config.is_test_mode():
            return await self._simulate_card_read(reader_name)
        
        try:
            return await self.readers[reader_name].read_card(self.config.NFC_READ_TIMEOUT)
        except Exception as e:
            self.logger.error(f"Errore nella lettura da lettore {reader_name}: {e}")
            return None
    
    async def _simulate_card_read(self, reader_name: str) -> Optional[str]:
        """Simula la lettura di una card in modalità test"""
        # Simula card casuali per test
        import random
        if random.random() < 0.1:  # 10% probabilità di "lettura"
            test_cards = [
                "123456789",
                "987654321", 
                "555666777",
                "111222333"
            ]
            return random.choice(test_cards)
        return None
    
    async def cleanup(self):
        """Pulisce tutti i lettori"""
        for reader in self.readers.values():
            reader.cleanup()
        
        # Pulisce GPIO
        try:
            GPIO.cleanup()
            self.logger.info("GPIO pulito")
        except Exception as e:
            self.logger.error(f"Errore nella pulizia GPIO: {e}")
    
    def get_available_readers(self):
        """Restituisce la lista dei lettori disponibili"""
        return list(self.readers.keys())