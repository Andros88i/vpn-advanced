# 🛡️ VPN Advanced para Termux

Sistema avanzado de VPN con ofuscación, rotación automática y kill switch para Termux en Android.

## ✨ Características Principales

### 🔒 Seguridad Avanzada
- **Kill Switch** con iptables que bloquea todo tráfico si VPN cae
- **Ofuscación DPI-proof** mediante Shadowsocks y Stunnel
- **Bloqueo IPv6** completo para prevenir fugas
- **DNS seguro** con Quad9 y Cloudflare sobre TLS

### 🔄 Rotación Inteligente
- Cambio automático entre configuraciones cada X minutos
- **Balanceo de carga** basado en latencia
- **Failover automático** ante caídas de conexión
- **Pruebas de conectividad** continuas

### 📊 Monitoreo y Logging
- Logs detallados de todas las operaciones
- Estadísticas de uso por configuración
- Detección de fugas DNS en tiempo real
- Notificaciones de estado

## 📁 Estructura del Proyecto

vpn-advanced/
├── configs/ # Configuraciones VPN
├── scripts/ # Scripts principales
├── logs/ # Logs del sistema
├── lists/ # Listas de configuración
├── backups/ # Backups de reglas
└── README.md # Esta documentación

## 📦 Dependencias Requeridas

# Paquetes base
pkg install python bash curl wget iptables openssl

# Herramientas VPN
pkg install openvpn wireguard-tools shadowsocks-libev

# Python dependencies
pip install requests psutil schedule ping3

# Monitoreo
pkg install net-tools dnsutils nmap
