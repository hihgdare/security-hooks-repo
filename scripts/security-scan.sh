#!/usr/bin/env bash

# Escaneo integral de seguridad
# Este script ejecuta múltiples verificaciones de seguridad

set -e

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔍 Iniciando escaneo integral de seguridad...${NC}"

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
        echo -e "${BLUE}� Entorno Windows detectado - aplicando ajustes de compatibilidad${NC}"
    fi
fi

# Configuración
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
CONFIG_FILE="$PROJECT_ROOT/.security-config.yml"

# Normalizar paths para Windows
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    SCRIPT_DIR=$(cygpath -u "$SCRIPT_DIR" 2>/dev/null || echo "$SCRIPT_DIR")
    PROJECT_ROOT=$(cygpath -u "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")
fi

# Cargar configuración si existe
if [ -f "$CONFIG_FILE" ]; then
    echo -e "${BLUE}📋 Cargando configuración desde $CONFIG_FILE${NC}"
fi

# Función para mostrar resultados
show_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ $2${NC}"
    else
        echo -e "${RED}❌ $2${NC}"
        return 1
    fi
}

# Función para mostrar warnings
warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Variable para trackear errores
ERRORS=0

echo -e "${BLUE}📁 Analizando archivos modificados...${NC}"
FILES_CHANGED=$(git diff --cached --name-only --diff-filter=ACM)

# En Windows, normalizar separadores de path
if [ "$IS_WINDOWS" = true ]; then
    FILES_CHANGED=$(echo "$FILES_CHANGED" | sed 's|\\|/|g')
fi

if [ -z "$FILES_CHANGED" ]; then
    echo -e "${YELLOW}⚠️  No hay archivos en staging para verificar${NC}"
    exit 0
fi

echo "Archivos a verificar:"
echo "$FILES_CHANGED" | sed 's/^/  - /'

# Diagnóstico para Windows/PowerShell
if [ "$IS_WINDOWS" = true ]; then
    echo -e "${BLUE}🔧 Diagnóstico Windows/PowerShell:${NC}"
    echo "  - OSTYPE: $OSTYPE"
    echo "  - Shell: $0"
    echo "  - PowerShell: $IS_POWERSHELL"
    echo "  - Git version: $(git --version 2>/dev/null || echo 'No disponible')"
    echo "  - Script dir: $SCRIPT_DIR"
    echo "  - Project root: $PROJECT_ROOT"
    
    # Variables específicas de PowerShell
    if [ "$IS_POWERSHELL" = true ]; then
        echo "  - WINDIR: ${WINDIR:-'No definido'}"
        echo "  - SYSTEMROOT: ${SYSTEMROOT:-'No definido'}"
        echo "  - POWERSHELL_DISTRIBUTION_CHANNEL: ${POWERSHELL_DISTRIBUTION_CHANNEL:-'No definido'}"
    fi
fi

# 1. Verificar archivos de entorno
echo -e "\n${BLUE}🔒 Verificando archivos de entorno...${NC}"
if echo "$FILES_CHANGED" | grep -E "^\.env$|^\.env\.local$|^\.env\.production$" | grep -v "\.env\.example\|\.env\.template"; then
    echo -e "${RED}❌ Archivos .env detectados en commit${NC}"
    echo -e "${YELLOW}💡 Los archivos .env no deben commitearse. Usar .env.example en su lugar.${NC}"
    ERRORS=$((ERRORS + 1))
else
    show_result 0 "No se detectaron archivos .env problemáticos"
fi

# 2. Ejecutar detección de secretos
echo -e "\n${BLUE}🔐 Ejecutando detección de secretos...${NC}"
set +e  # Temporalmente deshabilitar exit en error para capturar código
"$SCRIPT_DIR/secrets-detection.sh"
SECRETS_EXIT_CODE=$?
set -e  # Re-habilitar exit en error

# Manejo específico para PowerShell
if [ "$IS_POWERSHELL" = true ] && [ $SECRETS_EXIT_CODE -ne 0 ]; then
    echo "SECRETS DETECTION FAILED" >&2
fi

