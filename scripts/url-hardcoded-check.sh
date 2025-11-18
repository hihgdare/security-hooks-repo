#!/usr/bin/env bash

# Verificación de URLs hardcodeadas
# Este script detecta URLs de APIs que deberían estar en variables de entorno
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

safe_echo "info" "Verificando URLs hardcodeadas..."

# Configuración
PROJECT_ROOT=$(get_git_root)
CONFIG_FILE="$PROJECT_ROOT/.security-config.yml"
SCRIPT_DIR=$(normalize_path "$SCRIPT_DIR")
PROJECT_ROOT=$(normalize_path "$PROJECT_ROOT")

# URLs permitidas por defecto (no se consideran problemáticas)
ALLOWED_DOMAINS=(
    "localhost"
    "127\.0\.0\.1"
    "0\.0\.0\.0"
    "example\.com"
    "example\.org"
    "test\.com"
    "placeholder\.com"
    "github\.com"
    "gitlab\.com"
    "bitbucket\.org"
    "npmjs\.com"
    "yarnpkg\.com"
    "unpkg\.com"
    "jsdelivr\.net"
    "cdnjs\.cloudflare\.com"
    "fonts\.googleapis\.com"
    "fonts\.gstatic\.com"
    "www\.google\.com"
    "maps\.googleapis\.com"
    "youtube\.com"
    "vimeo\.com"
    "twitter\.com"
    "facebook\.com"
    "linkedin\.com"
    "instagram\.com"
    "api\.github\.com"
    "raw\.githubusercontent\.com"
    "shields\.io"
    "badge\.fury\.io"
    "codecov\.io"
    "coveralls\.io"
    "travis-ci\.(org|com)"
    "circleci\.com"
    "appveyor\.com"
)

# Cargar dominios permitidos adicionales desde configuración
if [[ -f "$CONFIG_FILE" ]]; then
    # Extraer dominios permitidos del YAML (implementación básica)
    ADDITIONAL_DOMAINS=$(grep -A 10 "allowed_domains:" "$CONFIG_FILE" 2>/dev/null | grep "^\s*-" | sed 's/^\s*-\s*//' | tr -d '"' || true)
    if [[ -n "$ADDITIONAL_DOMAINS" ]]; then
        safe_echo "info" "Cargando dominios permitidos adicionales desde configuración"
        while read -r domain; do
            if [[ -n "$domain" ]]; then
                ALLOWED_DOMAINS+=("$domain")
            fi
        done <<< "$ADDITIONAL_DOMAINS"
    fi
fi

# Crear patrón de exclusión
EXCLUSION_PATTERN=$(IFS='|'; echo "${ALLOWED_DOMAINS[*]}")

# Archivos a verificar
FILES=$(get_modified_files "ACM" '\.(ts|tsx|js|jsx|py|go|rs|java)$' | grep -v -E '^(node_modules/|\.git/|dist/|build/|.*\.test\.|.*\.spec\.|.*\.mock\.)' || true)

if [[ -z "$FILES" ]]; then
    safe_echo "success" "No hay archivos de código para verificar"
    safe_exit 0
fi

safe_echo "info" "Archivos a verificar:"
echo "$FILES" | sed 's/^/  - /'

URLS_FOUND=false
TOTAL_URLS=0

# Buscar URLs HTTP/HTTPS
safe_echo "info" "Buscando URLs HTTP/HTTPS..."

# Patrón para detectar URLs
URL_PATTERN="https?://[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}[^\s'\"\)]*"

# Buscar URLs en archivos
FOUND_URLS=$(search_pattern "$URL_PATTERN" "$FILES" "-n -E" | grep -v -E "($EXCLUSION_PATTERN)" || true)

if [[ -n "$FOUND_URLS" ]]; then
    safe_echo "error" "URLs hardcodeadas encontradas:"
    echo ""
    
    # Procesar cada URL encontrada
    echo "$FOUND_URLS" | while read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        line_num=$(echo "$line" | cut -d: -f2)
        content=$(echo "$line" | cut -d: -f3-)
        
        safe_echo "error" "  📄 $file:$line_num"
        safe_echo "warning" "     $content"
        
        # Extraer la URL específica
        url=$(echo "$content" | grep -o -E "$URL_PATTERN" | head -1)
        if [[ -n "$url" ]]; then
            domain=$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')
            safe_echo "info" "     🌐 Dominio: $domain"
        fi
        echo ""
    done
    
    URLS_FOUND=true
    TOTAL_URLS=$(echo "$FOUND_URLS" | wc -l)
