#!/bin/bash

# Script de instalación de hook central de seguridad
# Este script configura cualquier proyecto para usar el hook centralizado

set -e

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}🔧 Configurando hook central de seguridad...${NC}"

# Verificar que estamos en un repo Git
if [ ! -d ".git" ]; then
    echo -e "${RED}❌ Este script debe ejecutarse desde la raíz de un repositorio Git${NC}"
    exit 1
fi

# Crear directorio scripts si no existe
mkdir -p scripts

# Descargar el hook bootstrap desde el repositorio central
BOOTSTRAP_URL="https://raw.githubusercontent.com/bifrost-admin-hig/security-hooks/main/bootstrap/pre-commit-security.sh"

echo "📥 Descargando hook bootstrap..."
if command -v curl >/dev/null 2>&1; then
    curl -sSf "$BOOTSTRAP_URL" -o scripts/pre-commit-security.sh
elif command -v wget >/dev/null 2>&1; then
    wget -q "$BOOTSTRAP_URL" -O scripts/pre-commit-security.sh
else
    echo -e "${YELLOW}⚠️  curl o wget no encontrados. Descarga manualmente:${NC}"
    echo "   $BOOTSTRAP_URL"
    echo "   y guárdalo como scripts/pre-commit-security.sh"
    exit 1
fi

# Hacer el script ejecutable
chmod +x scripts/pre-commit-security.sh

# Crear archivo de configuración si no existe
if [ ! -f ".security-config" ]; then
    cat > .security-config << 'EOF'
# Configuración del Hook Central de Seguridad
HOOKS_REPO_URL=https://raw.githubusercontent.com/bifrost-admin-hig/security-hooks/main
HOOK_SCRIPT_PATH=pre-commit-security.sh
CACHE_DURATION=3600
# USE_LOCAL_HOOK=true  # Descomenta para usar solo verificaciones locales
EOF
    echo -e "${GREEN}✅ Archivo .security-config creado${NC}"
fi

# Configurar hook de Git
if [ -L ".git/hooks/pre-commit" ] || [ -f ".git/hooks/pre-commit" ]; then
    echo -e "${YELLOW}⚠️  Hook de pre-commit ya existe, respaldando...${NC}"
    mv .git/hooks/pre-commit .git/hooks/pre-commit.backup
fi

ln -sf ../../scripts/pre-commit-security.sh .git/hooks/pre-commit
echo -e "${GREEN}✅ Hook de pre-commit configurado${NC}"

# Agregar .security-config al .gitignore si es necesario
if [ -f ".gitignore" ]; then
    if ! grep -q "^\.security-config$" .gitignore; then
        echo "" >> .gitignore
        echo "# Configuración local de seguridad" >> .gitignore
        echo ".security-config.local" >> .gitignore
    fi
fi

echo ""
echo -e "${GREEN}🎉 ¡Configuración completada!${NC}"
echo ""
echo -e "${BLUE}📋 Lo que se configuró:${NC}"
echo "• Hook de pre-commit que descarga verificaciones del repositorio central"
echo "• Archivo de configuración .security-config"
echo "• Fallback a verificaciones locales si el repositorio central no está disponible"
echo ""
echo -e "${BLUE}📝 Próximos pasos:${NC}"
echo "• El hook se ejecutará automáticamente en cada commit"
echo "• Edita .security-config para personalizar la configuración"
echo "• Para saltear el hook: git commit --no-verify"
echo ""
echo -e "${BLUE}🔗 Repositorio central de hooks:${NC}"
echo "   https://github.com/bifrost-admin-hig/security-hooks"