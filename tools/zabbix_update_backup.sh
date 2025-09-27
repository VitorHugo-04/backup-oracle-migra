#!/bin/bash

# Script de Atualização para execução via Zabbix
# Versão: 1.0

set -e

# Configurações
REPO_URL="https://github.com/seu-usuario/backup-oracle-migra.git"
INSTALL_DIR="/u01/app/oracle/MigraTI/MigraBKP"
CONFIG_FILE="/etc/migra.conf"
LOG_FILE="/var/log/backup_update.log"

# Função de log
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
    exit 1
}

# Função principal
main() {
    log "=== Iniciando atualização do sistema de backup ==="
    
    # Backup da configuração atual
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log "Backup da configuração criado"
    fi
    
    # Atualiza ou clona repositório
    if [ -d "$INSTALL_DIR/.git" ]; then
        log "Atualizando repositório existente..."
        cd "$INSTALL_DIR"
        git fetch origin || error_exit "Falha ao fazer fetch"
        git reset --hard origin/main || error_exit "Falha ao resetar repositório"
    else
        log "Clonando repositório..."
        [ -d "$INSTALL_DIR" ] && mv "$INSTALL_DIR" "${INSTALL_DIR}.old.$(date +%Y%m%d_%H%M%S)"
        git clone "$REPO_URL" "$INSTALL_DIR" || error_exit "Falha ao clonar repositório"
        cd "$INSTALL_DIR"
    fi
    
    # Mescla configurações
    if [ -f "${CONFIG_FILE}.backup.$(date +%Y%m%d)_"* ]; then
        log "Mesclando configurações..."
        latest_backup=$(ls -t ${CONFIG_FILE}.backup.* | head -1)
        bash "$INSTALL_DIR/tools/merge_config.sh" \
            "$INSTALL_DIR/config/migra.conf.template" \
            "$latest_backup" \
            "/tmp/migra.conf.new" || error_exit "Falha ao mesclar configurações"
        
        cp "/tmp/migra.conf.new" "$CONFIG_FILE" || error_exit "Falha ao instalar nova configuração"
        rm -f "/tmp/migra.conf.new"
    fi
    
    # Atualiza scripts
    log "Atualizando scripts..."
    cp "$INSTALL_DIR/scripts/"*.sh "$INSTALL_DIR/bin/" || error_exit "Falha ao copiar scripts"
    chmod +x "$INSTALL_DIR/bin/"*.sh
    
    # Verifica versão atualizada
    if [ -f "$CONFIG_FILE" ]; then
        version=$(grep "export VERSION=" "$CONFIG_FILE" | cut -d'=' -f2)
        log "Atualização concluída! Versão: $version"
    fi
    
    log "=== Atualização finalizada com sucesso ==="
    echo "SUCCESS"
}

# Executa
main "$@" 2>&1
