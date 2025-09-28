#!/bin/bash

# Script de Atualização SEM Git - para execução via Zabbix
# Baixa tar.gz em vez de usar git

set -e

REPO_URL="https://github.com/VitorHugo-04/backup-oracle-migra/archive/refs/heads/main.tar.gz"
INSTALL_DIR="$ORACLE_BASE/MigraTI/MigraBKP"
CONFIG_FILE="/etc/migra.conf"
LOG_FILE="/var/log/backup_update.log"
TEMP_DIR="/tmp/migra_update_$$"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

error_exit() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1" | tee -a "$LOG_FILE"
    rm -rf "$TEMP_DIR"
    exit 1
}

main() {
    log "=== Iniciando atualização do sistema de backup ==="
    
    # Backup da configuração atual
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        log "Backup da configuração criado"
    fi
    
    # Criar diretório temporário
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    # Baixar nova versão
    log "Baixando nova versão..."
    wget -q "$REPO_URL" -O migra.tar.gz || error_exit "Falha ao baixar repositório"
    tar -xzf migra.tar.gz || error_exit "Falha ao extrair arquivos"
    
    # Encontrar diretório extraído
    extracted_dir=$(find . -name "backup-oracle-migra-*" -type d | head -1)
    [ -z "$extracted_dir" ] && error_exit "Diretório extraído não encontrado"
    
    # Backup da instalação atual
    if [ -d "$INSTALL_DIR" ]; then
        mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
    fi
    
    # Copiar nova versão
    log "Instalando nova versão..."
    mkdir -p "$INSTALL_DIR"/{bin,tmp,log,tools}
    cp -r "$extracted_dir/scripts/"* "$INSTALL_DIR/bin/"
    cp -r "$extracted_dir/tools/"* "$INSTALL_DIR/tools/"
    
    # Mesclar configurações se existir backup
    if [ -f "${CONFIG_FILE}.backup.$(date +%Y%m%d)"* ]; then
        log "Mesclando configurações..."
        latest_backup=$(ls -t ${CONFIG_FILE}.backup.* | head -1)
        bash "$INSTALL_DIR/tools/merge_config.sh" \
            "$extracted_dir/config/migra.conf.template" \
            "$latest_backup" \
            "$CONFIG_FILE" || error_exit "Falha ao mesclar configurações"
    fi
    
    # Definir permissões
    chmod +x "$INSTALL_DIR/bin/"*.sh
    chmod +x "$INSTALL_DIR/tools/"*.sh
    
    # Verificar versão
    if [ -f "$CONFIG_FILE" ]; then
        version=$(grep "export VERSION=" "$CONFIG_FILE" | cut -d'=' -f2)
        log "Atualização concluída! Versão: $version"
    fi
    
    # Limpeza
    rm -rf "$TEMP_DIR"
    
    log "=== Atualização finalizada com sucesso ==="
    echo "SUCCESS"
}

main "$@" 2>&1
