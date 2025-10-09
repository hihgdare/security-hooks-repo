#!/usr/bin/env bash

# Post-commit security report
# Genera reportes de seguridad después de commits

set -e

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}📊 Generando reporte de seguridad post-commit...${NC}"

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

PROJECT_NAME=$(basename "$PROJECT_ROOT")
COMMIT_HASH=$(git rev-parse HEAD)
REPORT_DIR="$PROJECT_ROOT/.security-reports"

# En Windows, asegurar que el path del directorio sea correcto
if [ "$IS_WINDOWS" = true ]; then
    REPORT_DIR=$(echo "$REPORT_DIR" | sed 's|\\|/|g')
fi

REPORT_FILE="$REPORT_DIR/security-report-$(date +%Y%m%d-%H%M%S).json"

# Crear directorio de reportes si no existe
mkdir -p "$REPORT_DIR"

# Información del commit
COMMIT_MESSAGE=$(git log -1 --pretty=%B)
AUTHOR_NAME=$(git log -1 --pretty=%an)
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

# Archivos modificados en este commit
FILES_CHANGED=$(git diff --name-only HEAD~1 HEAD)
FILES_COUNT=$(echo "$FILES_CHANGED" | wc -l)

# Función para contar líneas de código
count_loc() {
    local files="$1"
    local total=0
    
    while read -r file; do
        if [ -f "$file" ] && [[ "$file" =~ \.(ts|tsx|js|jsx|py|go|rs|java|php)$ ]]; then
            lines=$(wc -l < "$file" 2>/dev/null || echo "0")
            total=$((total + lines))
        fi
    done <<< "$files"
    
    echo "$total"
}

# Función para detectar tipos de archivos
analyze_file_types() {
    local files="$1"
    declare -A file_types
    
    while read -r file; do
        if [ -f "$file" ]; then
            ext="${file##*.}"
            case "$ext" in
                ts|tsx) file_types["typescript"]=$((${file_types["typescript"]:-0} + 1)) ;;
                js|jsx) file_types["javascript"]=$((${file_types["javascript"]:-0} + 1)) ;;
                py) file_types["python"]=$((${file_types["python"]:-0} + 1)) ;;
                go) file_types["go"]=$((${file_types["go"]:-0} + 1)) ;;
                rs) file_types["rust"]=$((${file_types["rust"]:-0} + 1)) ;;
                java) file_types["java"]=$((${file_types["java"]:-0} + 1)) ;;
                php) file_types["php"]=$((${file_types["php"]:-0} + 1)) ;;
                json) file_types["json"]=$((${file_types["json"]:-0} + 1)) ;;
                yml|yaml) file_types["yaml"]=$((${file_types["yaml"]:-0} + 1)) ;;
                md) file_types["markdown"]=$((${file_types["markdown"]:-0} + 1)) ;;
                *) file_types["other"]=$((${file_types["other"]:-0} + 1)) ;;
            esac
        fi
    done <<< "$files"
    
    # Convertir a JSON
    echo "{"
    first=true
    for type in "${!file_types[@]}"; do
        if [ "$first" = false ]; then echo ","; fi
        echo "    \"$type\": ${file_types[$type]}"
        first=false
    done
    echo "  }"
}

# Función para verificar patrones de seguridad
security_scan_summary() {
    local files="$1"
    local secrets_found=0
    local urls_found=0
    local console_logs=0
    local todos=0
    
    # Contar secretos potenciales
    secrets_found=$(echo "$files" | xargs grep -l -E -i "(api[_-]?key|token|secret|password)\s*[=:]\s*['\"][^'\"]{8,}" 2>/dev/null | wc -l || echo "0")
    
    # Contar URLs hardcodeadas
    urls_found=$(echo "$files" | xargs grep -l -E "https?://[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9]*\.[a-zA-Z]{2,}" 2>/dev/null | grep -v -E "(localhost|127\.0\.0\.1|example\.com|github\.com)" | wc -l || echo "0")
    
    # Contar console.log
    console_logs=$(echo "$files" | xargs grep -l "console\." 2>/dev/null | wc -l || echo "0")
    
    # Contar TODOs
    todos=$(echo "$files" | xargs grep -l -i "TODO\|FIXME\|HACK\|XXX" 2>/dev/null | wc -l || echo "0")
    
    echo "{
    \"potential_secrets\": $secrets_found,
    \"hardcoded_urls\": $urls_found,
    \"console_statements\": $console_logs,
    \"todo_comments\": $todos
  }"
}

