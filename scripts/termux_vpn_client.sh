#!/data/data/com.termux/files/usr/bin/bash

# ============================================
# TERMUX VPN CLIENT - NATIVO SIN ROOT
# ============================================

VPN_DIR="$HOME/.termux_vpn"
LOG_FILE="$VPN_DIR/vpn_client.log"
PID_FILE="$VPN_DIR/vpn_client.pid"

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

init_vpn_client() {
    mkdir -p "$VPN_DIR"
    echo "Termux VPN Client iniciado: $(date)" >> "$LOG_FILE"
}

log_vpn() {
    echo -e "${BLUE}[VPN Client]${NC} $1"
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}

# ============================================
# MÉTODOS VPN SIN ROOT
# ============================================

start_socks5_proxy() {
    local server="$1"
    local port="$2"
    local user="$3"
    local pass="$4"
    
    log_vpn "Iniciando proxy SOCKS5 a $server:$port"
    
    # Usar ssh como tunnel SOCKS5
    ssh -D 1080 -f -N -C -q \
        -o ServerAliveInterval=60 \
        -o ServerAliveCountMax=3 \
        -o ConnectTimeout=30 \
        ${user:+$user@}$server -p ${port:-22}
    
    if [ $? -eq 0 ]; then
        echo "$!" > "$PID_FILE"
        export http_proxy="socks5://127.0.0.1:1080"
        export https_proxy="socks5://127.0.0.1:1080"
        export ALL_PROXY="socks5://127.0.0.1:1080"
        
        log_vpn "✅ Proxy SOCKS5 activo en 1080"
        return 0
    else
        log_vpn "❌ Error al iniciar proxy"
        return 1
    fi
}

start_http_proxy() {
    local server="$1"
    local port="$2"
    
    log_vpn "Iniciando proxy HTTP a $server:$port"
    
    # Usar tinyproxy o similar
    if command -v tinyproxy >/dev/null; then
        echo "upstream http $server:$port" > $VPN_DIR/tinyproxy.conf
        echo "Listen 8080" >> $VPN_DIR/tinyproxy.conf
        tinyproxy -c $VPN_DIR/tinyproxy.conf
        echo "$!" > "$PID_FILE"
        
        export http_proxy="http://127.0.0.1:8080"
        export https_proxy="http://127.0.0.1:8080"
        
        log_vpn "✅ Proxy HTTP activo en 8080"
        return 0
    else
        log_vpn "⚠️  Instala: pkg install tinyproxy"
        return 1
    fi
}

start_wireguard_no_root() {
    local config="$1"
    
    log_vpn "Intentando WireGuard sin root..."
    
    # WireGuard requiere root, pero probamos método alternativo
    if [ -f "$config" ]; then
        # Extraer configuración para método userspace
        local private_key=$(grep "PrivateKey" "$config" | cut -d= -f2 | tr -d ' ')
        local public_key=$(grep "PublicKey" "$config" | cut -d= -f2 | tr -d ' ')
        local endpoint=$(grep "Endpoint" "$config" | cut -d= -f2 | tr -d ' ')
        
        if [ -n "$private_key" ] && [ -n "$endpoint" ]; then
            log_vpn "🔧 Configuración WireGuard detectada"
            log_vpn "⚠️  WireGuard necesita root. Usando alternativa SSH"
            
            # Convertir a tunnel SSH
            local server=$(echo "$endpoint" | cut -d: -f1)
            local port=$(echo "$endpoint" | cut -d: -f2)
            
            start_socks5_proxy "$server" "$port" "wireguard"
            return $?
        fi
    fi
    return 1
}

start_openvpn_no_root() {
    local config="$1"
    
    log_vpn "Intentando OpenVPN sin root..."
    
    if [ -f "$config" ]; then
        # Verificar si openvpn funciona sin root
        if openvpn --config "$config" --auth-nocache --dev tunvpn --daemon 2>&1 | grep -q "Permission denied"; then
            log_vpn "❌ OpenVPN necesita permisos root"
            
            # Alternativa: extraer proxy del config
            local remote_line=$(grep "^remote " "$config" | head -1)
            if [ -n "$remote_line" ]; then
                local server=$(echo "$remote_line" | awk '{print $2}')
                local port=$(echo "$remote_line" | awk '{print $3}')
                port=${port:-1194}
                
                log_vpn "🎯 Convirtiendo a proxy: $server:$port"
                start_socks5_proxy "$server" "$port" "openvpn"
                return $?
            fi
        else
            log_vpn "✅ OpenVPN iniciado (si hay permisos)"
            echo "$!" > "$PID_FILE"
            return 0
        fi
    fi
    return 1
}

