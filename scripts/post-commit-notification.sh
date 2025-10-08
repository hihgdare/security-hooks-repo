#!/bin/bash

# Post-commit notification hook
# Envía notificaciones después de commits exitosos

set -e

# Colores
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}📬 Ejecutando notificaciones post-commit...${NC}"

# Configuración
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
PROJECT_NAME=$(basename "$PROJECT_ROOT")
COMMIT_HASH=$(git rev-parse HEAD)
COMMIT_MESSAGE=$(git log -1 --pretty=%B)
AUTHOR_NAME=$(git log -1 --pretty=%an)
AUTHOR_EMAIL=$(git log -1 --pretty=%ae)
BRANCH_NAME=$(git rev-parse --abbrev-ref HEAD)
REPO_URL=$(git config --get remote.origin.url 2>/dev/null || echo "No configurado")

# Información del commit
echo -e "${BLUE}📋 Información del commit:${NC}"
echo -e "${BLUE}  Proyecto: $PROJECT_NAME${NC}"
echo -e "${BLUE}  Commit: ${COMMIT_HASH:0:8}${NC}"
echo -e "${BLUE}  Rama: $BRANCH_NAME${NC}"
echo -e "${BLUE}  Autor: $AUTHOR_NAME <$AUTHOR_EMAIL>${NC}"
echo -e "${BLUE}  Mensaje: $COMMIT_MESSAGE${NC}"

# Archivos modificados
FILES_CHANGED=$(git diff --name-only HEAD~1 HEAD)
FILES_COUNT=$(echo "$FILES_CHANGED" | wc -l)

echo -e "${BLUE}  Archivos modificados: $FILES_COUNT${NC}"

# Estadísticas del commit
ADDITIONS=$(git diff --shortstat HEAD~1 HEAD | grep -o '[0-9]* insertion' | cut -d' ' -f1 || echo "0")
DELETIONS=$(git diff --shortstat HEAD~1 HEAD | grep -o '[0-9]* deletion' | cut -d' ' -f1 || echo "0")

echo -e "${BLUE}  Líneas agregadas: ${ADDITIONS:-0}${NC}"
echo -e "${BLUE}  Líneas eliminadas: ${DELETIONS:-0}${NC}"

# Verificar si hay configuración de notificaciones
CONFIG_FILE="$PROJECT_ROOT/.security-config.yml"
NOTIFICATION_ENABLED=false
SLACK_WEBHOOK=""
DISCORD_WEBHOOK=""
EMAIL_ENABLED=false

if [ -f "$CONFIG_FILE" ]; then
    # Extraer configuración de notificaciones (implementación básica)
    if grep -q "notifications:" "$CONFIG_FILE"; then
        NOTIFICATION_ENABLED=true
        SLACK_WEBHOOK=$(grep "slack_webhook:" "$CONFIG_FILE" | cut -d':' -f2- | tr -d ' "' || echo "")
        DISCORD_WEBHOOK=$(grep "discord_webhook:" "$CONFIG_FILE" | cut -d':' -f2- | tr -d ' "' || echo "")
        EMAIL_ENABLED=$(grep "email_notifications:" "$CONFIG_FILE" | grep -q "true" && echo "true" || echo "false")
    fi
fi

# Función para enviar notificación a Slack
send_slack_notification() {
    local webhook_url="$1"
    
    if [ -z "$webhook_url" ]; then
        return 0
    fi
    
    echo -e "${BLUE}📱 Enviando notificación a Slack...${NC}"
    
    # Crear payload JSON
    local payload=$(cat <<EOF
{
    "text": "Nuevo commit en $PROJECT_NAME",
    "blocks": [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": "🚀 Nuevo Commit"
            }
        },
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "*Proyecto:*\n$PROJECT_NAME"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Rama:*\n$BRANCH_NAME"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Autor:*\n$AUTHOR_NAME"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Commit:*\n${COMMIT_HASH:0:8}"
                }
            ]
        },
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*Mensaje:*\n$COMMIT_MESSAGE"
            }
        },
        {
            "type": "section",
            "fields": [
                {
                    "type": "mrkdwn",
                    "text": "*Archivos:*\n$FILES_COUNT modificados"
                },
                {
                    "type": "mrkdwn",
                    "text": "*Cambios:*\n+${ADDITIONS:-0} -${DELETIONS:-0} líneas"
                }
            ]
        }
    ]
}
EOF
)
    
    # Enviar notificación
    if command -v curl >/dev/null 2>&1; then
        if curl -X POST -H 'Content-type: application/json' --data "$payload" "$webhook_url" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Notificación enviada a Slack${NC}"
        else
            echo -e "${YELLOW}⚠️  Error enviando notificación a Slack${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  curl no disponible para enviar notificación a Slack${NC}"
    fi
}

