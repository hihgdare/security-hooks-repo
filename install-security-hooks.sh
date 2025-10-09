#!/usr/bin/env bash

# Instalador de pre-commit para proyectos
# Este script instala y configura pre-commit en cualquier proyecto

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🔧 Instalador de Pre-commit Security Hooks${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Verificar que estamos en un repositorio Git
if [ ! -d ".git" ]; then
    echo -e "${RED}❌ Error: Este script debe ejecutarse desde la raíz de un repositorio Git${NC}"
    exit 1
fi

# Detectar tipo de proyecto
detect_project_type() {
    if [ -f "package.json" ]; then
        if grep -q "react" package.json 2>/dev/null; then
            echo "react"
        elif grep -q "vue" package.json 2>/dev/null; then
            echo "vue"
        elif grep -q "angular" package.json 2>/dev/null; then
            echo "angular"
        elif grep -q "express" package.json 2>/dev/null; then
            echo "node-express"
        else
            echo "node"
        fi
    elif [ -f "requirements.txt" ] || [ -f "pyproject.toml" ] || [ -f "setup.py" ]; then
        echo "python"
    elif [ -f "go.mod" ]; then
        echo "go"
    elif [ -f "Cargo.toml" ]; then
        echo "rust"
    elif [ -f "pom.xml" ] || [ -f "build.gradle" ]; then
        echo "java"
    elif [ -f "composer.json" ]; then
        echo "php"
    else
        echo "generic"
    fi
}

PROJECT_TYPE=$(detect_project_type)
PROJECT_NAME=$(basename "$(pwd)")

echo -e "${BLUE}📋 Información del proyecto:${NC}"
echo -e "  • Nombre: $PROJECT_NAME"
echo -e "  • Tipo detectado: $PROJECT_TYPE"

# Verificar si pre-commit está instalado
echo -e "\n${BLUE}🔍 Verificando pre-commit...${NC}"
if ! command -v pre-commit >/dev/null 2>&1; then
    echo -e "${YELLOW}⚠️  pre-commit no está instalado${NC}"
    echo -e "${BLUE}💡 Opciones de instalación:${NC}"
    echo -e "  • pip install pre-commit"
    echo -e "  • brew install pre-commit"
    echo -e "  • conda install -c conda-forge pre-commit"
    echo ""
    read -p "¿Quieres que intente instalarlo con pip? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v pip >/dev/null 2>&1; then
            echo -e "${BLUE}📦 Instalando pre-commit con pip...${NC}"
            pip install pre-commit
        elif command -v pip3 >/dev/null 2>&1; then
            echo -e "${BLUE}📦 Instalando pre-commit con pip3...${NC}"
            pip3 install pre-commit
        else
            echo -e "${RED}❌ pip no está disponible${NC}"
            exit 1
        fi
    else
        echo -e "${RED}❌ pre-commit es requerido para continuar${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}✅ pre-commit instalado: $(pre-commit --version)${NC}"

# Crear .pre-commit-config.yml si no existe
if [ ! -f ".pre-commit-config.yml" ]; then
    echo -e "\n${BLUE}📝 Creando .pre-commit-config.yml...${NC}"
    
    cat > .pre-commit-config.yml << 'EOF'
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

  # Hooks de seguridad centralizados
  - repo: https://github.com/bifrost-admin-hig/security-hooks-repo
    rev: main
    hooks:
      - id: security-scan
      - id: secrets-detection
      - id: url-hardcoded-check
      - id: dependency-vulnerabilities
EOF

    # Agregar hooks específicos según el tipo de proyecto
    case $PROJECT_TYPE in
        "react"|"vue"|"angular"|"node")
            cat >> .pre-commit-config.yml << 'EOF'

  # JavaScript/TypeScript
  - repo: https://github.com/pre-commit/mirrors-eslint
    rev: v8.57.0
    hooks:
      - id: eslint
        files: \.(ts|tsx|js|jsx)$
        additional_dependencies:
          - eslint@^8.57.0

  - repo: https://github.com/pre-commit/mirrors-prettier
    rev: v3.1.0
    hooks:
      - id: prettier
        files: \.(ts|tsx|js|jsx|json|yml|yaml|md)$
EOF
            ;;
        "python")
            cat >> .pre-commit-config.yml << 'EOF'

  # Python
  - repo: https://github.com/psf/black
    rev: 23.12.1
    hooks:
      - id: black

  - repo: https://github.com/pycqa/flake8
    rev: 7.0.0
    hooks:
      - id: flake8

  - repo: https://github.com/pycqa/bandit
    rev: 1.7.5
    hooks:
      - id: bandit
        args: ['-r', '.']
EOF
            ;;
        "go")
            cat >> .pre-commit-config.yml << 'EOF'

  # Go
  - repo: https://github.com/dnephin/pre-commit-golang
    rev: v0.5.1
    hooks:
      - id: go-fmt
      - id: go-vet-mod
      - id: go-mod-tidy