fi

# Buscar patrones específicos de configuración de API
safe_echo "info" "Buscando configuraciones de API..."

API_PATTERNS=(
    "baseURL\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "apiUrl\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "endpoint\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "server\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "host\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "url\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
)

for pattern in "${API_PATTERNS[@]}"; do
    API_MATCHES=$(search_pattern "$pattern" "$FILES" "-n -E -i" | grep -v -E "($EXCLUSION_PATTERN)" || true)
    
    if [[ -n "$API_MATCHES" ]]; then
        if [[ "$URLS_FOUND" == false ]]; then
            safe_echo "error" "Configuraciones de API hardcodeadas encontradas:"
            echo ""
        fi
        
        echo "$API_MATCHES" | while read -r line; do
            file=$(echo "$line" | cut -d: -f1)
            line_num=$(echo "$line" | cut -d: -f2)
            content=$(echo "$line" | cut -d: -f3-)
            
            safe_echo "error" "  📄 $file:$line_num"
            safe_echo "warning" "     $content"
            echo ""
        done
        
        URLS_FOUND=true
        TOTAL_URLS=$((TOTAL_URLS + $(echo "$API_MATCHES" | wc -l)))
    fi
done

# Buscar fetch/axios calls con URLs hardcodeadas
safe_echo "info" "Verificando llamadas HTTP..."

HTTP_CALLS=$(search_pattern "(fetch|axios\.(get|post|put|delete|patch))\s*\(\s*['\"]https?://[^'\"]*['\"]" "$FILES" "-n -E" | grep -v -E "($EXCLUSION_PATTERN)" || true)

if [[ -n "$HTTP_CALLS" ]]; then
    if [[ "$URLS_FOUND" == false ]]; then
        safe_echo "error" "Llamadas HTTP con URLs hardcodeadas encontradas:"
        echo ""
    fi
    
    echo "$HTTP_CALLS" | while read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        line_num=$(echo "$line" | cut -d: -f2)
        content=$(echo "$line" | cut -d: -f3-)
        
        safe_echo "error" "  📄 $file:$line_num"
        safe_echo "warning" "     $content"
        echo ""
    done
    
    URLS_FOUND=true
    TOTAL_URLS=$((TOTAL_URLS + $(echo "$HTTP_CALLS" | wc -l)))
fi

# Resultado final
safe_echo "info" "Resumen de verificación de URLs:"

if [[ "$URLS_FOUND" == true ]]; then
    safe_echo "error" "Se encontraron $TOTAL_URLS URLs hardcodeadas"
    echo ""
    safe_echo "warning" "Para solucionar:"
    echo ""
    safe_echo "warning" "1. Mover URLs a variables de entorno:"
    safe_echo "warning" "   // Antes (❌)"
    safe_echo "warning" "   const apiUrl = 'https://api.miapp.com';"
    echo ""
    safe_echo "warning" "   // Después (✅)"
    safe_echo "warning" "   const apiUrl = process.env.REACT_APP_API_URL;"
    safe_echo "warning" "   // o para Vite:"
    safe_echo "warning" "   const apiUrl = import.meta.env.VITE_API_URL;"
    echo ""
    safe_echo "warning" "2. Crear archivo .env.example con:"
    safe_echo "warning" "   REACT_APP_API_URL=https://api.example.com"
    safe_echo "warning" "   VITE_API_URL=https://api.example.com"
    echo ""
    safe_echo "warning" "3. Agregar dominios permitidos en .security-config.yml:"
    safe_echo "warning" "   url_check:"
    safe_echo "warning" "     allowed_domains:"
    safe_echo "warning" "       - 'mi-api-publica.com'"
    safe_echo "warning" "       - 'cdn.miapp.com'"
    echo ""
    safe_exit 1 "URL CHECK FAILED - COMMIT REJECTED"
else
    safe_echo "success" "No se encontraron URLs problemáticas hardcodeadas"
    safe_exit 0 "URL CHECK PASSED"
fi