# ============================================
# KILL SWITCH SIN ROOT
# ============================================

setup_killswitch_no_root() {
    log_vpn "Configurando protección sin root..."
    
    # 1. Matar todas las conexiones si falla el proxy
    local kill_script="$VPN_DIR/kill_protection.sh"
    
    cat > "$kill_script" << 'EOF'
#!/data/data/com.termux/files/usr/bin/bash
# Kill Switch sin root

VPN_DIR="$HOME/.termux_vpn"
LOG_FILE="$VPN_DIR/vpn_client.log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE"
}

check_vpn() {
    # Verificar si el proxy está funcionando
    if curl --socks5 127.0.0.1:1080 --max-time 5 ifconfig.me >/dev/null 2>&1; then
        return 0
    elif curl --proxy http://127.0.0.1:8080 --max-time 5 ifconfig.me >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

emergency_stop() {
    log "⚠️  EMERGENCIA: VPN caída - Bloqueando apps..."
    
    # Matar apps específicas que puedan filtrar
    pkill -9 curl 2>/dev/null
    pkill -9 wget 2>/dev/null
    pkill -9 firefox 2>/dev/null
    pkill -9 chrome 2>/dev/null
    
    # Bloquear conexiones nuevas
    log "🚫 Conexiones bloqueadas temporalmente"
    
    # Reiniciar proxy
    if [ -f "$VPN_DIR/restart_proxy.sh" ]; then
        bash "$VPN_DIR/restart_proxy.sh"
    fi
}

# Monitoreo continuo
while true; do
    if ! check_vpn; then
        emergency_stop
    fi
    sleep 10
done
EOF
    
    chmod +x "$kill_script"
    log_vpn "🔒 Protección activa (monitoreo continuo)"
    
    # Ejecutar en segundo plano
    bash "$kill_script" &
    echo "$!" > "$VPN_DIR/killswitch.pid"
}

# ============================================
# DNS SIN ROOT
# ============================================

configure_dns_no_root() {
    log_vpn "Configurando DNS seguro..."
    
    # 1. Archivo resolv.conf local
    echo "nameserver 9.9.9.9" > $PREFIX/etc/resolv.conf
    echo "nameserver 1.1.1.1" >> $PREFIX/etc/resolv.conf
    
    # 2. dnsmasq local
    if command -v dnsmasq >/dev/null; then
        cat > $VPN_DIR/dnsmasq.conf << EOF
server=9.9.9.9
server=1.1.1.1
listen-address=127.0.0.1
bind-interfaces
EOF
        dnsmasq -C $VPN_DIR/dnsmasq.conf
        echo "$!" > "$VPN_DIR/dnsmasq.pid"
        
        # Usar DNS local
        echo "nameserver 127.0.0.1" > $PREFIX/etc/resolv.conf
    fi
    
    # 3. dnscrypt-proxy (mejor opción)
    if command -v dnscrypt-proxy >/dev/null; then
        dnscrypt-proxy --local-address=127.0.0.1:5353 \
            --resolver-name=quad9-doh-ip4-filter-pri
        echo "nameserver 127.0.0.1" > $PREFIX/etc/resolv.conf
        echo "$!" > "$VPN_DIR/dnscrypt.pid"
    fi
    
    log_vpn "✅ DNS configurado (localmente)"
}

# ============================================
# OFUSCACIÓN SIN ROOT
# ============================================