EOF
            ;;
    esac

    echo -e "${GREEN}✅ .pre-commit-config.yml creado${NC}"
else
    echo -e "${YELLOW}⚠️  .pre-commit-config.yml ya existe${NC}"
fi

# Crear configuración de seguridad si no existe
if [ ! -f ".security-config.yml" ]; then
    echo -e "\n${BLUE}📝 Creando .security-config.yml...${NC}"
    
    cat > .security-config.yml << EOF
# Configuración de seguridad para el proyecto
project:
  name: "$PROJECT_NAME"
  type: "$PROJECT_TYPE"

# Configuración de detección de secretos
secrets_detection:
  exclude_patterns:
    - "node_modules/**"
    - "dist/**"
    - "build/**"
    - "coverage/**"
    - "*.test.*"
    - "*.spec.*"
    - "*.example.*"
    - "*.template.*"

# Configuración de verificación de URLs
url_check:
  allowed_domains:
    - "localhost"
    - "127.0.0.1"
    - "example.com"
    - "github.com"
    - "npmjs.com"
  exclude_patterns:
    - "*.test.*"
    - "*.spec.*"
    - "*.mock.*"

# Configuración de notificaciones (opcional)
notifications:
  enabled: false
  # slack_webhook: "https://hooks.slack.com/services/..."
  # discord_webhook: "https://discord.com/api/webhooks/..."
  # email_notifications: false

# Configuración de reportes
reports:
  enabled: true
  keep_last: 10
  include_in_git: false
EOF

    echo -e "${GREEN}✅ .security-config.yml creado${NC}"
else
    echo -e "${YELLOW}⚠️  .security-config.yml ya existe${NC}"
fi

# Actualizar .gitignore
echo -e "\n${BLUE}📝 Actualizando .gitignore...${NC}"
if [ -f ".gitignore" ]; then
    if ! grep -q ".security-reports" .gitignore; then
        echo "" >> .gitignore
        echo "# Security reports" >> .gitignore
        echo ".security-reports/" >> .gitignore
        echo -e "${GREEN}✅ .gitignore actualizado${NC}"
    fi
else
    cat > .gitignore << 'EOF'
# Security reports
.security-reports/

# Pre-commit
.pre-commit-config.local.yml
EOF
    echo -e "${GREEN}✅ .gitignore creado${NC}"
fi

# Instalar hooks
echo -e "\n${BLUE}🔧 Instalando hooks de pre-commit...${NC}"
if pre-commit install; then
    echo -e "${GREEN}✅ Hooks instalados exitosamente${NC}"
else
    echo -e "${RED}❌ Error instalando hooks${NC}"
    exit 1
fi

# Instalar hooks de post-commit también
echo -e "\n${BLUE}🔧 Instalando hooks de post-commit...${NC}"
if pre-commit install --hook-type post-commit; then
    echo -e "${GREEN}✅ Hooks de post-commit instalados${NC}"
else
    echo -e "${YELLOW}⚠️  Error instalando hooks de post-commit (opcional)${NC}"
fi

# Ejecutar en todos los archivos (primera vez)
echo -e "\n${BLUE}🧪 Probando hooks en todos los archivos...${NC}"
read -p "¿Quieres ejecutar pre-commit en todos los archivos ahora? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${BLUE}🔍 Ejecutando pre-commit run --all-files...${NC}"
    if pre-commit run --all-files; then
        echo -e "${GREEN}✅ Pre-commit ejecutado exitosamente en todos los archivos${NC}"
    else
        echo -e "${YELLOW}⚠️  Pre-commit encontró algunos problemas que deben revisarse${NC}"
        echo -e "${YELLOW}💡 Los hooks ahora están activos para futuros commits${NC}"
    fi
fi

# Mostrar resumen final
echo -e "\n${GREEN}🎉 ¡Instalación completada!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}📋 Lo que se instaló:${NC}"
echo -e "  ✅ Pre-commit hooks configurados"
echo -e "  ✅ .pre-commit-config.yml creado/actualizado"
echo -e "  ✅ .security-config.yml para personalización"
echo -e "  ✅ .gitignore actualizado"
echo -e "  ✅ Hooks de post-commit para reportes"
echo ""
echo -e "${BLUE}📚 Próximos pasos:${NC}"
echo -e "  • Los hooks se ejecutarán automáticamente en cada commit"
echo -e "  • Personaliza .security-config.yml según tus necesidades"
echo -e "  • Configura notificaciones si lo deseas"
echo -e "  • Para actualizar hooks: pre-commit autoupdate"
echo -e "  • Para ejecutar manualmente: pre-commit run --all-files"
echo ""
echo -e "${BLUE}🔗 Documentación:${NC}"
echo -e "  • https://pre-commit.com/"
echo -e "  • https://github.com/bifrost-admin-hig/security-hooks-repo"
echo ""
echo -e "${GREEN}✨ ¡Tu proyecto ahora tiene hooks de seguridad automatizados!${NC}"
EOF