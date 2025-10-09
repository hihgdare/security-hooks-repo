#!/usr/bin/env bash

# Verificación de vulnerabilidades en dependencias
# Este script escanea archivos de dependencias en busca de vulnerabilidades conocidas

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🛡️ Verificando vulnerabilidades en dependencias...${NC}"

# Detectar entorno Windows
IS_WINDOWS=false
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
    IS_WINDOWS=true
    echo -e "${BLUE}🧠 Entorno Windows detectado - aplicando ajustes de compatibilidad${NC}"
fi

# Configuración
PROJECT_ROOT="$(git rev-parse --show-toplevel)"

# Normalizar paths para Windows
if [ "$IS_WINDOWS" = true ]; then
    PROJECT_ROOT=$(cygpath -u "$PROJECT_ROOT" 2>/dev/null || echo "$PROJECT_ROOT")
fi

cd "$PROJECT_ROOT"

# Archivos de dependencias modificados
DEP_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep -E '^(package\.json|package-lock\.json|yarn\.lock|bun\.lockb|requirements\.txt|Pipfile\.lock|go\.mod|Cargo\.lock|composer\.json|composer\.lock)$' || true)

# En Windows, normalizar separadores de path
if [ "$IS_WINDOWS" = true ]; then
    DEP_FILES=$(echo "$DEP_FILES" | sed 's|\\|/|g')
fi

if [ -z "$DEP_FILES" ]; then
    echo -e "${GREEN}✅ No se modificaron archivos de dependencias${NC}"
    exit 0
fi

echo "Archivos de dependencias modificados:"
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
    
    if [ "$count" -gt 0 ]; then
        echo -e "${color}  $level: $count${NC}"
    fi
}

# Verificar Node.js (npm/yarn/bun)
if echo "$DEP_FILES" | grep -E "package\.json|package-lock\.json|yarn\.lock|bun\.lockb" >/dev/null; then
    echo -e "\n${BLUE}📦 Verificando dependencias Node.js...${NC}"
    
    # Intentar con npm audit
    if [ -f "package-lock.json" ] && command -v npm >/dev/null 2>&1; then
        echo "Ejecutando npm audit..."
        
        # Ejecutar npm audit y capturar la salida
        if npm audit --audit-level=moderate --json > /tmp/npm-audit.json 2>/dev/null; then
            echo -e "${GREEN}✅ npm audit completado sin vulnerabilidades críticas${NC}"
        else
            AUDIT_RESULT=$(cat /tmp/npm-audit.json 2>/dev/null || echo '{}')
            
            # Parsear resultados (implementación básica)
            CRITICAL_VULNS=$(echo "$AUDIT_RESULT" | grep -o '"critical":[0-9]*' | cut -d':' -f2 | head -1 || echo "0")
            HIGH_VULNS=$(echo "$AUDIT_RESULT" | grep -o '"high":[0-9]*' | cut -d':' -f2 | head -1 || echo "0")
            MODERATE_VULNS=$(echo "$AUDIT_RESULT" | grep -o '"moderate":[0-9]*' | cut -d':' -f2 | head -1 || echo "0")
            
            if [ "$CRITICAL_VULNS" -gt 0 ] || [ "$HIGH_VULNS" -gt 0 ]; then
                VULNERABILITIES_FOUND=true
                echo -e "${RED}❌ Vulnerabilidades encontradas:${NC}"
                show_vuln_summary "Críticas" "$CRITICAL_VULNS" "$RED"
                show_vuln_summary "Altas" "$HIGH_VULNS" "$RED"
                show_vuln_summary "Moderadas" "$MODERATE_VULNS" "$YELLOW"
                
                echo -e "\n${YELLOW}🔧 Para ver detalles: npm audit${NC}"
                echo -e "${YELLOW}🔧 Para arreglar automáticamente: npm audit fix${NC}"
            elif [ "$MODERATE_VULNS" -gt 0 ]; then
                echo -e "${YELLOW}⚠️  $MODERATE_VULNS vulnerabilidades moderadas encontradas${NC}"
                echo -e "${YELLOW}🔧 Revisar con: npm audit${NC}"
            fi
        fi
        rm -f /tmp/npm-audit.json
        
    # Intentar con yarn audit
    elif [ -f "yarn.lock" ] && command -v yarn >/dev/null 2>&1; then
        echo "Ejecutando yarn audit..."
        
        if yarn audit --level moderate --json > /tmp/yarn-audit.json 2>/dev/null; then
            echo -e "${GREEN}✅ yarn audit completado sin vulnerabilidades críticas${NC}"
        else
            echo -e "${YELLOW}⚠️  yarn audit reportó vulnerabilidades${NC}"
            echo -e "${YELLOW}🔧 Para ver detalles: yarn audit${NC}"
            VULNERABILITIES_FOUND=true
        fi
        rm -f /tmp/yarn-audit.json
        
    # Intentar con bun
    elif [ -f "bun.lockb" ] && command -v bun >/dev/null 2>&1; then
        echo "Verificando con bun..."
        # Bun no tiene audit nativo aún, usar npm audit si está disponible
        if command -v npm >/dev/null 2>&1; then
            echo "Usando npm audit para verificar bun.lockb..."
            if npm audit --audit-level=moderate > /dev/null 2>&1; then
                echo -e "${GREEN}✅ Verificación completada sin vulnerabilidades críticas${NC}"
            else
                echo -e "${YELLOW}⚠️  Se encontraron vulnerabilidades${NC}"
                echo -e "${YELLOW}🔧 Para ver detalles: npm audit${NC}"
                VULNERABILITIES_FOUND=true
            fi
        else
            echo -e "${YELLOW}⚠️  npm no disponible para verificar bun.lockb${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  No se pudo ejecutar audit - herramientas no disponibles${NC}"
    fi
