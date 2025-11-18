#!/usr/bin/env bash

# Platform Compatibility Library
# Funciones universales para compatibilidad multiplataforma
# Windows (Git Bash/PowerShell/WSL), macOS, Linux

# Variables globales de detección de plataforma
export IS_WINDOWS=false
export IS_MACOS=false  
export IS_LINUX=false
export IS_WSL=false
export IS_POWERSHELL=false
export IS_GIT_BASH=false
export IS_CYGWIN=false

# Función principal de detección de plataforma
detect_platform() {
    # Detectar macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        IS_MACOS=true
        echo -e "${BLUE:-}🍎 macOS detectado${NC:-}"
        return
    fi

    # Detectar Linux
    if [[ "$OSTYPE" == "linux-gnu"* ]] || [[ "$OSTYPE" == "linux"* ]]; then
        IS_LINUX=true
        
        # Verificar si es WSL
        if grep -qEi "(Microsoft|WSL)" /proc/version 2>/dev/null || [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -n "${WSLENV:-}" ]]; then
            IS_WSL=true
            IS_WINDOWS=true
            echo -e "${BLUE:-}🐧 Linux en WSL detectado${NC:-}"
        else
            echo -e "${BLUE:-}🐧 Linux nativo detectado${NC:-}"
        fi
        return
    fi

    # Detectar Windows (Git Bash, Cygwin, MSYS2)
    if [[ "$OSTYPE" == "msys"* ]] || [[ "$OSTYPE" == "cygwin"* ]]; then
        IS_WINDOWS=true
        
        if [[ "$OSTYPE" == "msys"* ]]; then
            IS_GIT_BASH=true
            echo -e "${BLUE:-}🪟 Git Bash en Windows detectado${NC:-}"
        elif [[ "$OSTYPE" == "cygwin"* ]]; then
            IS_CYGWIN=true
            echo -e "${BLUE:-}🪟 Cygwin en Windows detectado${NC:-}"
        fi
        return
    fi

    # Detectar PowerShell
    if [[ -n "${PSVersionTable:-}" ]] || [[ "${SHELL:-}" == *"powershell"* ]] || [[ -n "${POWERSHELL_DISTRIBUTION_CHANNEL:-}" ]] || [[ -n "${PSModulePath:-}" ]]; then
        IS_POWERSHELL=true
        IS_WINDOWS=true
        echo -e "${BLUE:-}🔵 PowerShell en Windows detectado${NC:-}"
        return
    fi

    # Detectar Windows por variables de entorno
    if [[ -n "${WINDIR:-}" ]] || [[ -n "${SYSTEMROOT:-}" ]] || [[ -n "${PROGRAMFILES:-}" ]]; then
        IS_WINDOWS=true
        echo -e "${BLUE:-}🪟 Windows detectado por variables de entorno${NC:-}"
        return
    fi

    # Fallback: si no se detecta nada, asumir Unix-like
    IS_LINUX=true
    echo -e "${YELLOW:-}⚠️ Sistema no detectado claramente, asumiendo Linux${NC:-}"
}

# Normalizar paths para diferentes plataformas
normalize_path() {
    local path="$1"
    
    if [[ "$IS_WINDOWS" == true ]] && [[ "$IS_WSL" != true ]]; then
        # Para Windows nativo (Git Bash, PowerShell, Cygwin)
        if command -v cygpath >/dev/null 2>&1; then
            cygpath -u "$path" 2>/dev/null || echo "$path"
        else
            echo "$path" | sed 's|\\|/|g' | sed 's|^[Cc]:|/c|'
        fi
    else
        echo "$path"
    fi
}

# Ejecutar comando compatible con grep
safe_grep() {
    local pattern="$1"
    shift
    local files="$@"
    
    if [[ "$IS_MACOS" == true ]]; then
        # En macOS, usar grep con opciones específicas
        echo "$files" | tr ' ' '\n' | xargs -I {} grep "$pattern" {} 2>/dev/null || true
    elif [[ "$IS_WINDOWS" == true ]]; then
        # En Windows, manejar paths y usar grep de forma robusta
        echo "$files" | tr ' ' '\n' | while read -r file; do
            if [[ -f "$file" ]]; then
                grep "$pattern" "$file" 2>/dev/null || true
            fi
        done
    else
        # Linux estándar
        echo "$files" | tr ' ' '\n' | xargs grep "$pattern" 2>/dev/null || true
    fi
}