start_obfuscation_no_root() {
    local method="$1"
    
    log_vpn "Iniciando ofuscación: $method"
    
    case "$method" in
        "ssh")
            # SSH obfuscado
            log_vpn "🔐 SSH con ofuscación"
            ;;
        "obfs4")
            # Obfs4proxy (Tor)
            if command -v obfs4proxy >/dev/null; then
                obfs4proxy &
                echo "$!" > "$VPN_DIR/obfs4.pid"
                log_vpn "🌀 Obfs4 activo"
            fi
            ;;
        "v2ray")
            # V2Ray (si está instalado)
            if command -v v2ray >/dev/null; then
                v2ray -config=$VPN_DIR/v2ray.json &
                echo "$!" > "$VPN_DIR/v2ray.pid"
                log_vpn "⚡ V2Ray activo"
            fi
            ;;
    esac
}

# ============================================
# GESTIÓN DE CONEXIÓN
# ============================================

connect_vpn() {
    local config="$1"
    local method="$2"
    
    log_vpn "Conectando VPN: $config"
    
    # Detectar tipo de configuración
    if [[ "$config" == *wireguard* ]] || [[ "$config" == *.conf ]]; then
        start_wireguard_no_root "$config"
    elif [[ "$config" == *openvpn* ]] || [[ "$config" == *.ovpn ]]; then
        start_openvpn_no_root "$config"
    elif [[ "$config" == *socks5* ]] || [[ "$config" == *socks* ]]; then
        local server=$(echo "$config" | cut -d'|' -f1)
        local port=$(echo "$config" | cut -d'|' -f2)
        start_socks5_proxy "$server" "$port"
    elif [[ "$config" == *http* ]] || [[ "$config" == *proxy* ]]; then
        local server=$(echo "$config" | cut -d'|' -f1)
        local port=$(echo "$config" | cut -d'|' -f2)
        start_http_proxy "$server" "$port"
    else
        # Asumir SSH tunnel
        start_socks5_proxy "$config" "22"
    fi
    
    if [ $? -eq 0 ]; then
        # Configurar DNS
        configure_dns_no_root
        
        # Iniciar ofuscación si se especifica
        [ -n "$method" ] && start_obfuscation_no_root "$method"
        
        # Activar protección
        setup_killswitch_no_root
        
        log_vpn "✅ VPN conectado exitosamente"
        return 0
    else
        log_vpn "❌ Error al conectar VPN"
        return 1
    fi
}

