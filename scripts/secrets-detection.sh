#!/usr/bin/env bash

# Detección de secretos y credenciales hardcodeadas
# Este script busca patrones de API keys, tokens y otros secretos

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔐 Ejecutando detección de secretos...${NC}"

# Detectar entorno Windows/PowerShell
IS_WINDOWS=false
IS_POWERSHELL=false

# Detectar Windows por múltiples métodos
if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]] || [[ "$OSTYPE" == "win32" ]] || [[ -n "$WINDIR" ]] || [[ -n "$SYSTEMROOT" ]]; then
    IS_WINDOWS=true
fi

# Detectar PowerShell
if [[ -n "$PSVersionTable" ]] || [[ "$SHELL" == *"powershell"* ]] || [[ -n "$POWERSHELL_DISTRIBUTION_CHANNEL" ]]; then
    IS_POWERSHELL=true
    IS_WINDOWS=true
fi

if [ "$IS_WINDOWS" = true ]; then
    if [ "$IS_POWERSHELL" = true ]; then
        echo -e "${BLUE}🔵 PowerShell en Windows detectado - aplicando ajustes específicos${NC}"
    else
        echo -e "${BLUE}🧠 Entorno Windows detectado - aplicando ajustes de compatibilidad${NC}"
    fi
fi

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
CONFIG_FILE="$PROJECT_ROOT/.security-config.yml"

# Normalizar paths para Windows
if [ "$IS_WINDOWS" = true ]; then
    SCRIPT_DIR=$(cygpath -u "$SCRIPT_DIR" 2>/dev/null || echo "$SCRIPT_DIR")
    PROJECT_ROOT=$(cygpath -u "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")
fi

# Patrones de secretos a detectar
PATTERNS=(
    # API Keys generales
    "api[_-]?key\s*[=:]\s*['\"][^'\"]{20,}"
    "apikey\s*[=:]\s*['\"][^'\"]{20,}"
    
    # Tokens
    "token\s*[=:]\s*['\"][^'\"]{20,}"
    "auth[_-]?token\s*[=:]\s*['\"][^'\"]{20,}"
    "bearer[_-]?token\s*[=:]\s*['\"][^'\"]{20,}"
    "access[_-]?token\s*[=:]\s*['\"][^'\"]{20,}"
    "refresh[_-]?token\s*[=:]\s*['\"][^'\"]{20,}"
    
    # Secretos
    "secret\s*[=:]\s*['\"][^'\"]{20,}"
    "client[_-]?secret\s*[=:]\s*['\"][^'\"]{20,}"
    "app[_-]?secret\s*[=:]\s*['\"][^'\"]{20,}"
    
    # Passwords
    "password\s*[=:]\s*['\"][^'\"]{8,}"
    "passwd\s*[=:]\s*['\"][^'\"]{8,}"
    "pwd\s*[=:]\s*['\"][^'\"]{8,}"
    
    # AWS
    "aws[_-]?access[_-]?key[_-]?id\s*[=:]\s*['\"][^'\"]{16,}"
    "aws[_-]?secret[_-]?access[_-]?key\s*[=:]\s*['\"][^'\"]{32,}"
    
    # GitHub
    "github[_-]?token\s*[=:]\s*['\"]gh[ps]_[A-Za-z0-9_]{36,255}"
    
    # Google
    "google[_-]?api[_-]?key\s*[=:]\s*['\"][^'\"]{35,45}"
    
    # Firebase
    "firebase[_-]?api[_-]?key\s*[=:]\s*['\"][^'\"]{35,45}"
    
    # JWT
    "jwt[_-]?secret\s*[=:]\s*['\"][^'\"]{20,}"
    
    # Database URLs
    "database[_-]?url\s*[=:]\s*['\"][^'\"]*://[^'\"]*:[^'\"]*@[^'\"]*"
    "db[_-]?url\s*[=:]\s*['\"][^'\"]*://[^'\"]*:[^'\"]*@[^'\"]*"
    
    # Slack
    "slack[_-]?token\s*[=:]\s*['\"]xox[bpsr]-[^'\"]*"
    
    # Discord
    "discord[_-]?token\s*[=:]\s*['\"][^'\"]{50,}"
    
    # Stripe
    "stripe[_-]?key\s*[=:]\s*['\"][rs]k_[live|test]_[^'\"]*"
    
    # SendGrid
    "sendgrid[_-]?api[_-]?key\s*[=:]\s*['\"]SG\.[^'\"]*"
    
    # Twilio
    "twilio[_-]?sid\s*[=:]\s*['\"]AC[^'\"]*"
    "twilio[_-]?token\s*[=:]\s*['\"][^'\"]{32,}"
    
    # Claves privadas
    "-----BEGIN\s+(RSA\s+|EC\s+|DSA\s+|)?PRIVATE\s+KEY-----"
    "-----BEGIN\s+OPENSSH\s+PRIVATE\s+KEY-----"
    
    # Certificates
    "-----BEGIN\s+CERTIFICATE-----"
    
    # Generic high entropy strings (posibles secretos)
    "['\"][A-Za-z0-9+/]{40,}={0,2}['\"]"  # Base64 encoded
)

# Archivos a verificar
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(ts|tsx|js|jsx|json|py|go|rs|java|yml|yaml|sh|env)$' | grep -v -E '^(node_modules/|\.git/|dist/|build/|\.env\.example|\.env\.template)' || true)

# En Windows, normalizar separadores de path
if [ "$IS_WINDOWS" = true ]; then
    FILES=$(echo "$FILES" | sed 's|\\|/|g')
fi

if [ -z "$FILES" ]; then
    echo -e "${GREEN}✅ No hay archivos relevantes para verificar${NC}"
    exit 0
