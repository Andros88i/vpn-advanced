#!/data/data/com.termux/files/usr/bin/python3
"""
Rotador Avanzado de Configuraciones VPN
Con balanceo de carga, pruebas de latencia y failover automático
"""

import os
import sys
import time
import random
import subprocess
import json
import threading
from datetime import datetime
import schedule
import ping3
import requests

class VPNRotator:
    def __init__(self):
        self.config_dir = os.path.expanduser("~/vpn-advanced")
        self.config_list_file = os.path.join(self.config_dir, "lists/config_list.txt")
        self.stats_file = os.path.join(self.config_dir, "logs/rotation_stats.json")
        self.current_config = None
        self.config_stats = {}
        self.rotation_interval = 300  # 5 minutos
        self.max_failures = 3
        self.load_configs()
        self.load_stats()
        
    def load_configs(self):
        """Cargar lista de configuraciones"""
        self.configs = []
        self.priority_configs = []
        
        if not os.path.exists(self.config_list_file):
            print(f"⚠️  No existe {self.config_list_file}")
            self.create_sample_configs()
            return
            
        with open(self.config_list_file, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith('#'):
                    continue
                    
                # Verificar configuraciones con prioridad
                if "#PRIORITY:" in line:
                    parts = line.split("#PRIORITY:")
                    config_path = parts[0].strip()
                    priority = int(parts[1].split()[0])
                    self.priority_configs.append({
                        'path': config_path,
                        'priority': priority,
                        'failures': 0,
                        'last_used': None,
                        'latency': 9999
                    })
                else:
                    self.configs.append({
                        'path': line,
                        'priority': 5,  # Prioridad media por defecto
                        'failures': 0,
                        'last_used': None,
                        'latency': 9999
                    })
        
        print(f"✅ Cargadas {len(self.configs)} configuraciones normales")
        print(f"✅ Cargadas {len(self.priority_configs)} configuraciones prioritarias")
    
    def create_sample_configs(self):
        """Crear configuraciones de ejemplo si no existen"""
        sample_configs = [
            os.path.join(self.config_dir, "configs/servidor-usa.ovpn"),
            os.path.join(self.config_dir, "configs/servidor-europa.ovpn"),
            os.path.join(self.config_dir, "configs/servidor-asia.ovpn"),
        ]
        
        os.makedirs(os.path.dirname(sample_configs[0]), exist_ok=True)
        
        for config in sample_configs:
            with open(config, 'w') as f:
                f.write("# Configuración VPN de ejemplo\n")
                f.write("# Reemplaza con tu configuración real\n")
                
        with open(self.config_list_file, 'w') as f:
            for config in sample_configs:
                f.write(f"{config}\n")
                
        print(f"✅ Creadas configuraciones de ejemplo en {self.config_dir}")
        self.load_configs()
    
    def load_stats(self):
        """Cargar estadísticas previas"""
        if os.path.exists(self.stats_file):
            with open(self.stats_file, 'r') as f:
                self.config_stats = json.load(f)
    
    def save_stats(self):
        """Guardar estadísticas"""
        with open(self.stats_file, 'w') as f:
            json.dump(self.config_stats, f, indent=2)
    
    def test_latency(self, config):
        """Probar latencia del servidor VPN"""
        try:
            # Extraer IP del archivo de configuración
            ip = self.extract_server_ip(config['path'])
            if not ip:
                return 9999
                
            # Usar ping3 para medir latencia
            latency = ping3.ping(ip, timeout=2)
            if latency is None or latency is False:
                return 9999
                
            return round(latency * 1000, 2)  # Convertir a ms
        except:
            return 9999
    
    def extract_server_ip(self, config_path):
        """Extraer IP del servidor del archivo de configuración"""
        try:
            if config_path.endswith('.ovpn'):
                with open(config_path, 'r') as f:
                    for line in f:
                        if line.startswith('remote '):
                            parts = line.strip().split()
                            return parts[1]  # IP o dominio
            elif config_path.endswith('.conf'):
                with open(config_path, 'r') as f:
                    for line in f:
                        if 'Endpoint' in line:
                            parts = line.strip().split('=')
                            endpoint = parts[1].strip()
                            return endpoint.split(':')[0]
        except:
            pass
        return None
    
    def test_connection(self, config):
        """Probar conectividad completa"""
        # Medir latencia
        latency = self.test_latency(config)
        config['latency'] = latency
        
        # Probar conectividad a internet
        try:
            response = requests.get('http://1.1.1.1', timeout=3)
            return latency < 500  # Considerar válido si < 500ms
        except:
            return False
    
    def stop_current_vpn(self):
        """Detener conexión VPN actual"""
        print("🛑 Deteniendo conexión actual...")
        
        # Matar procesos VPN
        subprocess.run(['pkill', '-f', 'openvpn'], 
                      stdout=subprocess.DEVNULL, 
                      stderr=subprocess.DEVNULL)
        subprocess.run(['wg-quick', 'down', 'all'],
                      stdout=subprocess.DEVNULL,
                      stderr=subprocess.DEVNULL)
        
        time.sleep(2)
    
    def start_vpn(self, config):
        """Iniciar conexión VPN"""
        config_path = config['path']
        print(f"🚀 Iniciando: {os.path.basename(config_path)}")
        
        if config_path.endswith('.ovpn'):
            cmd = ['openvpn', '--config', config_path, '--daemon']
        elif config_path.endswith('.conf'):
            cmd = ['wg-quick', 'up', config_path]
        else:
            print(f"❌ Formato no soportado: {config_path}")
            return False
        
        try:
            result = subprocess.run(cmd, 
                                  capture_output=True, 
                                  text=True,
                                  timeout=10)
            
            if result.returncode == 0:
                config['last_used'] = datetime.now().isoformat()
                self.current_config = config
                
                # Esperar que la conexión se establezca
                time.sleep(3)
                
                # Verificar conexión
                if self.test_connection(config):
                    print(f"✅ Conectado - Latencia: {config['latency']}ms")
                    config['failures'] = 0
                    return True
                else:
                    print("❌ Conexión falló después de iniciar")
                    config['failures'] += 1
                    return False
            else:
                print(f"❌ Error al iniciar: {result.stderr}")
                config['failures'] += 1
                return False
                
        except subprocess.TimeoutExpired:
            print("❌ Timeout al iniciar VPN")
            config['failures'] += 1
            return False
    
    def