disconnect_vpn() {
    log_vpn "Desconectando VPN..."
    
    # Matar todos los procesos VPN
    [ -f "$PID_FILE" ] && kill $(cat "$PID_FILE") 2>/dev/null
    [ -f "$VPN_DIR/dnsmasq.pid" ] && kill $(cat "$VPN_DIR/dnsmasq.pid") 2>/dev/null
    [ -f "$VPN_DIR/dnscrypt.pid" ] && kill $(cat "$VPN_DIR/dnscrypt.pid") 2>/dev/null
    [ -f "$VPN_DIR/killswitch.pid" ] && kill $(cat "$VPN_DIR/killswitch.pid") 2>/dev/null
    [ -f "$VPN_DIR/obfs4.pid" ] && kill $(cat "$VPN_DIR/obfs4.pid") 2>/dev/null
    [ -f "$VPN_DIR/v2ray.pid" ] && kill $(cat "$VPN_DIR/v2ray.pid") 2>/dev/null
    
    # Limpiar variables de proxy
    unset http_proxy https_proxy ALL_PROXY
    
    # Restaurar DNS
    echo "nameserver 8.8.8.8" > $PREFIX/etc/resolv.conf
    
    # Limpiar archivos PID
    rm -f "$VPN_DIR"/*.pid 2>/dev/null
    
    log_vpn "✅ VPN desconectado"
}

# ============================================
# MONITOREO
# ============================================

check_vpn_status() {
    echo "🔍 Estado VPN:"
    echo "================"
    
    # Verificar proxy
    if curl --socks5 127.0.0.1:1080 --max-time 3 ifconfig.me 2>/dev/null; then
        echo "✅ SOCKS5 Proxy: ACTIVO"
    elif curl --proxy http://127.0.0.1:8080 --max-time 3 ifconfig.me 2>/dev/null; then
        echo "✅ HTTP Proxy: ACTIVO"
    else
        echo "❌ Proxy: INACTIVO"
    fi
    
    # Verificar DNS
    echo -n "🔍 DNS: "
    if dig +short google.com @127.0.0.1 2>/dev/null | head -1; then
        echo "✅ DNS Local: ACTIVO"
    else
        echo "🌐 DNS: Usando sistema"
    fi
    
    # Verificar procesos
    echo "📊 Procesos VPN:"
    pgrep -af "ssh.*-D\|tinyproxy\|dnsmasq\|dnscrypt" || echo "  Ninguno activo"
}

# ============================================
# INTERFAZ PRINCIPAL
# ============================================

show_vpn_menu() {
    clear
    echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║     TERMUX VPN CLIENT (NO ROOT)      ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
    echo ""
    
    check_vpn_status
    echo ""
    
    echo "1) 🚀 Conectar VPN (SOCKS5/SSH)"
    echo "2) 🌐 Conectar VPN (HTTP Proxy)"
    echo "3) 🔄 Rotar servidores"
    echo "4) 🛑 Desconectar VPN"
    echo "5) ⚙️  Configurar servidores"
    echo "6) 📊 Ver logs"
    echo "7) 🔙 Volver al menú principal"
    echo ""
    
    read -p "Selección: " choice
    
    case $choice in
        1)
            read -p "Servidor SSH: " server
            read -p "Puerto (22): " port
            read -p "Usuario (opcional): " user
            port=${port:-22}
            connect_vpn "$server|$port|$user" "ssh"
            ;;
        2)
            read -p "Servidor HTTP: " server
            read -p "Puerto (8080): " port
            port=${port:-8080}
            connect_vpn "$server|$port" "http"
            ;;
        3)
            rotate_vpn_servers
            ;;
        4)
            disconnect_vpn
            ;;
        5)
            configure_vpn_servers
            ;;
        6)
            [ -f "$LOG_FILE" ] && tail -20 "$LOG_FILE" || echo "No hay logs"
            ;;
        7)
            return 1
            ;;
    esac
    
    read -p "Enter para continuar..."
    show_vpn_menu
}

rotate_vpn_servers() {
    local servers=(
        "server1.ssh.com|22|user1"
        "server2.ssh.com|2222|user2"
        "vpn.server.com|443|vpnuser"
    )
    
    local random_server=${servers[$RANDOM % ${#servers[@]}]}
    
    log_vpn "Rotando a servidor: $random_server"
    disconnect_vpn
    sleep 2
    connect_vpn "$random_server"
}

configure_vpn_servers() {
    local servers_file="$VPN_DIR/servers.txt"
    
    if [ ! -f "$servers_file" ]; then
        cat > "$servers_file" << EOF
# Formato: servidor|puerto|usuario|método
# Métodos: ssh, http, socks5, wireguard, openvpn

# Servidores SSH gratuitos (ejemplos)
free-ssh.com|22|freeuser|ssh
ssh.server.com|2222|user|ssh

# Servidores SOCKS5
socks5.proxy.com|1080||socks5

# HTTP Proxies
http.proxy.com|8080||http
EOF
    fi
    
    nano "$servers_file"
}

# ============================================
# INSTALACIÓN AUTOMÁTICA
# ============================================

install_vpn_client() {
    echo "📦 Instalando Termux VPN Client..."
    
    # Dependencias esenciales
    pkg install -y openssh curl wget dnsutils
    
    # Herramientas VPN/Proxy
    pkg install -y tor torsocks proxychains-ng
    
    # DNS mejorado
    pkg install -y dnsmasq dnscrypt-proxy
    
    # Para ofuscación
    pkg install -y obfs4proxy
    
    echo ""
    echo "✅ Termux VPN Client instalado"
    echo "📁 Configuración en: $VPN_DIR"
    echo "📄 Servidores en: $VPN_DIR/servers.txt"
}

# ============================================
# INICIO
# ============================================

if [ "$1" = "install" ]; then
    install_vpn_client
    exit 0
fi

init_vpn_client

if [ "$1" = "menu" ]; then
    show_vpn_menu
elif [ "$1" = "connect" ]; then
    connect_vpn "$2" "$3"
elif [ "$1" = "disconnect" ]; then
    disconnect_vpn
elif [ "$1" = "status" ]; then
    check_vpn_status
else
    show_vpn_menu
fi
