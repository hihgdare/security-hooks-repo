#!/usr/bin/env bash

# Verificación de vulnerabilidades en dependencias
# Este script escanea archivos de dependencias en busca de vulnerabilidades conocidas
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

safe_echo "info" "Verificando vulnerabilidades en dependencias..."

# Configuración
PROJECT_ROOT=$(get_git_root)
SCRIPT_DIR=$(normalize_path "$SCRIPT_DIR")
PROJECT_ROOT=$(normalize_path "$PROJECT_ROOT")

cd "$PROJECT_ROOT"

# Archivos de dependencias modificados
DEP_FILES=$(get_modified_files "ACM" '^(package\.json|package-lock\.json|yarn\.lock|bun\.lockb|requirements\.txt|Pipfile\.lock|go\.mod|Cargo\.lock|composer\.json|composer\.lock)$')

if [[ -z "$DEP_FILES" ]]; then
    safe_echo "success" "No se modificaron archivos de dependencias"
    safe_exit 0
fi

safe_echo "info" "Archivos de dependencias modificados:"
echo "$DEP_FILES" | sed 's/^/  - /'

VULNERABILITIES_FOUND=false
CRITICAL_VULNS=0
HIGH_VULNS=0
MODERATE_VULNS=0

# Función para mostrar resumen de vulnerabilidades
show_vuln_summary() {
    local level="$1"
    local count="$2"
    local color="$3"
    
    if [[ "$count" -gt 0 ]]; then
        safe_echo "$color" "  $level: $count"
    fi
}

