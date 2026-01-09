#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# VPN MANAGER ADVANCED - Termux
# Características:
# 1. Ofuscación Shadowsocks/Stunnel
# 2. Rotación dinámica de configuraciones
# 3. Kill Switch con iptables
# 4. DNS seguro + bloqueo IPv6
# 5. VPN Nativo Termux (sin root)
# ============================================

CONFIG_DIR="$HOME/vpn-advanced"
LOG_FILE="$CONFIG_DIR/logs/vpn.log"
CONFIG_LIST="$CONFIG_DIR/lists/config_list.txt"
WHITELIST="$CONFIG_DIR/lists/whitelist.txt"
CURRENT_CONFIG=""
ROTATION_TIME=300  # 5 minutos (en segundos)

# =========================================================
# CONFIGURACIÓN
# =========================================================
IMG="/data/data/com.termux/files/home/storage/pictures/Anonymus.png"

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================
# VPN NATIVO TERMUX (SIN ROOT)
# ============================================

start_termux_vpn() {
    log_message "Iniciando VPN nativo de Termux..."
    
    # Ruta al cliente VPN
    local vpn_client="$CONFIG_DIR/scripts/termux_vpn.sh"
    
    # Si no existe, mostrar mensaje
    if [ ! -f "$vpn_client" ]; then
        log_message "${YELLOW}Cliente VPN nativo no encontrado${NC}"
        echo ""
        echo "📦 Para usar VPN sin root, necesitas:"
        echo "1. Crear el archivo: $vpn_client"
        echo "2. Agregar el código del cliente VPN"
        echo "3. Dar permisos: chmod +x $vpn_client"
        echo ""
        echo "📄 El código está disponible como 'termux_vpn_client.sh'"
        echo "📋 Guárdalo en la ubicación indicada"
        echo ""
        read -p "Presiona Enter para continuar..."
        return 1
    fi
    
    # Verificar si es ejecutable
    if [ ! -x "$vpn_client" ]; then
        log_message "${YELLOW}El cliente VPN no es ejecutable${NC}"
        echo "Ejecuta: chmod +x $vpn_client"
        return 1
    fi
    
    # Ejecutar el cliente VPN
    log_message "Ejecutando cliente VPN nativo..."
    bash "$vpn_client" menu
    
    log_message "VPN nativo finalizado"
    return 0
}

# Inicializar directorios
init_directories() {
    mkdir -p $CONFIG_DIR/{configs,scripts,logs,lists}
    touch $LOG_FILE $CONFIG_LIST $WHITELIST
    
    echo "VPN Manager iniciado: $(date)" >> $LOG_FILE
    log_message "Sistema inicializado"
}

# Logging function
log_message() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# ============================================
# KILL SWITCH CON IPTABLES
# ============================================

setup_killswitch() {
    log_message "Configurando Kill Switch..."
    
    # Flush existing rules
    iptables -F
    iptables -t nat -F
    ip6tables -F
    
    # Establecer políticas por defecto (DROP todo)
    iptables -P INPUT DROP
    iptables -P OUTPUT DROP
    iptables -P FORWARD DROP
    ip6tables -P INPUT DROP
    ip6tables -P OUTPUT DROP
    ip6tables -P FORWARD DROP
    
    # Permitir loopback
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A OUTPUT -o lo -j ACCEPT
    
    # Permitir conexiones establecidas y relacionadas
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A OUTPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    
    # Permitir DNS de confianza (Quad9, Cloudflare)
    iptables -A OUTPUT -p udp --dport 53 -d 9.9.9.9 -j ACCEPT
    iptables -A OUTPUT -p udp --dport 53 -d 1.1.1.1 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -d 9.9.9.9 -j ACCEPT
    iptables -A OUTPUT -p tcp --dport 53 -d 1.1.1.1 -j ACCEPT
    
    # Whitelist de IPs/dominios
    if [ -f "$WHITELIST" ]; then
        while read -r line; do
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            iptables -A OUTPUT -d "$line" -j ACCEPT
        done < "$WHITELIST"
    fi
    
    # Bloquear todo el tráfico IPv6
    ip6tables -A INPUT -j DROP
    ip6tables -A OUTPUT -j DROP
    
    log_message "Kill Switch activado"
}

disable_killswitch() {
    log_message "Desactivando Kill Switch..."
    
    iptables -P INPUT ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -P FORWARD ACCEPT
    ip6tables -P INPUT ACCEPT
    ip6tables -P OUTPUT ACCEPT
    ip6tables -P FORWARD ACCEPT
    
    iptables -F
    iptables -t nat -F
    ip6tables -F
    
    log_message "Kill Switch desactivado"
}

# ============================================
# GESTIÓN DNS Y IPv6
# ============================================

