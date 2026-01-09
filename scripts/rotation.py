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
    
    def select_best_config(self):
        """Seleccionar la mejor configuración disponible"""
        all_configs = self.priority_configs + self.configs
        
        # Filtrar configuraciones con muchas fallas
        valid_configs = [c for c in all_configs if c['failures'] < self.max_failures]
        
        if not valid_configs:
            print("⚠️  Todas las configuraciones tienen muchas fallas, reseteando...")
            for c in all_configs:
                c['failures'] = 0
            valid_configs = all_configs
        
        # Ordenar por prioridad (mayor primero) y luego por latencia
        valid_configs.sort(key=lambda x: (-x['priority'], x['latency']))
        
        # Evitar usar la misma configuración si hay alternativas
        if (self.current_config and len(valid_configs) > 1 and 
            valid_configs[0]['path'] == self.current_config['path']):
            return valid_configs[1]
        
        return valid_configs[0] if valid_configs else None
    
    def rotate(self):
        """Realizar rotación de configuración"""
        print(f"\n{'='*50}")
        print(f"🔄 Rotación programada - {datetime.now().strftime('%H:%M:%S')}")
        print(f"{'='*50}")
        
        # Seleccionar mejor configuración
        best_config = self.select_best_config()
        
        if not best_config:
            print("❌ No hay configuraciones disponibles")
            return
        
        print(f"🎯 Seleccionada: {os.path.basename(best_config['path'])}")
        print(f"   Prioridad: {best_config['priority']}")
        print(f"   Fallos previos: {best_config['failures']}")
        print(f"   Último uso: {best_config['last_used']}")
        
        # Detener conexión actual
        self.stop_current_vpn()
        
        # Iniciar nueva conexión
        if self.start_vpn(best_config):
            print("✅ Rotación exitosa")
            
            # Actualizar estadísticas
            stats_key = os.path.basename(best_config['path'])
            if stats_key not in self.config_stats:
                self.config_stats[stats_key] = {'uses': 0, 'total_latency': 0}
            
            self.config_stats[stats_key]['uses'] += 1
            self.config_stats[stats_key]['total_latency'] += best_config['latency']
            self.save_stats()
        else:
            print("❌ Rotación fallida, reintentando...")
            time.sleep(2)
            self.rotate()  # Reintentar
    
    def continuous_monitoring(self):
        """Monitoreo continuo de la conexión"""
        def monitor():
            while True:
                if self.current_config:
                    # Probar conexión actual
                    if not self.test_connection(self.current_config):
                        print("⚠️  Conexión actual falló, rotando...")
                        self.rotate()
                
                time.sleep(60)  # Verificar cada minuto
        
        thread = threading.Thread(target=monitor, daemon=True)
        thread.start()
    
    def run_scheduled_rotation(self):
        """Ejecutar rotaciones programadas"""
        # Rotar cada X minutos
        schedule.every(self.rotation_interval).seconds.do(self.rotate)
        
        # Rotación inicial
        self.rotate()
        
        print(f"\n⏰ Rotación programada cada {self.rotation_interval} segundos")
        print("📊 Monitoreo continuo activado")
        print("🛑 Presiona Ctrl+C para detener\n")
        
        # Iniciar monitoreo continuo
        self.continuous_monitoring()
        
        try:
            while True:
                schedule.run_pending()
                time.sleep(1)
        except KeyboardInterrupt:
            print("\n👋 Deteniendo rotador...")
            self.stop_current_vpn()
    
    def test_all_configs(self):
        """Probar todas las configuraciones"""
        print("\n🧪 Probando todas las configuraciones...")
        
        all_configs = self.priority_configs + self.configs
        results = []
        
        for config in all_configs:
            print(f"\n🔍 Probando: {os.path.basename(config['path'])}")
            
            latency = self.test_latency(config)
            config['latency'] = latency
            
            if latency < 500:
                status = "✅ OK"
            elif latency < 1000:
                status = "⚠️  Lento"
            else:
                status = "❌ Inalcanzable"
            
            results.append({
                'config': os.path.basename(config['path']),
                'latency': f"{latency}ms",
                'status': status,
                'priority': config['priority']
            })
            
            print(f"   Latencia: {latency}ms - {status}")
        
        # Mostrar resumen
        print("\n" + "="*50)
        print("📊 RESUMEN DE PRUEBAS")
        print("="*50)
        
        for result in sorted(results, key=lambda x: x['latency']):
            print(f"{result['status']} {result['config']}: {result['latency']} (Pri: {result['priority']})")
    
    def show_stats(self):
        """Mostrar estadísticas históricas"""
        print("\n📈 ESTADÍSTICAS DE USO")
        print("="*50)
        
        if not self.config_stats:
            print("No hay estadísticas registradas")
            return
        
        for config_name, stats in self.config_stats.items():
            avg_latency = stats['total_latency'] / stats['uses'] if stats['uses'] > 0 else 0
            print(f"📁 {config_name}:")
            print(f"   Usos: {stats['uses']}")
            print(f"   Latencia promedio: {avg_latency:.2f}ms")
            print()

def main():
    """Función principal"""
    print("""
    ╔══════════════════════════════════════╗
    ║   ROTADOR AVANZADO DE VPN            ║
    ║   Balanceo de carga + Failover       ║
    ╚══════════════════════════════════════╝
    """)
    
    rotator = VPNRotator()
    
    if len(sys.argv) > 1:
        if sys.argv[1] == "test":
            rotator.test_all_configs()
        elif sys.argv[1] == "stats":
            rotator.show_stats()
        elif sys.argv[1] == "rotate":
            rotator.rotate()
        elif sys.argv[1] == "once":
            rotator.rotate()
            time.sleep(5)
        elif sys.argv[1].isdigit():
            rotator.rotation_interval = int(sys.argv[1])
            rotator.run_scheduled_rotation()
    else:
        # Menú interactivo
        while True:
            print("\n" + "="*50)
            print("MENÚ PRINCIPAL")
            print("="*50)
            print("1) Iniciar rotación automática")
            print("2) Rotar una vez")
            print("3) Probar todas las configuraciones")
            print("4) Mostrar estadísticas")
            print("5) Configurar intervalo (segundos)")
            print("6) Salir")
            print(f"\nIntervalo actual: {rotator.rotation_interval}s")
            
            choice = input("\nSelecciona opción: ").strip()
            
            if choice == "1":
                rotator.run_scheduled_rotation()
                break
            elif choice == "2":
                rotator.rotate()
            elif choice == "3":
                rotator.test_all_configs()
            elif choice == "4":
                rotator.show_stats()
            elif choice == "5":
                try:
                    interval = int(input("Nuevo intervalo (segundos): "))
                    rotator.rotation_interval = interval
                    print(f"✅ Intervalo cambiado a {interval}s")
                except ValueError:
                    print("❌ Valor inválido")
            elif choice == "6":
                print("👋 Saliendo...")
                break
            else:
                print("❌ Opción inválida")

if __name__ == "__main__":
    main()
