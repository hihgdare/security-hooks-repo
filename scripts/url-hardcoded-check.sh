#!/bin/bash

# Verificación de URLs hardcodeadas
# Este script detecta URLs de APIs que deberían estar en variables de entorno

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🌐 Verificando URLs hardcodeadas...${NC}"

# Configuración
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
CONFIG_FILE="$PROJECT_ROOT/.security-config.yml"

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
if [ -f "$CONFIG_FILE" ]; then
    # Extraer dominios permitidos del YAML (implementación básica)
    ADDITIONAL_DOMAINS=$(grep -A 10 "allowed_domains:" "$CONFIG_FILE" 2>/dev/null | grep "^\s*-" | sed 's/^\s*-\s*//' | tr -d '"' || true)
    if [ -n "$ADDITIONAL_DOMAINS" ]; then
        echo -e "${BLUE}📋 Cargando dominios permitidos adicionales desde configuración${NC}"
        while read -r domain; do
            ALLOWED_DOMAINS+=("$domain")
        done <<< "$ADDITIONAL_DOMAINS"
    fi
fi

# Crear patrón de exclusión
EXCLUSION_PATTERN=$(IFS='|'; echo "${ALLOWED_DOMAINS[*]}")

# Archivos a verificar
FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '\.(ts|tsx|js|jsx|py|go|rs|java)$' | grep -v -E '^(node_modules/|\.git/|dist/|build/|.*\.test\.|.*\.spec\.|.*\.mock\.)' || true)

if [ -z "$FILES" ]; then
    echo -e "${GREEN}✅ No hay archivos de código para verificar${NC}"
    exit 0
fi

echo "Archivos a verificar:"
echo "$FILES" | sed 's/^/  - /'

URLS_FOUND=false
TOTAL_URLS=0

# Buscar URLs HTTP/HTTPS
echo -e "\n${BLUE}🔍 Buscando URLs HTTP/HTTPS...${NC}"

# Patrón para detectar URLs
URL_PATTERN="https?://[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}[^\s'\"\)]*"

# Buscar URLs en archivos
FOUND_URLS=$(echo "$FILES" | xargs grep -n -E "$URL_PATTERN" 2>/dev/null | grep -v -E "($EXCLUSION_PATTERN)" || true)

if [ -n "$FOUND_URLS" ]; then
    echo -e "${RED}❌ URLs hardcodeadas encontradas:${NC}"
    echo ""
    
    # Procesar cada URL encontrada
    echo "$FOUND_URLS" | while read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        line_num=$(echo "$line" | cut -d: -f2)
        content=$(echo "$line" | cut -d: -f3-)
        
        echo -e "${RED}  📄 $file:$line_num${NC}"
        echo -e "${YELLOW}     $content${NC}"
        
        # Extraer la URL específica
        url=$(echo "$content" | grep -o -E "$URL_PATTERN" | head -1)
        if [ -n "$url" ]; then
            domain=$(echo "$url" | sed -E 's|https?://([^/]+).*|\1|')
            echo -e "${BLUE}     🌐 Dominio: $domain${NC}"
        fi
        echo ""
    done
    
    URLS_FOUND=true
    TOTAL_URLS=$(echo "$FOUND_URLS" | wc -l)
fi

# Buscar patrones específicos de configuración de API
echo -e "\n${BLUE}🔍 Buscando configuraciones de API...${NC}"

API_PATTERNS=(
    "baseURL\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "apiUrl\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "endpoint\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "server\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "host\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
    "url\s*[=:]\s*['\"]https?://[^'\"]*['\"]"
)

