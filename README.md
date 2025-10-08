# Security Hooks Repository

Este repositorio contiene hooks de seguridad centralizados para ser utilizados con `pre-commit` en múltiples proyectos.

## 🛡️ Hooks Disponibles

### security-scan
Escaneo integral de seguridad que incluye:
- Detección de secretos con múltiples herramientas
- Análisis de patrones de código inseguro
- Verificación de configuraciones

### secrets-detection
Detección específica de secretos:
- API keys y tokens
- Credenciales hardcodeadas
- Certificados y claves privadas

### url-hardcoded-check
Verificación de URLs hardcodeadas:
- URLs de APIs de producción
- Endpoints que deberían estar en variables de entorno

### dependency-vulnerabilities
Análisis de vulnerabilidades en dependencias:
- npm audit para proyectos Node.js
- Verificación con bases de datos de vulnerabilidades

## 📝 Uso

Agrega este repositorio a tu `.pre-commit-config.yml`:

```yaml
repos:
  - repo: https://github.com/bifrost-admin-hig/security-hooks-repo
    rev: main
    hooks:
      - id: security-scan
      - id: secrets-detection
      - id: url-hardcoded-check
      - id: dependency-vulnerabilities
```

## 🔧 Configuración

Cada proyecto puede personalizar los hooks creando un archivo `.security-config.yml`:

```yaml
# Configuración personalizada de seguridad
secrets_detection:
  exclude_patterns:
    - "test/**"
    - "*.example.*"
  custom_patterns:
    - "CUSTOM_API_KEY"

url_check:
  allowed_domains:
    - "api.example.com"
    - "localhost"
```

## 🚀 Instalación en Proyecto

```bash
# Instalar pre-commit
pip install pre-commit
# o con homebrew: brew install pre-commit

# Instalar hooks en el proyecto
pre-commit install

# Ejecutar en todos los archivos (primera vez)
pre-commit run --all-files
```

## 📋 Estructura

```
├── .pre-commit-hooks.yaml      # Definición de hooks
├── scripts/
│   ├── security-scan.sh
│   ├── secrets-detection.sh
│   ├── url-hardcoded-check.sh
│   └── dependency-vulnerabilities.sh
├── configs/
│   ├── secrets-patterns.txt
│   ├── allowed-urls.txt
│   └── vulnerability-sources.yml
└── docs/
    ├── setup.md
    └── customization.md
```