# Verificar Node.js (npm/yarn/bun)
if echo "$DEP_FILES" | grep -E "package\.json|package-lock\.json|yarn\.lock|bun\.lockb" >/dev/null; then
    safe_echo "info" "Verificando dependencias Node.js..."
    
    # Intentar con npm audit
    if [[ -f "package-lock.json" ]] && command_exists npm; then
        safe_echo "info" "Ejecutando npm audit..."
        
        # Ejecutar npm audit y capturar la salida
        TEMP_AUDIT="/tmp/npm-audit-$$.json"
        if npm audit --audit-level=moderate --json > "$TEMP_AUDIT" 2>/dev/null; then
            safe_echo "success" "npm audit completado sin vulnerabilidades críticas"
        else
            if [[ -f "$TEMP_AUDIT" ]]; then
                AUDIT_RESULT=$(cat "$TEMP_AUDIT")
                
                # Parsear resultados (implementación básica)
                CRITICAL_VULNS=$(echo "$AUDIT_RESULT" | grep -o '"critical":[0-9]*' | cut -d':' -f2 | head -1 || echo "0")
                HIGH_VULNS=$(echo "$AUDIT_RESULT" | grep -o '"high":[0-9]*' | cut -d':' -f2 | head -1 || echo "0")
                MODERATE_VULNS=$(echo "$AUDIT_RESULT" | grep -o '"moderate":[0-9]*' | cut -d':' -f2 | head -1 || echo "0")
                
                # Remover posibles espacios
                CRITICAL_VULNS=${CRITICAL_VULNS// /}
                HIGH_VULNS=${HIGH_VULNS// /}
                MODERATE_VULNS=${MODERATE_VULNS// /}
                
                if [[ "$CRITICAL_VULNS" -gt 0 ]] || [[ "$HIGH_VULNS" -gt 0 ]]; then
                    VULNERABILITIES_FOUND=true
                    safe_echo "error" "Vulnerabilidades encontradas:"
                    show_vuln_summary "Críticas" "$CRITICAL_VULNS" "error"
                    show_vuln_summary "Altas" "$HIGH_VULNS" "error"
                    show_vuln_summary "Moderadas" "$MODERATE_VULNS" "warning"
                    
                    safe_echo "warning" "Para ver detalles: npm audit"
                    safe_echo "warning" "Para arreglar automáticamente: npm audit fix"
                elif [[ "$MODERATE_VULNS" -gt 0 ]]; then
                    safe_echo "warning" "$MODERATE_VULNS vulnerabilidades moderadas encontradas"
                    safe_echo "warning" "Revisar con: npm audit"
                fi
            fi
        fi
        rm -f "$TEMP_AUDIT"
        
    # Intentar con yarn audit
    elif [[ -f "yarn.lock" ]] && command_exists yarn; then
        safe_echo "info" "Ejecutando yarn audit..."
        
        TEMP_YARN_AUDIT="/tmp/yarn-audit-$$.json"
        if yarn audit --level moderate --json > "$TEMP_YARN_AUDIT" 2>/dev/null; then
            safe_echo "success" "yarn audit completado sin vulnerabilidades críticas"
        else
            safe_echo "warning" "yarn audit reportó vulnerabilidades"
            safe_echo "warning" "Para ver detalles: yarn audit"
            VULNERABILITIES_FOUND=true
        fi
        rm -f "$TEMP_YARN_AUDIT"
        
    # Intentar con bun
    elif [[ -f "bun.lockb" ]] && command_exists bun; then
        safe_echo "info" "Verificando con bun..."
        # Bun no tiene audit nativo aún, usar npm audit si está disponible
        if command_exists npm; then
            safe_echo "info" "Usando npm audit para verificar bun.lockb..."
            if npm audit --audit-level=moderate > /dev/null 2>&1; then
                safe_echo "success" "Verificación completada sin vulnerabilidades críticas"
            else
                safe_echo "warning" "Se encontraron vulnerabilidades"
                safe_echo "warning" "Para ver detalles: npm audit"
                VULNERABILITIES_FOUND=true
            fi
        else
            safe_echo "warning" "npm no disponible para verificar bun.lockb"
        fi
    else
        safe_echo "warning" "No se pudo ejecutar audit - herramientas no disponibles"
    fi
fi

# Verificar Python
if echo "$DEP_FILES" | grep -E "requirements\.txt|Pipfile\.lock" >/dev/null; then
    safe_echo "info" "Verificando dependencias Python..."
    
    if command_exists pip; then
        # Intentar con safety si está disponible
        if command_exists safety; then
            safe_echo "info" "Ejecutando safety check..."
            TEMP_SAFETY="/tmp/safety-check-$$.json"
            if safety check --json > "$TEMP_SAFETY" 2>/dev/null; then
                safe_echo "success" "safety check completado sin vulnerabilidades"
            else
                safe_echo "warning" "safety check encontró vulnerabilidades"
                safe_echo "warning" "Para ver detalles: safety check"
                VULNERABILITIES_FOUND=true
            fi
            rm -f "$TEMP_SAFETY"
        else
            safe_echo "warning" "safety no instalado"
            safe_echo "warning" "Instalar con: pip install safety"
        fi
        
        # Verificar pip-audit si está disponible
        if command_exists pip-audit; then
            safe_echo "info" "Ejecutando pip-audit..."
            TEMP_PIP_AUDIT="/tmp/pip-audit-$$.json"
            if pip-audit --desc --format=json > "$TEMP_PIP_AUDIT" 2>/dev/null; then
                safe_echo "success" "pip-audit completado sin vulnerabilidades"
            else
                safe_echo "warning" "pip-audit encontró vulnerabilidades"
                safe_echo "warning" "Para ver detalles: pip-audit"
                VULNERABILITIES_FOUND=true
            fi
            rm -f "$TEMP_PIP_AUDIT"
        fi
    else
        safe_echo "warning" "pip no disponible"
    fi
fi

# Verificar Go
if echo "$DEP_FILES" | grep "go\.mod" >/dev/null; then
    safe_echo "info" "Verificando dependencias Go..."
    
    if command_exists go; then
        # Verificar con govulncheck si está disponible
        if command_exists govulncheck; then
            safe_echo "info" "Ejecutando govulncheck..."
            if govulncheck ./... > /dev/null 2>&1; then
                safe_echo "success" "govulncheck completado sin vulnerabilidades"
            else
                safe_echo "warning" "govulncheck encontró vulnerabilidades"
                safe_echo "warning" "Para ver detalles: govulncheck ./..."
                VULNERABILITIES_FOUND=true
            fi
        else
            safe_echo "warning" "govulncheck no instalado"
            safe_echo "warning" "Instalar con: go install golang.org/x/vuln/cmd/govulncheck@latest"
        fi
    else
        safe_echo "warning" "Go no disponible"
    fi
fi

# Verificar Rust
if echo "$DEP_FILES" | grep "Cargo\.lock" >/dev/null; then
    safe_echo "info" "Verificando dependencias Rust..."
    
    if command_exists cargo; then
        # Verificar con cargo-audit si está disponible
        if command_exists cargo-audit; then
            safe_echo "info" "Ejecutando cargo audit..."
            if cargo audit > /dev/null 2>&1; then
                safe_echo "success" "cargo audit completado sin vulnerabilidades"
            else
                safe_echo "warning" "cargo audit encontró vulnerabilidades"
                safe_echo "warning" "Para ver detalles: cargo audit"
                VULNERABILITIES_FOUND=true
            fi
        else
            safe_echo "warning" "cargo-audit no instalado"
            safe_echo "warning" "Instalar con: cargo install cargo-audit"
        fi
    else
        safe_echo "warning" "Cargo no disponible"
    fi
fi

# Verificar PHP
if echo "$DEP_FILES" | grep -E "composer\.json|composer\.lock" >/dev/null; then
    safe_echo "info" "Verificando dependencias PHP..."
    
    if command_exists composer; then
        safe_echo "info" "Ejecutando composer audit..."
        TEMP_COMPOSER_AUDIT="/tmp/composer-audit-$$.json"
        if composer audit --format=json > "$TEMP_COMPOSER_AUDIT" 2>/dev/null; then
            safe_echo "success" "composer audit completado sin vulnerabilidades"
        else
            safe_echo "warning" "composer audit encontró vulnerabilidades"
            safe_echo "warning" "Para ver detalles: composer audit"
            VULNERABILITIES_FOUND=true
        fi
        rm -f "$TEMP_COMPOSER_AUDIT"
    else
        safe_echo "warning" "Composer no disponible"
    fi
fi

# Recomendaciones generales
safe_echo "info" "Recomendaciones de seguridad:"
safe_echo "info" "• Mantener dependencias actualizadas regularmente"
safe_echo "info" "• Usar versiones específicas en lugar de rangos amplios"
safe_echo "info" "• Revisar dependencias antes de agregarlas"
safe_echo "info" "• Configurar alertas automáticas de seguridad"

# Resultado final
safe_echo "info" "Resumen de verificación de dependencias:"

if [[ "$VULNERABILITIES_FOUND" == true ]]; then
    if [[ "$CRITICAL_VULNS" -gt 0 ]] || [[ "$HIGH_VULNS" -gt 0 ]]; then
        safe_echo "error" "Vulnerabilidades críticas o altas encontradas"
        safe_echo "error" "Se recomienda no proceder hasta resolver las vulnerabilidades"
        safe_exit 1 "DEPENDENCY VULNERABILITIES FOUND - COMMIT REJECTED"
    else
        safe_echo "warning" "Vulnerabilidades menores encontradas"
        safe_echo "warning" "Revisar y planificar actualizaciones"
        safe_echo "success" "Commit permitido con advertencia"
        safe_exit 0 "DEPENDENCY CHECK PASSED WITH WARNINGS"
    fi
else
    safe_echo "success" "No se detectaron vulnerabilidades críticas"
    safe_exit 0 "DEPENDENCY CHECK PASSED"
fi