if [ $SECRETS_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Detección de secretos falló${NC}"
    ERRORS=$((ERRORS + 1))
fi

# 3. Verificar URLs hardcodeadas
echo -e "\n${BLUE}🌐 Verificando URLs hardcodeadas...${NC}"
set +e  # Temporalmente deshabilitar exit en error para capturar código
"$SCRIPT_DIR/url-hardcoded-check.sh"
URL_EXIT_CODE=$?
set -e  # Re-habilitar exit en error

# Manejo específico para PowerShell
if [ "$IS_POWERSHELL" = true ] && [ $URL_EXIT_CODE -ne 0 ]; then
    echo "URL CHECK FAILED" >&2
fi

if [ $URL_EXIT_CODE -ne 0 ]; then
    echo -e "${RED}❌ Verificación de URLs falló${NC}"
    ERRORS=$((ERRORS + 1))
fi

# 4. Verificar sintaxis según tipo de archivo
echo -e "\n${BLUE}📝 Verificando sintaxis...${NC}"

# TypeScript/JavaScript
TS_JS_FILES=$(echo "$FILES_CHANGED" | grep -E '\.(ts|tsx|js|jsx)$' || true)
if [ -n "$TS_JS_FILES" ]; then
    if command -v tsc >/dev/null 2>&1; then
        echo "Verificando TypeScript..."
        TS_OUTPUT=$(tsc --noEmit --skipLibCheck 2>&1)
        if [ $? -ne 0 ]; then
            echo -e "${RED}❌ Errores de TypeScript encontrados:${NC}"
            echo "$TS_OUTPUT" | grep -E "error TS[0-9]+:" | head -10
            ERRORS=$((ERRORS + 1))
        else
            show_result 0 "Verificación de TypeScript exitosa"
        fi
    elif command -v node >/dev/null 2>&1; then
        echo "Verificando sintaxis JavaScript básica..."
        for file in $TS_JS_FILES; do
            if [ -f "$file" ]; then
                JS_ERROR=$(node -c "$file" 2>&1)
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ Error de sintaxis en $file:${NC}"
                    echo "$JS_ERROR" | head -3
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        done
        if [ $ERRORS -eq 0 ]; then
            show_result 0 "Verificación de sintaxis JavaScript exitosa"
        fi
    fi
fi

# Python
PY_FILES=$(echo "$FILES_CHANGED" | grep -E '\.py$' || true)
if [ -n "$PY_FILES" ]; then
    if command -v python3 >/dev/null 2>&1; then
        echo "Verificando sintaxis Python..."
        for file in $PY_FILES; do
            if [ -f "$file" ]; then
                PY_ERROR=$(python3 -m py_compile "$file" 2>&1)
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ Error de sintaxis en $file:${NC}"
                    echo "$PY_ERROR" | head -3
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        done
        if [ $ERRORS -eq 0 ]; then
            show_result 0 "Verificación de sintaxis Python exitosa"
        fi
    fi
fi

# JSON
JSON_FILES=$(echo "$FILES_CHANGED" | grep -E '\.json$' || true)
if [ -n "$JSON_FILES" ]; then
    echo "Verificando sintaxis JSON..."
    for file in $JSON_FILES; do
        if [ -f "$file" ]; then
            if command -v jq >/dev/null 2>&1; then
                JSON_ERROR=$(jq empty "$file" 2>&1)
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ JSON inválido en $file:${NC}"
                    echo "$JSON_ERROR" | head -3
                    ERRORS=$((ERRORS + 1))
                fi
            elif command -v python3 >/dev/null 2>&1; then
                JSON_ERROR=$(python3 -m json.tool "$file" 2>&1)
                if [ $? -ne 0 ]; then
                    echo -e "${RED}❌ JSON inválido en $file:${NC}"
                    echo "$JSON_ERROR" | head -3
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        fi
    done
    if [ $ERRORS -eq 0 ]; then
        show_result 0 "Verificación de sintaxis JSON exitosa"
    fi
fi

# 5. Verificar dependencias si cambió package.json o similar
echo -e "\n${BLUE}🛡️  Verificando vulnerabilidades en dependencias...${NC}"
if echo "$FILES_CHANGED" | grep -E "package\.json|package-lock\.json|yarn\.lock|bun\.lockb|requirements\.txt" >/dev/null; then
    if ! "$SCRIPT_DIR/dependency-vulnerabilities.sh"; then
        warning "Se encontraron vulnerabilidades en dependencias"
        # No fallar el commit por vulnerabilidades, solo advertir
    fi
else
    echo "No se modificaron archivos de dependencias"
fi

# 6. Verificar que no haya console.log o similar
echo -e "\n${BLUE}🐛 Verificando statements de debug...${NC}"
DEBUG_STATEMENTS=$(echo "$FILES_CHANGED" | grep -E '\.(ts|tsx|js|jsx)$' | xargs grep -l "console\." 2>/dev/null || true)
if [ -n "$DEBUG_STATEMENTS" ]; then
    warning "Console statements encontrados en:"
    echo "$DEBUG_STATEMENTS" | sed 's/^/  - /'
    echo -e "${YELLOW}💡 Considera remover console statements para producción${NC}"
fi

# 7. Verificar comentarios TODO/FIXME
TODO_COMMENTS=$(echo "$FILES_CHANGED" | xargs grep -l -i "TODO\|FIXME\|HACK\|XXX" 2>/dev/null || true)
if [ -n "$TODO_COMMENTS" ]; then
    warning "Comentarios TODO/FIXME encontrados en:"
    echo "$TODO_COMMENTS" | sed 's/^/  - /'
fi

# Resultado final
echo -e "\n${BLUE}📊 Resumen del escaneo de seguridad:${NC}"

# En PowerShell, forzar salida inmediata y visible
if [ "$IS_POWERSHELL" = true ]; then
    echo ""
    echo "=== SECURITY SCAN RESULT ==="
fi

if [ $ERRORS -eq 0 ]; then
    echo -e "${GREEN}✅ Todas las verificaciones críticas pasaron exitosamente${NC}"
    echo -e "${GREEN}🎉 Commit aprobado para continuar${NC}"
    
    # Flush específico para PowerShell
    if [ "$IS_POWERSHELL" = true ]; then
        echo "RESULT: SUCCESS"
        echo "=== END SECURITY SCAN ==="
        sleep 0.1  # Pequeña pausa para PowerShell
    fi
    
    # Flush output para Windows
    exec 1>&1 2>&2
    exit 0
else
    echo -e "${RED}❌ Se encontraron $ERRORS errores críticos${NC}"
    echo -e "${RED}🚫 Commit bloqueado hasta resolver los problemas${NC}"
    echo -e "${RED}🚫 SECURITY SCAN FAILED - COMMIT REJECTED${NC}"
    
    # Manejo específico para PowerShell
    if [ "$IS_POWERSHELL" = true ]; then
        echo ""
        echo "RESULT: FAILED"
        echo "ERRORS: $ERRORS"
        echo "=== END SECURITY SCAN ==="
        # En PowerShell, escribir a stderr también
        echo "SECURITY SCAN FAILED - COMMIT BLOCKED" >&2
        sleep 0.1  # Pequeña pausa para PowerShell
    fi
    
    # Flush output para Windows
    exec 1>&1 2>&2
    
    # En PowerShell, usar exit más agresivo
    if [ "$IS_POWERSHELL" = true ]; then
        exit 1
    else
        exit 1
    fi
fi