fi

# Verificar Python
if echo "$DEP_FILES" | grep -E "requirements\.txt|Pipfile\.lock" >/dev/null; then
    echo -e "\n${BLUE}🐍 Verificando dependencias Python...${NC}"
    
    if command -v pip >/dev/null 2>&1; then
        # Intentar con safety si está disponible
        if command -v safety >/dev/null 2>&1; then
            echo "Ejecutando safety check..."
            if safety check --json > /tmp/safety-check.json 2>/dev/null; then
                echo -e "${GREEN}✅ safety check completado sin vulnerabilidades${NC}"
            else
                echo -e "${YELLOW}⚠️  safety check encontró vulnerabilidades${NC}"
                echo -e "${YELLOW}🔧 Para instalar safety: pip install safety${NC}"
                echo -e "${YELLOW}🔧 Para ver detalles: safety check${NC}"
                VULNERABILITIES_FOUND=true
            fi
            rm -f /tmp/safety-check.json
        else
            echo -e "${YELLOW}⚠️  safety no instalado${NC}"
            echo -e "${YELLOW}💡 Instalar con: pip install safety${NC}"
        fi
        
        # Verificar pip-audit si está disponible
        if command -v pip-audit >/dev/null 2>&1; then
            echo "Ejecutando pip-audit..."
            if pip-audit --desc --format=json > /tmp/pip-audit.json 2>/dev/null; then
                echo -e "${GREEN}✅ pip-audit completado sin vulnerabilidades${NC}"
            else
                echo -e "${YELLOW}⚠️  pip-audit encontró vulnerabilidades${NC}"
                echo -e "${YELLOW}🔧 Para ver detalles: pip-audit${NC}"
                VULNERABILITIES_FOUND=true
            fi
            rm -f /tmp/pip-audit.json
        fi
    else
        echo -e "${YELLOW}⚠️  pip no disponible${NC}"
    fi
fi

# Verificar Go
if echo "$DEP_FILES" | grep "go\.mod" >/dev/null; then
    echo -e "\n${BLUE}🐹 Verificando dependencias Go...${NC}"
    
    if command -v go >/dev/null 2>&1; then
        # Verificar con govulncheck si está disponible
        if command -v govulncheck >/dev/null 2>&1; then
            echo "Ejecutando govulncheck..."
            if govulncheck ./... > /dev/null 2>&1; then
                echo -e "${GREEN}✅ govulncheck completado sin vulnerabilidades${NC}"
            else
                echo -e "${YELLOW}⚠️  govulncheck encontró vulnerabilidades${NC}"
                echo -e "${YELLOW}🔧 Para ver detalles: govulncheck ./...${NC}"
                VULNERABILITIES_FOUND=true
            fi
        else
            echo -e "${YELLOW}⚠️  govulncheck no instalado${NC}"
            echo -e "${YELLOW}💡 Instalar con: go install golang.org/x/vuln/cmd/govulncheck@latest${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Go no disponible${NC}"
    fi
