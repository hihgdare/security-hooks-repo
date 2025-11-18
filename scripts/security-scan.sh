#!/usr/bin/env bash

# Escaneo integral de seguridad
# Este script ejecuta múltiples verificaciones de seguridad
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

# Configuración de colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

safe_echo "info" "Iniciando escaneo integral de seguridad..."

# Configuración de paths
PROJECT_ROOT=$(get_git_root)
CONFIG_FILE="$PROJECT_ROOT/.security-config.yml"
SCRIPT_DIR=$(normalize_path "$SCRIPT_DIR")
PROJECT_ROOT=$(normalize_path "$PROJECT_ROOT")

# Cargar configuración si existe
if [[ -f "$CONFIG_FILE" ]]; then
    safe_echo "info" "Cargando configuración desde $CONFIG_FILE"
fi

# Variable para trackear errores
ERRORS=0

# Obtener archivos modificados
safe_echo "info" "Analizando archivos modificados..."
FILES_CHANGED=$(get_modified_files)

if [[ -z "$FILES_CHANGED" ]]; then
    safe_echo "warning" "No hay archivos en staging para verificar"
    safe_exit 0
fi

safe_echo "info" "Archivos a verificar:"
echo "$FILES_CHANGED" | sed 's/^/  - /'

# Función para mostrar resultados
show_result() {
    local code=$1
    local message="$2"
    
    if [[ $code -eq 0 ]]; then
        safe_echo "success" "$message"
    else
        safe_echo "error" "$message"
        return 1
    fi
}

# 1. Verificar archivos de entorno
safe_echo "info" "Verificando archivos de entorno..."

# Detectar archivos .env problemáticos
ENV_FILES_FOUND=$(echo "$FILES_CHANGED" | grep -E "^\.env$|^\.env\.local$|^\.env\.production$" | grep -v -E "\.env\.example|\.env\.template" || true)

if [[ -n "$ENV_FILES_FOUND" ]]; then
    safe_echo "error" "Archivos .env detectados en commit"
    safe_echo "warning" "Los archivos .env no deben commitearse. Usar .env.example en su lugar."
    ERRORS=$((ERRORS + 1))
else
    show_result 0 "No se detectaron archivos .env problemáticos"
fi

# 2. Ejecutar detección de secretos
safe_echo "info" "Ejecutando detección de secretos..."
set +e  # Temporalmente deshabilitar exit en error para capturar código
"$SCRIPT_DIR/secrets-detection.sh"
SECRETS_EXIT_CODE=$?
set -e  # Re-habilitar exit en error

if [[ $SECRETS_EXIT_CODE -ne 0 ]]; then
    safe_echo "error" "Detección de secretos falló"
    ERRORS=$((ERRORS + 1))
fi

# 3. Verificar URLs hardcodeadas
safe_echo "info" "Verificando URLs hardcodeadas..."
set +e  # Temporalmente deshabilitar exit en error para capturar código
"$SCRIPT_DIR/url-hardcoded-check.sh"
URL_EXIT_CODE=$?
set -e  # Re-habilitar exit en error

if [[ $URL_EXIT_CODE -ne 0 ]]; then
    safe_echo "error" "Verificación de URLs falló"
    ERRORS=$((ERRORS + 1))
fi

# 4. Verificar sintaxis según tipo de archivo
safe_echo "info" "Verificando sintaxis..."

# TypeScript/JavaScript
TS_JS_FILES=$(echo "$FILES_CHANGED" | grep -E '\.(ts|tsx|js|jsx)$' || true)
if [[ -n "$TS_JS_FILES" ]]; then
    if command_exists tsc; then
        safe_echo "info" "Verificando TypeScript..."
        if ! TS_OUTPUT=$(tsc --noEmit --skipLibCheck 2>&1); then
            safe_echo "error" "Errores de TypeScript encontrados:"
            echo "$TS_OUTPUT" | grep -E "error TS[0-9]+:" | head -10
            ERRORS=$((ERRORS + 1))
        else
            show_result 0 "Verificación de TypeScript exitosa"
        fi
    elif command_exists node; then
        safe_echo "info" "Verificando sintaxis JavaScript básica..."
        while read -r file; do
            if [[ -f "$file" ]]; then
                if ! JS_ERROR=$(node -c "$file" 2>&1); then
                    safe_echo "error" "Error de sintaxis en $file:"
                    echo "$JS_ERROR" | head -3
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        done <<< "$TS_JS_FILES"
        
        if [[ $ERRORS -eq 0 ]]; then
            show_result 0 "Verificación de sintaxis JavaScript exitosa"
        fi
    fi