# Función para enviar notificación a Discord
send_discord_notification() {
    local webhook_url="$1"
    
    if [ -z "$webhook_url" ]; then
        return 0
    fi
    
    echo -e "${BLUE}📱 Enviando notificación a Discord...${NC}"
    
    # Crear payload JSON para Discord
    local payload=$(cat <<EOF
{
    "content": null,
    "embeds": [
        {
            "title": "🚀 Nuevo Commit en $PROJECT_NAME",
            "description": "$COMMIT_MESSAGE",
            "color": 5814783,
            "fields": [
                {
                    "name": "👤 Autor",
                    "value": "$AUTHOR_NAME",
                    "inline": true
                },
                {
                    "name": "🌿 Rama",
                    "value": "$BRANCH_NAME",
                    "inline": true
                },
                {
                    "name": "📝 Commit",
                    "value": "${COMMIT_HASH:0:8}",
                    "inline": true
                },
                {
                    "name": "📊 Estadísticas",
                    "value": "$FILES_COUNT archivos modificados\n+${ADDITIONS:-0} -${DELETIONS:-0} líneas",
                    "inline": false
                }
            ],
            "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
        }
    ]
}
EOF
)
    
    # Enviar notificación
    if command -v curl >/dev/null 2>&1; then
        if curl -X POST -H 'Content-type: application/json' --data "$payload" "$webhook_url" >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Notificación enviada a Discord${NC}"
        else
            echo -e "${YELLOW}⚠️  Error enviando notificación a Discord${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  curl no disponible para enviar notificación a Discord${NC}"
    fi
}

# Función para mostrar resumen local
show_local_summary() {
    echo -e "\n${GREEN}🎉 ¡Commit exitoso!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📋 Resumen:${NC}"
    echo -e "${GREEN}  • Proyecto: $PROJECT_NAME${NC}"
    echo -e "${GREEN}  • Commit: ${COMMIT_HASH:0:8} en rama $BRANCH_NAME${NC}"
    echo -e "${GREEN}  • Cambios: $FILES_COUNT archivos (+${ADDITIONS:-0} -${DELETIONS:-0} líneas)${NC}"
    echo -e "${GREEN}  • Autor: $AUTHOR_NAME${NC}"
    echo ""
    echo -e "${BLUE}💡 Próximos pasos recomendados:${NC}"
    echo -e "${BLUE}  • git push origin $BRANCH_NAME (para subir cambios)${NC}"
    echo -e "${BLUE}  • Crear pull request si estás en una rama feature${NC}"
    echo -e "${BLUE}  • Verificar que los tests pasen en CI/CD${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Ejecutar notificaciones si están habilitadas
if [ "$NOTIFICATION_ENABLED" = true ]; then
    echo -e "\n${BLUE}📬 Enviando notificaciones...${NC}"
    
    # Slack
    if [ -n "$SLACK_WEBHOOK" ]; then
        send_slack_notification "$SLACK_WEBHOOK"
    fi
    
    # Discord
    if [ -n "$DISCORD_WEBHOOK" ]; then
        send_discord_notification "$DISCORD_WEBHOOK"
    fi
    
    # Email (implementación básica)
    if [ "$EMAIL_ENABLED" = "true" ]; then
        echo -e "${YELLOW}📧 Email notifications configuradas pero no implementadas en este hook${NC}"
        echo -e "${YELLOW}💡 Considerar integrar con sendmail, mailgun, o similar${NC}"
    fi
else
    echo -e "${YELLOW}📬 Notificaciones no configuradas${NC}"
    echo -e "${YELLOW}💡 Para habilitar, configurar en .security-config.yml:${NC}"
    echo -e "${YELLOW}   notifications:${NC}"
    echo -e "${YELLOW}     slack_webhook: 'https://hooks.slack.com/...'${NC}"
    echo -e "${YELLOW}     discord_webhook: 'https://discord.com/api/webhooks/...'${NC}"
fi

# Mostrar resumen local siempre
show_local_summary

# Verificar si hay cambios sin push
UNPUSHED_COMMITS=$(git log --oneline @{upstream}..HEAD 2>/dev/null | wc -l || echo "0")
if [ "$UNPUSHED_COMMITS" -gt 0 ]; then
    echo -e "\n${YELLOW}📤 Tienes $UNPUSHED_COMMITS commit(s) sin subir${NC}"
    echo -e "${YELLOW}💡 Ejecuta: git push origin $BRANCH_NAME${NC}"
fi

echo -e "\n${GREEN}✅ Post-commit hook completado${NC}"