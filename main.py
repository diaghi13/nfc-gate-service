#!/usr/bin/env python3
"""
Sistema di controllo tornello bidirezionale
Raspberry Pi 4B con lettori NFC RC522 e relè a 2 canali
"""

import asyncio
import logging
import signal
import sys
from pathlib import Path

from src.config import Config
from src.turnstile_controller import TurnstileController
from src.logger_setup import setup_logging

class TurnstileSystem:
    def __init__(self):
        self.config = Config()
        self.controller = None
        self.running = False
        
    async def start(self):
        """Avvia il sistema del tornello"""
        try:
            setup_logging(self.config)
            logging.info(f"Avvio sistema tornello ID: {self.config.DEVICE_ID}")
            
            self.controller = TurnstileController(self.config)
            await self.controller.initialize()
            
            # Gestione segnali per shutdown pulito
            signal.signal(signal.SIGINT, self._signal_handler)
            signal.signal(signal.SIGTERM, self._signal_handler)
            
            self.running = True
            await self.controller.start()
            
        except Exception as e:
            logging.error(f"Errore nell'avvio del sistema: {e}")
            sys.exit(1)
    
    def _signal_handler(self, signum, frame):
        """Gestisce i segnali di shutdown"""
        logging.info(f"Ricevuto segnale {signum}, arresto sistema...")
        self.running = False
        if self.controller:
            asyncio.create_task(self.controller.stop())
    
    async def stop(self):
        """Arresta il sistema"""
        self.running = False
        if self.controller:
            await self.controller.stop()
        logging.info("Sistema arrestato correttamente")

async def main():
    """Funzione principale"""
    system = TurnstileSystem()
    try:
        await system.start()
    except KeyboardInterrupt:
        logging.info("Interruzione da tastiera")
    finally:
        await system.stop()

if __name__ == "__main__":
    asyncio.run(main())