fi

# Python
PY_FILES=$(echo "$FILES_CHANGED" | grep -E '\.py$' || true)
if [[ -n "$PY_FILES" ]]; then
    if command_exists python3; then
        safe_echo "info" "Verificando sintaxis Python..."
        while read -r file; do
            if [[ -f "$file" ]]; then
                if ! PY_ERROR=$(python3 -m py_compile "$file" 2>&1); then
                    safe_echo "error" "Error de sintaxis en $file:"
                    echo "$PY_ERROR" | head -3
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        done <<< "$PY_FILES"
        
        if [[ $ERRORS -eq 0 ]]; then
            show_result 0 "Verificación de sintaxis Python exitosa"
        fi
    fi
fi

# JSON
JSON_FILES=$(echo "$FILES_CHANGED" | grep -E '\.json$' || true)
if [[ -n "$JSON_FILES" ]]; then
    safe_echo "info" "Verificando sintaxis JSON..."
    while read -r file; do
        if [[ -f "$file" ]]; then
            if command_exists jq; then
                if ! JSON_ERROR=$(jq empty "$file" 2>&1); then
                    safe_echo "error" "JSON inválido en $file:"
                    echo "$JSON_ERROR" | head -3
                    ERRORS=$((ERRORS + 1))
                fi
            elif command_exists python3; then
                if ! JSON_ERROR=$(python3 -m json.tool "$file" >/dev/null 2>&1); then
                    safe_echo "error" "JSON inválido en $file:"
                    echo "$JSON_ERROR" | head -3
                    ERRORS=$((ERRORS + 1))
                fi
            fi
        fi
    done <<< "$JSON_FILES"
    
    if [[ $ERRORS -eq 0 ]]; then
        show_result 0 "Verificación de sintaxis JSON exitosa"
    fi
fi

# 5. Verificar dependencias si cambió package.json o similar
safe_echo "info" "Verificando vulnerabilidades en dependencias..."
if echo "$FILES_CHANGED" | grep -E "package\.json|package-lock\.json|yarn\.lock|bun\.lockb|requirements\.txt" >/dev/null; then
    if ! "$SCRIPT_DIR/dependency-vulnerabilities.sh"; then
        safe_echo "warning" "Se encontraron vulnerabilidades en dependencias"
        # No fallar el commit por vulnerabilidades, solo advertir
    fi
else
    safe_echo "info" "No se modificaron archivos de dependencias"
fi

# 6. Verificar que no haya console.log o similar
safe_echo "info" "Verificando statements de debug..."
DEBUG_STATEMENTS=$(search_pattern "console\." "$FILES_CHANGED" "-l")

if [[ -n "$DEBUG_STATEMENTS" ]]; then
    safe_echo "warning" "Console statements encontrados en:"
    echo "$DEBUG_STATEMENTS" | sed 's/^/  - /'
    safe_echo "warning" "Considera remover console statements para producción"
fi

# 7. Verificar comentarios TODO/FIXME
if [[ -n "$FILES_CHANGED" ]]; then
    TODO_COMMENTS=$(search_pattern "TODO\|FIXME\|HACK\|XXX" "$FILES_CHANGED" "-l -i")
    if [[ -n "$TODO_COMMENTS" ]]; then
        safe_echo "warning" "Comentarios TODO/FIXME encontrados en:"
        echo "$TODO_COMMENTS" | sed 's/^/  - /'
    fi
fi

# Resultado final
safe_echo "info" "Resumen del escaneo de seguridad:"

if [[ $ERRORS -eq 0 ]]; then
    safe_echo "success" "Todas las verificaciones críticas pasaron exitosamente"
    safe_echo "success" "Commit aprobado para continuar"
    safe_exit 0 "SECURITY SCAN PASSED"
else
    safe_echo "error" "Se encontraron $ERRORS errores críticos"
    safe_echo "error" "Commit bloqueado hasta resolver los problemas"
    safe_exit 1 "SECURITY SCAN FAILED - COMMIT REJECTED"
fi