configure_dns() {
    log_message "Configurando DNS seguro..."
    
    # Configurar resolv.conf temporal
    echo "nameserver 9.9.9.9" > /data/data/com.termux/files/usr/etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /data/data/com.termux/files/usr/etc/resolv.conf
    
    # Deshabilitar IPv6
    sysctl -w net.ipv6.conf.all.disable_ipv6=1
    sysctl -w net.ipv6.conf.default.disable_ipv6=1
    
    # Bloquear IPv6 con iptables (ya hecho en killswitch)
    log_message "DNS configurado e IPv6 deshabilitado"
}

# ============================================
# OFUSCACIÓN CON SHADOWSOCKS/STUNNEL
# ============================================

start_shadowsocks() {
    local config="$CONFIG_DIR/configs/shadowsocks.json"
    
    if [ ! -f "$config" ]; then
        log_message "Creando configuración Shadowsocks por defecto..."
        cat > "$config" << EOF
{
    "server":"your-server-ip",
    "server_port":8388,
    "local_port":1080,
    "password":"your-password",
    "timeout":300,
    "method":"chacha20-ietf-poly1305"
}
EOF
        log_message "${YELLOW}Edita $config con tus credenciales${NC}"
        return 1
    fi
    
    log_message "Iniciando Shadowsocks..."
    ss-local -c "$config" -b 127.0.0.1 -l 1080 &
    echo $! > /tmp/ss.pid
}

start_stunnel() {
    local config="$CONFIG_DIR/configs/stunnel.conf"
    
    if [ ! -f "$config" ]; then
        log_message "Creando configuración Stunnel por defecto..."
        cat > "$config" << EOF
[openvpn]
client = yes
accept = 127.0.0.1:1194
connect = your-server:443
verify = 2
CAfile = /data/data/com.termux/files/usr/etc/tls/ca.crt
cert = /data/data/com.termux/files/usr/etc/tls/client.crt
key = /data/data/com.termux/files/usr/etc/tls/client.key
EOF
        log_message "${YELLOW}Edita $config con tus certificados${NC}"
        return 1
    fi
    
    log_message "Iniciando Stunnel..."
    stunnel "$config" &
    echo $! > /tmp/stunnel.pid
}

# ============================================
# ROTACIÓN DE CONFIGURACIONES
# ============================================