# Función para verificar dependencias
dependency_summary() {
    local deps_modified=false
    local package_json_changed=false
    local lock_files_changed=false
    
    if echo "$FILES_CHANGED" | grep -E "package\.json|requirements\.txt|go\.mod|Cargo\.toml|composer\.json" >/dev/null; then
        deps_modified=true
        package_json_changed=true
    fi
    
    if echo "$FILES_CHANGED" | grep -E "package-lock\.json|yarn\.lock|bun\.lockb|Pipfile\.lock|go\.sum|Cargo\.lock|composer\.lock" >/dev/null; then
        lock_files_changed=true
    fi
    
    echo "{
    \"dependencies_modified\": $deps_modified,
    \"package_files_changed\": $package_json_changed,
    \"lock_files_changed\": $lock_files_changed
  }"
}

# Función para calcular métricas de complejidad
complexity_metrics() {
    local total_loc
    local code_files
    local avg_file_size=0
    
    code_files=$(echo "$FILES_CHANGED" | grep -E '\.(ts|tsx|js|jsx|py|go|rs|java|php)$' || echo "")
    
    if [ -n "$code_files" ]; then
        total_loc=$(count_loc "$code_files")
        file_count=$(echo "$code_files" | wc -l)
        if [ "$file_count" -gt 0 ]; then
            avg_file_size=$((total_loc / file_count))
        fi
    else
        total_loc=0
    fi
    
    echo "{
    \"total_lines_of_code\": $total_loc,
    \"code_files_modified\": $(echo "$code_files" | wc -l),
    \"average_file_size\": $avg_file_size
  }"
}

# Recopilar estadísticas de Git
git_stats() {
    local additions=$(git diff --shortstat HEAD~1 HEAD | grep -o '[0-9]* insertion' | cut -d' ' -f1 || echo "0")
    local deletions=$(git diff --shortstat HEAD~1 HEAD | grep -o '[0-9]* deletion' | cut -d' ' -f1 || echo "0")
    
    echo "{
    \"additions\": ${additions:-0},
    \"deletions\": ${deletions:-0},
    \"files_changed\": $FILES_COUNT
  }"
}

echo -e "${BLUE}📋 Analizando archivos modificados...${NC}"
echo "Archivos a analizar: $FILES_COUNT"

# Generar reporte JSON
echo -e "${BLUE}📊 Generando reporte de seguridad...${NC}"

cat > "$REPORT_FILE" << EOF
{
  "report_metadata": {
    "generated_at": "$TIMESTAMP",
    "project_name": "$PROJECT_NAME",
    "commit_hash": "$COMMIT_HASH",
    "branch": "$BRANCH_NAME",
    "author": "$AUTHOR_NAME",
    "commit_message": "$COMMIT_MESSAGE"
  },
  "git_statistics": $(git_stats),
  "file_analysis": {
    "file_types": $(analyze_file_types "$FILES_CHANGED"),
    "complexity_metrics": $(complexity_metrics)
  },
  "security_analysis": $(security_scan_summary "$FILES_CHANGED"),
  "dependency_analysis": $(dependency_summary),
  "files_modified": [
$(echo "$FILES_CHANGED" | sed 's/^/    "/' | sed 's/$/"/' | paste -sd, -)
  ]
}
EOF

echo -e "${GREEN}✅ Reporte generado: $REPORT_FILE${NC}"

# Mostrar resumen en consola
echo -e "\n${BLUE}📊 Resumen del Reporte de Seguridad:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Leer y mostrar datos del reporte
if command -v jq >/dev/null 2>&1; then
    # Si jq está disponible, usar para formatear
    ADDITIONS=$(jq -r '.git_statistics.additions' "$REPORT_FILE")
    DELETIONS=$(jq -r '.git_statistics.deletions' "$REPORT_FILE")
    POTENTIAL_SECRETS=$(jq -r '.security_analysis.potential_secrets' "$REPORT_FILE")
    HARDCODED_URLS=$(jq -r '.security_analysis.hardcoded_urls' "$REPORT_FILE")
    CONSOLE_STATEMENTS=$(jq -r '.security_analysis.console_statements' "$REPORT_FILE")
    TODO_COMMENTS=$(jq -r '.security_analysis.todo_comments' "$REPORT_FILE")
    DEPS_MODIFIED=$(jq -r '.dependency_analysis.dependencies_modified' "$REPORT_FILE")
