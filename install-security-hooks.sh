#!/usr/bin/env bash

# Instalador de pre-commit para proyectos
# Este script instala y configura pre-commit en cualquier proyecto
# Compatible con Windows (Git Bash/PowerShell/WSL), macOS y Linux

set -e

# Configuración inicial
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar biblioteca de compatibilidad multiplataforma si existe
if [[ -f "$SCRIPT_DIR/scripts/platform-compatibility.sh" ]]; then
    source "$SCRIPT_DIR/scripts/platform-compatibility.sh"
else
    # Definir funciones básicas si no está disponible
    safe_echo() {
        local level="$1"
        shift
        local message="$@"
        case "$level" in
            "error") echo -e "\033[0;31m❌ $message\033[0m" ;;
            "warning") echo -e "\033[1;33m⚠️ $message\033[0m" ;;
            "success") echo -e "\033[0;32m✅ $message\033[0m" ;;
            "info") echo -e "\033[0;34mℹ️ $message\033[0m" ;;
            *) echo "$level $message" ;;
        esac
    }
    
    command_exists() {
        command -v "$1" >/dev/null 2>&1
    }
    
    get_git_root() {
        git rev-parse --show-toplevel 2>/dev/null || echo "$(pwd)"
    }
fi

safe_echo "info" "Instalador de Pre-commit Security Hooks"
safe_echo "info" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Verificar que estamos en un repositorio Git
if [[ ! -d ".git" ]]; then
    safe_echo "error" "Este script debe ejecutarse desde la raíz de un repositorio Git"
    exit 1
fi

PROJECT_ROOT=$(get_git_root)
cd "$PROJECT_ROOT"

# Detectar tipo de proyecto
detect_project_type() {
    if [[ -f "package.json" ]]; then
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
    elif [[ -f "requirements.txt" ]] || [[ -f "pyproject.toml" ]] || [[ -f "setup.py" ]]; then
        echo "python"
    elif [[ -f "go.mod" ]]; then
        echo "go"
    elif [[ -f "Cargo.toml" ]]; then
        echo "rust"
    elif [[ -f "pom.xml" ]] || [[ -f "build.gradle" ]]; then
        echo "java"
    elif [[ -f "composer.json" ]]; then
        echo "php"
    else
        echo "generic"
    fi
}

PROJECT_TYPE=$(detect_project_type)
PROJECT_NAME=$(basename "$(pwd)")

safe_echo "info" "Información del proyecto:"
echo "  • Nombre: $PROJECT_NAME"
echo "  • Tipo detectado: $PROJECT_TYPE"

# Verificar si pre-commit está instalado
safe_echo "info" "Verificando pre-commit..."
if ! command_exists pre-commit; then
    safe_echo "warning" "pre-commit no está instalado"
    safe_echo "info" "Opciones de instalación:"
    echo "  • pip install pre-commit"
    echo "  • brew install pre-commit"
    echo "  • conda install -c conda-forge pre-commit"
    echo ""
    read -p "¿Quieres que intente instalarlo con pip? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command_exists pip; then
            safe_echo "info" "Instalando pre-commit con pip..."
            pip install pre-commit
        elif command_exists pip3; then
            safe_echo "info" "Instalando pre-commit con pip3..."
            pip3 install pre-commit
        else
            safe_echo "error" "pip no está disponible"
            exit 1
        fi
    else
        safe_echo "error" "pre-commit es requerido para continuar"
        exit 1
    fi
fi

safe_echo "success" "pre-commit instalado: $(pre-commit --version)"

# Crear .pre-commit-config.yml si no existe
if [[ ! -f ".pre-commit-config.yml" ]]; then
    safe_echo "info" "Creando .pre-commit-config.yml..."
    
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

    safe_echo "success" ".pre-commit-config.yml creado"
else
    safe_echo "warning" ".pre-commit-config.yml ya existe"
fi

# Crear configuración de seguridad si no existe
if [[ ! -f ".security-config.yml" ]]; then
    safe_echo "info" "Creando .security-config.yml..."
    
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

    safe_echo "success" ".security-config.yml creado"
else
    safe_echo "warning" ".security-config.yml ya existe"
fi

# Actualizar .gitignore
safe_echo "info" "Actualizando .gitignore..."
if [[ -f ".gitignore" ]]; then
    if ! grep -q ".security-reports" .gitignore; then
        echo "" >> .gitignore
        echo "# Security reports" >> .gitignore
        echo ".security-reports/" >> .gitignore
        safe_echo "success" ".gitignore actualizado"
    fi
else
    cat > .gitignore << 'EOF'
# Security reports
.security-reports/

# Pre-commit
.pre-commit-config.local.yml
EOF
    safe_echo "success" ".gitignore creado"
fi

# Instalar hooks
safe_echo "info" "Instalando hooks de pre-commit..."
if pre-commit install; then
    safe_echo "success" "Hooks instalados exitosamente"
else
    safe_echo "error" "Error instalando hooks"
    exit 1
fi

# Instalar hooks de post-commit también
safe_echo "info" "Instalando hooks de post-commit..."
if pre-commit install --hook-type post-commit; then
    safe_echo "success" "Hooks de post-commit instalados"
else
    safe_echo "warning" "Error instalando hooks de post-commit (opcional)"
fi

# Ejecutar en todos los archivos (primera vez)
safe_echo "info" "Probando hooks en todos los archivos..."
read -p "¿Quieres ejecutar pre-commit en todos los archivos ahora? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    safe_echo "info" "Ejecutando pre-commit run --all-files..."
    if pre-commit run --all-files; then
        safe_echo "success" "Pre-commit ejecutado exitosamente en todos los archivos"
    else
        safe_echo "warning" "Pre-commit encontró algunos problemas que deben revisarse"
        safe_echo "warning" "Los hooks ahora están activos para futuros commits"
    fi
fi

# Mostrar resumen final
safe_echo "success" "¡Instalación completada!"
safe_echo "success" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
safe_echo "success" "Lo que se instaló:"
echo "  ✅ Pre-commit hooks configurados"
echo "  ✅ .pre-commit-config.yml creado/actualizado"
echo "  ✅ .security-config.yml para personalización"
echo "  ✅ .gitignore actualizado"
echo "  ✅ Hooks de post-commit para reportes"
echo ""
safe_echo "info" "Próximos pasos:"
echo "  • Los hooks se ejecutarán automáticamente en cada commit"
echo "  • Personaliza .security-config.yml según tus necesidades"
echo "  • Configura notificaciones si lo deseas"
echo "  • Para actualizar hooks: pre-commit autoupdate"
echo "  • Para ejecutar manualmente: pre-commit run --all-files"
echo ""
safe_echo "info" "Documentación:"
echo "  • https://pre-commit.com/"
echo "  • https://github.com/bifrost-admin-hig/security-hooks-repo"
echo ""
safe_echo "success" "✨ ¡Tu proyecto ahora tiene hooks de seguridad automatizados!"