for pattern in "${API_PATTERNS[@]}"; do
    API_MATCHES=$(echo "$FILES" | xargs grep -n -E -i "$pattern" 2>/dev/null | grep -v -E "($EXCLUSION_PATTERN)" || true)
    
    if [ -n "$API_MATCHES" ]; then
        if [ "$URLS_FOUND" = false ]; then
            echo -e "${RED}❌ Configuraciones de API hardcodeadas encontradas:${NC}"
            echo ""
        fi
        
        echo "$API_MATCHES" | while read -r line; do
            file=$(echo "$line" | cut -d: -f1)
            line_num=$(echo "$line" | cut -d: -f2)
            content=$(echo "$line" | cut -d: -f3-)
            
            echo -e "${RED}  📄 $file:$line_num${NC}"
            echo -e "${YELLOW}     $content${NC}"
            echo ""
        done
        
        URLS_FOUND=true
        TOTAL_URLS=$((TOTAL_URLS + $(echo "$API_MATCHES" | wc -l)))
    fi
done

# Buscar fetch/axios calls con URLs hardcodeadas
echo -e "\n${BLUE}🔍 Verificando llamadas HTTP...${NC}"

HTTP_CALLS=$(echo "$FILES" | xargs grep -n -E "(fetch|axios\.(get|post|put|delete|patch))\s*\(\s*['\"]https?://[^'\"]*['\"]" 2>/dev/null | grep -v -E "($EXCLUSION_PATTERN)" || true)

if [ -n "$HTTP_CALLS" ]; then
    if [ "$URLS_FOUND" = false ]; then
        echo -e "${RED}❌ Llamadas HTTP con URLs hardcodeadas encontradas:${NC}"
        echo ""
    fi
    
    echo "$HTTP_CALLS" | while read -r line; do
        file=$(echo "$line" | cut -d: -f1)
        line_num=$(echo "$line" | cut -d: -f2)
        content=$(echo "$line" | cut -d: -f3-)
        
        echo -e "${RED}  📄 $file:$line_num${NC}"
        echo -e "${YELLOW}     $content${NC}"
        echo ""
    done
    
    URLS_FOUND=true
    TOTAL_URLS=$((TOTAL_URLS + $(echo "$HTTP_CALLS" | wc -l)))
fi

# Resultado final
echo -e "\n${BLUE}📊 Resumen de verificación de URLs:${NC}"

if [ "$URLS_FOUND" = true ]; then
    echo -e "${RED}❌ Se encontraron $TOTAL_URLS URLs hardcodeadas${NC}"
    echo ""
    echo -e "${YELLOW}🔧 Para solucionar:${NC}"
    echo ""
    echo -e "${YELLOW}1. Mover URLs a variables de entorno:${NC}"
    echo -e "${YELLOW}   // Antes (❌)${NC}"
    echo -e "${YELLOW}   const apiUrl = 'https://api.miapp.com';${NC}"
    echo ""
    echo -e "${YELLOW}   // Después (✅)${NC}"
    echo -e "${YELLOW}   const apiUrl = process.env.REACT_APP_API_URL;${NC}"
    echo -e "${YELLOW}   // o para Vite:${NC}"
    echo -e "${YELLOW}   const apiUrl = import.meta.env.VITE_API_URL;${NC}"
    echo ""
    echo -e "${YELLOW}2. Crear archivo .env.example con:${NC}"
    echo -e "${YELLOW}   REACT_APP_API_URL=https://api.example.com${NC}"
    echo -e "${YELLOW}   VITE_API_URL=https://api.example.com${NC}"
    echo ""
    echo -e "${YELLOW}3. Agregar dominios permitidos en .security-config.yml:${NC}"
    echo -e "${YELLOW}   url_check:${NC}"
    echo -e "${YELLOW}     allowed_domains:${NC}"
    echo -e "${YELLOW}       - 'mi-api-publica.com'${NC}"
    echo -e "${YELLOW}       - 'cdn.miapp.com'${NC}"
    echo ""
    echo -e "${RED}🚫 Commit bloqueado por URLs hardcodeadas${NC}"
    exit 1
else
    echo -e "${GREEN}✅ No se encontraron URLs problemáticas hardcodeadas${NC}"
    exit 0
fi