fi

echo "Archivos a escanear:"
echo "$FILES" | sed 's/^/  - /'

SECRETS_FOUND=false
TOTAL_MATCHES=0

# Función para verificar patrones
check_pattern() {
    local pattern="$1"
    local description="$2"
    
    echo -e "\n${BLUE}🔍 Buscando: $description${NC}"
    
    local matches=$(echo "$FILES" | xargs grep -l -E -i "$pattern" 2>/dev/null || true)
    
    if [ -n "$matches" ]; then
        SECRETS_FOUND=true
        echo -e "${RED}❌ Patrón encontrado en:${NC}"
        echo "$matches" | while read -r file; do
            echo -e "${RED}  📄 $file${NC}"
            # Mostrar las líneas que coinciden (sin mostrar el secreto completo)
            grep -n -E -i "$pattern" "$file" 2>/dev/null | head -3 | while read -r line; do
                line_num=$(echo "$line" | cut -d: -f1)
                content=$(echo "$line" | cut -d: -f2- | sed 's/['\''"][^'\''\"]*['\''"]/**REDACTED**/g')
                echo -e "${YELLOW}    Línea $line_num: $content${NC}"
            done
        done
        TOTAL_MATCHES=$((TOTAL_MATCHES + 1))
        return 1
    else
        echo -e "${GREEN}✅ No encontrado${NC}"
        return 0
    fi
}

# Verificar cada patrón
echo -e "\n${BLUE}🔍 Ejecutando detección de patrones...${NC}"

check_pattern "api[_-]?key\s*[=:]\s*['\"][^'\"]{20,}" "API Keys"
check_pattern "token\s*[=:]\s*['\"][^'\"]{20,}" "Tokens genéricos"
check_pattern "secret\s*[=:]\s*['\"][^'\"]{20,}" "Secretos genéricos"
check_pattern "password\s*[=:]\s*['\"][^'\"]{8,}" "Passwords"
check_pattern "aws[_-]?access[_-]?key" "AWS Access Keys"
check_pattern "github[_-]?token" "GitHub Tokens"
check_pattern "slack[_-]?token" "Slack Tokens"
check_pattern "stripe[_-]?key" "Stripe Keys"
check_pattern "-----BEGIN.*PRIVATE.*KEY-----" "Claves privadas"

# Verificar patrones específicos de alta entropía
echo -e "\n${BLUE}🔍 Verificando strings de alta entropía...${NC}"
HIGH_ENTROPY_MATCHES=$(echo "$FILES" | xargs grep -E "['\"][A-Za-z0-9+/]{40,}={0,2}['\"]" 2>/dev/null || true)
if [ -n "$HIGH_ENTROPY_MATCHES" ]; then
    echo -e "${YELLOW}⚠️  Strings de alta entropía encontrados (posibles secretos codificados):${NC}"
    echo "$HIGH_ENTROPY_MATCHES" | head -5 | while read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        line_num=$(echo "$line" | cut -d: -f2)
        echo -e "${YELLOW}  📄 $file:$line_num${NC}"
    done
    echo -e "${YELLOW}💡 Revisa si estos strings son secretos que deberían estar en variables de entorno${NC}"
fi

# Verificar variables de entorno sospechosas
echo -e "\n${BLUE}🔍 Verificando variables de entorno sospechosas...${NC}"
ENV_VARS=$(echo "$FILES" | xargs grep -E "(process\.env\.|import\.meta\.env\.)" 2>/dev/null | grep -v -E "(NODE_ENV|PUBLIC_|VITE_|NEXT_PUBLIC_)" || true)
if [ -n "$ENV_VARS" ]; then
    echo -e "${YELLOW}⚠️  Variables de entorno privadas encontradas:${NC}"
    echo "$ENV_VARS" | head -5 | while read -r line; do
        echo -e "${YELLOW}  $line${NC}"
    done
    echo -e "${YELLOW}💡 Asegúrate de que estas variables no contengan secretos${NC}"
fi

# Resultado final
echo -e "\n${BLUE}📊 Resumen de detección de secretos:${NC}"

if [ "$SECRETS_FOUND" = true ]; then
    echo -e "${RED}❌ Se encontraron $TOTAL_MATCHES patrones de secretos${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Para solucionar:${NC}"
    echo -e "${YELLOW}1. Mover secretos a variables de entorno${NC}"
    echo -e "${YELLOW}2. Usar archivos .env (y agregarlos a .gitignore)${NC}"
    echo -e "${YELLOW}3. Considerar usar servicios de gestión de secretos${NC}"
    echo -e "${YELLOW}4. Para variables frontend, usar prefijos seguros (VITE_, NEXT_PUBLIC_, etc.)${NC}"
    echo ""
    echo -e "${RED}🚫 Commit bloqueado por seguridad${NC}"
    echo -e "${RED}🚫 SECRETS DETECTION FAILED - COMMIT REJECTED${NC}"
    
    # Manejo específico para PowerShell
    if [ "$IS_POWERSHELL" = true ]; then
        echo "SECRETS FOUND: $TOTAL_MATCHES" >&2
        echo "RESULT: BLOCKED" >&2
        sleep 0.1
    fi
    
    # Flush output para Windows
    exec 1>&1 2>&2
    exit 1
else
    echo -e "${GREEN}✅ No se detectaron secretos hardcodeados${NC}"
    
    # Manejo específico para PowerShell
    if [ "$IS_POWERSHELL" = true ]; then
        echo "RESULT: SUCCESS"
        sleep 0.1
    fi
    
    # Flush output para Windows
    exec 1>&1 2>&2
    exit 0
fi