# Ejecutar comando compatible con xargs
safe_xargs() {
    local cmd="$1"
    shift
    
    if [[ "$IS_MACOS" == true ]]; then
        # macOS xargs sin -r
        xargs $cmd "$@" 2>/dev/null || true
    elif [[ "$IS_WINDOWS" == true ]]; then
        # Windows: manejar files uno por uno si xargs falla
        while read -r line; do
            if [[ -n "$line" ]]; then
                $cmd "$line" "$@" 2>/dev/null || true
            fi
        done
    else
        # Linux con -r (no ejecutar si input está vacío)
        xargs -r $cmd "$@" 2>/dev/null || true
    fi
}

# Verificar si comando existe (compatible multiplataforma)
command_exists() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

# Obtener git root de forma segura
get_git_root() {
    local git_root
    if git_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        normalize_path "$git_root"
    else
        echo "$(pwd)"
    fi
}

# Obtener archivos modificados de forma segura
get_modified_files() {
    local filter="${1:-ACM}"
    local pattern="${2:-.*}"
    
    local files
    files=$(git diff --cached --name-only --diff-filter="$filter" 2>/dev/null | grep -E "$pattern" || true)
    
    if [[ "$IS_WINDOWS" == true ]]; then
        # Normalizar separadores de path
        echo "$files" | sed 's|\\|/|g'
    else
        echo "$files"
    fi
}

# Buscar patrones en archivos de forma segura
search_pattern() {
    local pattern="$1"
    local files="$2"
    local options="${3:--E -i}"
    
    if [[ -z "$files" ]]; then
        return 0
    fi
    
    if [[ "$IS_MACOS" == true ]]; then
        echo "$files" | tr '\n' '\0' | xargs -0 -I {} grep $options "$pattern" {} 2>/dev/null || true
    elif [[ "$IS_WINDOWS" == true ]]; then
        echo "$files" | while read -r file; do
            if [[ -f "$file" ]]; then
                grep $options "$pattern" "$file" 2>/dev/null && echo "$file" || true
            fi
        done
    else
        echo "$files" | xargs grep $options "$pattern" 2>/dev/null || true
    fi
}

# Función para logging seguro (compatible con PowerShell)
safe_echo() {
    local level="$1"
    shift
    local message="$@"
    
    case "$level" in
        "error")
            echo -e "${RED:-}❌ $message${NC:-}" >&2
            if [[ "$IS_POWERSHELL" == true ]]; then
                echo "ERROR: $message" >&2
            fi
            ;;
        "warning")
            echo -e "${YELLOW:-}⚠️ $message${NC:-}"
            if [[ "$IS_POWERSHELL" == true ]]; then
                echo "WARNING: $message"
            fi
            ;;
        "success")
            echo -e "${GREEN:-}✅ $message${NC:-}"
            if [[ "$IS_POWERSHELL" == true ]]; then
                echo "SUCCESS: $message"
            fi
            ;;
        "info")
            echo -e "${BLUE:-}ℹ️ $message${NC:-}"
            if [[ "$IS_POWERSHELL" == true ]]; then
                echo "INFO: $message"
            fi
            ;;
        *)
            echo "$level $message"
            ;;
    esac
    
    # Flush output para Windows
    if [[ "$IS_WINDOWS" == true ]]; then
        exec 1>&1 2>&2
    fi
}

# Función para salida segura con códigos de error
safe_exit() {
    local code="${1:-0}"
    local message="${2:-}"
    
    if [[ -n "$message" ]]; then
        if [[ "$code" -eq 0 ]]; then
            safe_echo "success" "$message"
        else
            safe_echo "error" "$message"
        fi
    fi
    
    # Flush output específico para PowerShell
    if [[ "$IS_POWERSHELL" == true ]]; then
        echo "EXIT_CODE: $code"
        sleep 0.1
    fi
    
    # Flush output para Windows
    if [[ "$IS_WINDOWS" == true ]]; then
        exec 1>&1 2>&2
    fi
    
    exit "$code"
}

# Función para verificar herramientas requeridas
check_required_tools() {
    local tools=("$@")
    local missing=()
    
    for tool in "${tools[@]}"; do
        if ! command_exists "$tool"; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        safe_echo "warning" "Herramientas faltantes: ${missing[*]}"
        return 1
    fi
    
    return 0
}

# Inicializar colores si no están definidos
if [[ -z "${RED:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    NC='\033[0m'
fi

# Detectar plataforma automáticamente al cargar el script
detect_platform

# Exportar funciones para uso en otros scripts
export -f normalize_path
export -f safe_grep
export -f safe_xargs
export -f command_exists
export -f get_git_root
export -f get_modified_files
export -f search_pattern
export -f safe_echo
export -f safe_exit
export -f check_required_tools