fi

# Verificar Rust
if echo "$DEP_FILES" | grep "Cargo\.lock" >/dev/null; then
    echo -e "\n${BLUE}🦀 Verificando dependencias Rust...${NC}"
    
    if command -v cargo >/dev/null 2>&1; then
        # Verificar con cargo-audit si está disponible
        if command -v cargo-audit >/dev/null 2>&1; then
            echo "Ejecutando cargo audit..."
            if cargo audit > /dev/null 2>&1; then
                echo -e "${GREEN}✅ cargo audit completado sin vulnerabilidades${NC}"
            else
                echo -e "${YELLOW}⚠️  cargo audit encontró vulnerabilidades${NC}"
                echo -e "${YELLOW}🔧 Para ver detalles: cargo audit${NC}"
                VULNERABILITIES_FOUND=true
            fi
        else
            echo -e "${YELLOW}⚠️  cargo-audit no instalado${NC}"
            echo -e "${YELLOW}💡 Instalar con: cargo install cargo-audit${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  Cargo no disponible${NC}"
    fi
fi

# Verificar PHP
if echo "$DEP_FILES" | grep -E "composer\.json|composer\.lock" >/dev/null; then
    echo -e "\n${BLUE}🐘 Verificando dependencias PHP...${NC}"
    
    if command -v composer >/dev/null 2>&1; then
        echo "Ejecutando composer audit..."
        if composer audit --format=json > /tmp/composer-audit.json 2>/dev/null; then
            echo -e "${GREEN}✅ composer audit completado sin vulnerabilidades${NC}"
        else
            echo -e "${YELLOW}⚠️  composer audit encontró vulnerabilidades${NC}"
            echo -e "${YELLOW}🔧 Para ver detalles: composer audit${NC}"
            VULNERABILITIES_FOUND=true
        fi
        rm -f /tmp/composer-audit.json
    else
        echo -e "${YELLOW}⚠️  Composer no disponible${NC}"
    fi
fi

# Recomendaciones generales
echo -e "\n${BLUE}💡 Recomendaciones de seguridad:${NC}"
echo -e "${BLUE}• Mantener dependencias actualizadas regularmente${NC}"
echo -e "${BLUE}• Usar versiones específicas en lugar de rangos amplios${NC}"
echo -e "${BLUE}• Revisar dependencias antes de agregarlas${NC}"
echo -e "${BLUE}• Configurar alertas automáticas de seguridad${NC}"

# Resultado final
echo -e "\n${BLUE}📊 Resumen de verificación de dependencias:${NC}"

if [ "$VULNERABILITIES_FOUND" = true ]; then
    if [ "$CRITICAL_VULNS" -gt 0 ] || [ "$HIGH_VULNS" -gt 0 ]; then
        echo -e "${RED}❌ Vulnerabilidades críticas o altas encontradas${NC}"
        echo -e "${RED}🚫 Se recomienda no proceder hasta resolver las vulnerabilidades${NC}"
        echo -e "${RED}🚫 DEPENDENCY VULNERABILITIES FOUND - COMMIT REJECTED${NC}"
        # Flush output para Windows
        exec 1>&1 2>&2
        exit 1
    else
        echo -e "${YELLOW}⚠️  Vulnerabilidades menores encontradas${NC}"
        echo -e "${YELLOW}📋 Revisar y planificar actualizaciones${NC}"
        echo -e "${GREEN}✅ Commit permitido con advertencia${NC}"
        # Flush output para Windows
        exec 1>&1 2>&2
        exit 0
    fi
else
    echo -e "${GREEN}✅ No se detectaron vulnerabilidades críticas${NC}"
    # Flush output para Windows
    exec 1>&1 2>&2
    exit 0
fi