else
    # Fallback sin jq
    ADDITIONS=$(grep '"additions"' "$REPORT_FILE" | cut -d':' -f2 | tr -d ' ,')
    DELETIONS=$(grep '"deletions"' "$REPORT_FILE" | cut -d':' -f2 | tr -d ' ,')
    POTENTIAL_SECRETS=$(grep '"potential_secrets"' "$REPORT_FILE" | cut -d':' -f2 | tr -d ' ,')
    HARDCODED_URLS=$(grep '"hardcoded_urls"' "$REPORT_FILE" | cut -d':' -f2 | tr -d ' ,')
    CONSOLE_STATEMENTS=$(grep '"console_statements"' "$REPORT_FILE" | cut -d':' -f2 | tr -d ' ,')
    TODO_COMMENTS=$(grep '"todo_comments"' "$REPORT_FILE" | cut -d':' -f2 | tr -d ' ,')
    DEPS_MODIFIED=$(grep '"dependencies_modified"' "$REPORT_FILE" | cut -d':' -f2 | tr -d ' ,')
fi

echo -e "${BLUE}📈 Estadísticas de Código:${NC}"
echo -e "  • Archivos modificados: $FILES_COUNT"
echo -e "  • Líneas agregadas: $ADDITIONS"
echo -e "  • Líneas eliminadas: $DELETIONS"

echo -e "\n${BLUE}🔒 Análisis de Seguridad:${NC}"
if [ "$POTENTIAL_SECRETS" -gt 0 ]; then
    echo -e "${RED}  • Posibles secretos: $POTENTIAL_SECRETS ❌${NC}"
else
    echo -e "${GREEN}  • Posibles secretos: $POTENTIAL_SECRETS ✅${NC}"
fi

if [ "$HARDCODED_URLS" -gt 0 ]; then
    echo -e "${YELLOW}  • URLs hardcodeadas: $HARDCODED_URLS ⚠️${NC}"
else
    echo -e "${GREEN}  • URLs hardcodeadas: $HARDCODED_URLS ✅${NC}"
fi

echo -e "\n${BLUE}🐛 Calidad de Código:${NC}"
if [ "$CONSOLE_STATEMENTS" -gt 0 ]; then
    echo -e "${YELLOW}  • Console statements: $CONSOLE_STATEMENTS ⚠️${NC}"
else
    echo -e "${GREEN}  • Console statements: $CONSOLE_STATEMENTS ✅${NC}"
fi

if [ "$TODO_COMMENTS" -gt 0 ]; then
    echo -e "${YELLOW}  • Comentarios TODO: $TODO_COMMENTS 📝${NC}"
else
    echo -e "${GREEN}  • Comentarios TODO: $TODO_COMMENTS ✅${NC}"
fi

echo -e "\n${BLUE}📦 Dependencias:${NC}"
if [ "$DEPS_MODIFIED" = "true" ]; then
    echo -e "${BLUE}  • Dependencias modificadas: Sí 📦${NC}"
    echo -e "${YELLOW}  • Recomendación: Ejecutar audit de dependencias${NC}"
else
    echo -e "${GREEN}  • Dependencias modificadas: No ✅${NC}"
fi

# Limpiar reportes antiguos (mantener solo los últimos 10)
echo -e "\n${BLUE}🧹 Limpiando reportes antiguos...${NC}"
cd "$REPORT_DIR"
ls -t security-report-*.json 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
REPORTS_COUNT=$(ls security-report-*.json 2>/dev/null | wc -l)
echo -e "${GREEN}📊 Reportes mantenidos: $REPORTS_COUNT${NC}"

echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Recomendaciones basadas en el análisis
echo -e "\n${BLUE}💡 Recomendaciones:${NC}"

if [ "$POTENTIAL_SECRETS" -gt 0 ] || [ "$HARDCODED_URLS" -gt 0 ]; then
    echo -e "${YELLOW}🔒 Revisar patrones de seguridad detectados${NC}"
fi

if [ "$CONSOLE_STATEMENTS" -gt 0 ]; then
    echo -e "${YELLOW}🐛 Considerar remover console statements para producción${NC}"
fi

if [ "$TODO_COMMENTS" -gt 0 ]; then
    echo -e "${YELLOW}📝 Revisar y planificar resolución de TODOs${NC}"
fi

if [ "$DEPS_MODIFIED" = "true" ]; then
    echo -e "${YELLOW}📦 Ejecutar audit de seguridad en dependencias${NC}"
fi

echo -e "${GREEN}📊 Ver reporte completo en: ${REPORT_FILE#$PROJECT_ROOT/}${NC}"
echo -e "${GREEN}✅ Reporte de seguridad post-commit completado${NC}"

# Flush output para Windows
if [ "$IS_WINDOWS" = true ]; then
    exec 1>&1 2>&2
fi