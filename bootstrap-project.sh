#!/bin/bash

# Bootstrap script para cualquier proyecto que quiera usar los security hooks
# Este script se descarga y ejecuta desde cualquier proyecto

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

REPO_URL="https://github.com/hihgdare/security-hooks-repo"
RAW_URL="https://raw.githubusercontent.com/hihgdare/security-hooks-repo/main"

echo -e "${BLUE}🔧 Configurando Security Hooks desde repositorio central...${NC}"

# Verificar que estamos en un repositorio Git
if [ ! -d ".git" ]; then
    echo -e "${RED}❌ Error: Debe ejecutarse desde la raíz de un repositorio Git${NC}"
    exit 1
fi

# Crear directorio scripts si no existe
mkdir -p scripts

# Descargar el instalador principal
echo -e "${BLUE}📥 Descargando instalador...${NC}"
if command -v curl >/dev/null 2>&1; then
    curl -sSf "$RAW_URL/install-security-hooks.sh" -o scripts/install-precommit-required.sh
elif command -v wget >/dev/null 2>&1; then
    wget -q "$RAW_URL/install-security-hooks.sh" -O scripts/install-precommit-required.sh
else
    echo -e "${RED}❌ curl o wget requeridos${NC}"
    exit 1
fi

chmod +x scripts/install-precommit-required.sh

# Crear .pre-commit-config.yaml básico
if [ ! -f ".pre-commit-config.yaml" ]; then
    echo -e "${BLUE}📝 Creando .pre-commit-config.yaml...${NC}"
    cat > .pre-commit-config.yaml << 'YAML_EOF'
# Configuración de Pre-commit Hooks
repos:
  # Hooks básicos
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v4.5.0
    hooks:
      - id: trailing-whitespace
      - id: check-yaml
      - id: check-json
      - id: check-merge-conflict
      - id: check-added-large-files
        args: ['--maxkb=500']
      - id: detect-private-key

  # Security hooks centralizados
  - repo: https://github.com/hihgdare/security-hooks-repo
    rev: v1.0.1
    hooks:
      - id: security-scan
      - id: secrets-detection
      - id: url-hardcoded-check
      - id: dependency-vulnerabilities

# Configuración global
ci:
  autofix_prs: true
  autoupdate_schedule: weekly
YAML_EOF
fi

# Ejecutar instalación
echo -e "${BLUE}🚀 Ejecutando instalación...${NC}"
./scripts/install-precommit-required.sh

echo -e "${GREEN}✅ ¡Configuración completada!${NC}"
echo -e "${BLUE}💡 Los hooks de seguridad están ahora activos en este proyecto${NC}"
