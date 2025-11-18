#!/usr/bin/env bash

# Detección de secretos y credenciales hardcodeadas
# Este script busca patrones de API keys, tokens y otros secretos
# Compatible con Windows (Git Bash/PowerShell/WSL), macOS y Linux

set -e

# Configuración inicial
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar biblioteca de compatibilidad multiplataforma
if [[ -f "$SCRIPT_DIR/platform-compatibility.sh" ]]; then
    source "$SCRIPT_DIR/platform-compatibility.sh"
else
    echo "❌ Error: No se encontró platform-compatibility.sh" >&2
    exit 1
fi

safe_echo "info" "Ejecutando detección de secretos..."

# Configuración
PROJECT_ROOT=$(get_git_root)
CONFIG_FILE="$PROJECT_ROOT/.security-config.yml"
SCRIPT_DIR=$(normalize_path "$SCRIPT_DIR")
PROJECT_ROOT=$(normalize_path "$PROJECT_ROOT")

# Archivos a verificar
FILES=$(get_modified_files "ACM" '\.(ts|tsx|js|jsx|json|py|go|rs|java|yml|yaml|sh|env)$' | grep -v -E '^(node_modules/|\.git/|dist/|build/|\.env\.example|\.env\.template)' || true)

if [[ -z "$FILES" ]]; then
    safe_echo "success" "No hay archivos relevantes para verificar"
    safe_exit 0
fi

safe_echo "info" "Archivos a escanear:"
echo "$FILES" | sed 's/^/  - /'

SECRETS_FOUND=false
TOTAL_MATCHES=0

# Función para verificar patrones
check_pattern() {
    local pattern="$1"
    local description="$2"
    
    safe_echo "info" "Buscando: $description"
    
    local matches
    matches=$(search_pattern "$pattern" "$FILES" "-l -E -i")
    
    if [[ -n "$matches" ]]; then
        SECRETS_FOUND=true
        safe_echo "error" "Patrón encontrado en:"
        echo "$matches" | while read -r file; do
            safe_echo "error" "  📄 $file"
            # Mostrar las líneas que coinciden (sin mostrar el secreto completo)
            search_pattern "$pattern" "$file" "-n -E -i" | head -3 | while read -r line; do
                line_num=$(echo "$line" | cut -d: -f1)
                content=$(echo "$line" | cut -d: -f2- | sed 's/['\''"][^'\''\"]*['\''"]/**REDACTED**/g')
                safe_echo "warning" "    Línea $line_num: $content"
            done
        done
        TOTAL_MATCHES=$((TOTAL_MATCHES + 1))
        return 1
    else
        safe_echo "success" "No encontrado"
        return 0
    fi
}

# Verificar cada patrón
safe_echo "info" "Ejecutando detección de patrones..."

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
safe_echo "info" "Verificando strings de alta entropía..."
HIGH_ENTROPY_MATCHES=$(search_pattern "['\"][A-Za-z0-9+/]{40,}={0,2}['\"]" "$FILES")

if [[ -n "$HIGH_ENTROPY_MATCHES" ]]; then
    safe_echo "warning" "Strings de alta entropía encontrados (posibles secretos codificados):"
    echo "$HIGH_ENTROPY_MATCHES" | head -5 | while read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        line_num=$(echo "$line" | cut -d: -f2)
        safe_echo "warning" "  📄 $file:$line_num"
    done
    safe_echo "warning" "Revisa si estos strings son secretos que deberían estar en variables de entorno"
fi

# Verificar variables de entorno sospechosas
safe_echo "info" "Verificando variables de entorno sospechosas..."
ENV_VARS=$(search_pattern "(process\\.env\\.|import\\.meta\\.env\\.)" "$FILES" | grep -v -E "(NODE_ENV|PUBLIC_|VITE_|NEXT_PUBLIC_)" || true)

if [[ -n "$ENV_VARS" ]]; then
    safe_echo "warning" "Variables de entorno privadas encontradas:"
    echo "$ENV_VARS" | head -5 | while read -r line; do
        safe_echo "warning" "  $line"
    done
    safe_echo "warning" "Asegúrate de que estas variables no contengan secretos"
fi

# Resultado final
safe_echo "info" "Resumen de detección de secretos:"

if [[ "$SECRETS_FOUND" == true ]]; then
    safe_echo "error" "Se encontraron $TOTAL_MATCHES patrones de secretos"
    echo ""
    safe_echo "warning" "Para solucionar:"
    safe_echo "warning" "1. Mover secretos a variables de entorno"
    safe_echo "warning" "2. Usar archivos .env (y agregarlos a .gitignore)"
    safe_echo "warning" "3. Considerar usar servicios de gestión de secretos"
    safe_echo "warning" "4. Para variables frontend, usar prefijos seguros (VITE_, NEXT_PUBLIC_, etc.)"
    safe_exit 1 "SECRETS DETECTION FAILED - COMMIT REJECTED"
else
    safe_echo "success" "No se detectaron secretos hardcodeados"
    safe_exit 0 "SECRETS DETECTION PASSED"
fi