rotate_configuration() {
    local configs=($(cat "$CONFIG_LIST" 2>/dev/null))
    
    if [ ${#configs[@]} -eq 0 ]; then
        log_message "${RED}No hay configuraciones en la lista${NC}"
        return 1
    fi
    
    # Seleccionar configuración aleatoria
    local random_index=$((RANDOM % ${#configs[@]}))
    local new_config="${configs[$random_index]}"
    
    if [ "$new_config" = "$CURRENT_CONFIG" ]; then
        # Seleccionar la siguiente si es la misma
        new_config="${configs[((random_index + 1) % ${#configs[@]})]}"
    fi
    
    log_message "Rotando a configuración: $new_config"
    
    # Detener conexión actual
    stop_vpn_connection
    
    # Esperar para evitar fugas de DNS
    sleep 2
    
    # Iniciar nueva configuración
    start_vpn_connection "$new_config"
    
    CURRENT_CONFIG="$new_config"
    log_message "${GREEN}Rotación completada${NC}"
}

# ============================================
# GESTIÓN CONEXIÓN VPN
# ============================================

start_vpn_connection() {
    local config="$1"
    
    if [[ "$config" == *.ovpn ]]; then
        log_message "Iniciando OpenVPN: $config"
        openvpn --config "$config" --auth-nocache --daemon &
        echo $! > /tmp/openvpn.pid
        
    elif [[ "$config" == *.conf ]]; then
        log_message "Iniciando WireGuard: $config"
        wg-quick up "$config" 2>> $LOG_FILE &
        echo $! > /tmp/wireguard.pid
    fi
    
    # Verificar conexión
    sleep 3
    if check_connection; then
        log_message "${GREEN}Conexión establecida${NC}"
    else
        log_message "${RED}Error en la conexión${NC}"
        rotate_configuration
    fi
}

stop_vpn_connection() {
    # Detener procesos VPN
    [ -f /tmp/openvpn.pid ] && kill $(cat /tmp/openvpn.pid) 2>/dev/null
    [ -f /tmp/wireguard.pid ] && wg-quick down $(cat /tmp/wireguard.conf) 2>/dev/null
    [ -f /tmp/ss.pid ] && kill $(cat /tmp/ss.pid) 2>/dev/null
    [ -f /tmp/stunnel.pid ] && kill $(cat /tmp/stunnel.pid) 2>/dev/null
    
    rm -f /tmp/*.pid
}

check_connection() {
    # Verificar conectividad
    if ping -c 2 -W 3 9.9.9.9 >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# ============================================
# MONITOREO Y ROTACIÓN AUTOMÁTICA
# ============================================

monitor_connection() {
    log_message "Iniciando monitor de conexión..."
    
    while true; do
        if ! check_connection; then
            log_message "${RED}Conexión perdida - Activando Kill Switch${NC}"
            setup_killswitch
            rotate_configuration
        fi
        
        # Rotación programada cada X minutos
        sleep $ROTATION_TIME
        log_message "Rotación programada iniciada..."
        rotate_configuration
    done
}

# ============================================
# MENÚ PRINCIPAL
# ============================================

show_menu() {
    
    clear

if command -v chafa >/dev/null 2>&1 && [ -f "$IMG" ]; then
    chafa --center=on --size=60x30 "$IMG"
else
    echo -e "${RED}[!] No se pudo cargar la imagen o chafa no está instalado${NC}"
fi

    echo
    echo -e "${LRED}      [+] CREADOR : Andro_Os${NC}"
    echo -e "${LRED}      [+] PROYECTO: VPN MANAGER ADVANCED - TERMUX${NC}"
    echo -e "${LRED}      [+] ESTADO  : ${GREEN}ACTIVO${NC}"
    echo -e "${LRED}=================================================${NC}"
    echo ""
    echo "1) Iniciar VPN con ofuscación"
    echo "2) Iniciar rotación automática"
    echo "3) VPN Nativo Termux (sin root)"
    echo "4) Detener todos los servicios"
    echo "5) Ver estado de conexión"
    echo "6) Agregar configuración"
    echo "7) Configurar Kill Switch"
    echo "8) Salir"
    echo ""
    read -p "Selecciona una opción: " choice
    
    case $choice in
        1)
            setup_killswitch
            configure_dns
            start_shadowsocks
            sleep 2
            rotate_configuration
            ;;
        2)
            setup_killswitch
            configure_dns
            monitor_connection &
            ;;
        3)
            start_termux_vpn
            ;;
        4)
            stop_vpn_connection
            disable_killswitch
            ;;
        5)
            if check_connection; then
                echo -e "${GREEN}✓ Conectado${NC}"
            else
                echo -e "${RED}✗ Desconectado${NC}"
            fi
            ;;
        6)
            nano $CONFIG_LIST
            ;;
        7)
            setup_killswitch
            ;;
        8)
            stop_vpn_connection
            disable_killswitch
            exit 0
            ;;
    esac
    
    read -p "Presiona Enter para continuar..."
    show_menu
}

# ============================================
# SCRIPT DE ROTACIÓN EN PYTHON (opcional)
# ============================================

cat > $CONFIG_DIR/scripts/rotation.py << 'EOF'
#!/data/data/com.termux/files/usr/bin/python3

import subprocess
import time
import random
import os
import sys
import schedule

CONFIG_DIR = os.path.expanduser("~/vpn-advanced")
CONFIG_LIST = os.path.join(CONFIG_DIR, "lists/config_list.txt")

def load_configs():
    with open(CONFIG_LIST, 'r') as f:
        configs = [line.strip() for line in f if line.strip()]
    return configs

def rotate_vpn():
    configs = load_configs()
    if not configs:
        print("No hay configuraciones disponibles")
        return
    
    new_config = random.choice(configs)
    print(f"Rotando a: {new_config}")
    
    # Detener conexión actual
    subprocess.run(["pkill", "openvpn"])
    subprocess.run(["wg-quick", "down", "wg0"])
    time.sleep(2)
    
    # Iniciar nueva conexión
    if new_config.endswith('.ovpn'):
        subprocess.Popen(["openvpn", "--config", new_config, "--daemon"])
    elif new_config.endswith('.conf'):
        subprocess.Popen(["wg-quick", "up", new_config])
    
    # Verificar conexión
    time.sleep(5)
    result = subprocess.run(["ping", "-c", "2", "9.9.9.9"], 
                          capture_output=True)
    if result.returncode == 0:
        print("✓ Rotación exitosa")
    else:
        print("✗ Error en rotación")
        rotate_vpn()  # Reintentar

if __name__ == "__main__":
    # Rotar cada 5 minutos
    schedule.every(5).minutes.do(rotate_vpn)
    
    print("Rotador iniciado - Ctrl+C para salir")
    try:
        while True:
            schedule.run_pending()
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nDeteniendo rotador...")
EOF

# ============================================
# EJECUCIÓN PRINCIPAL
# ============================================

if [ "$1" = "auto" ]; then
    init_directories
    setup_killswitch
    configure_dns
    start_shadowsocks
    monitor_connection
else
    init_directories
    show_menu
fi
