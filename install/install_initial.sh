#!/bin/bash

# Script de Instalação Inicial do Sistema de Backup
# Para novos clientes ou primeira instalação

set -e

REPO_URL="https://github.com/seu-usuario/backup-oracle-migra.git"
INSTALL_DIR="/u01/app/oracle/MigraTI/MigraBKP"
CONFIG_FILE="/etc/migra.conf"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    exit 1
}

# Verifica se já existe instalação
if [ -d "$INSTALL_DIR/.git" ]; then
    log "Instalação Git já existe. Use o script de atualização."
    exit 0
fi

log "=== Instalação Inicial do Sistema de Backup ==="

# Backup da instalação atual se existir
if [ -d "$INSTALL_DIR" ]; then
    log "Fazendo backup da instalação atual..."
    mv "$INSTALL_DIR" "${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Backup da configuração atual se existir
if [ -f "$CONFIG_FILE" ]; then
    log "Fazendo backup da configuração atual..."
    cp "$CONFIG_FILE" "${CONFIG_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
fi

# Clona repositório
log "Clonando repositório..."
git clone "$REPO_URL" "$INSTALL_DIR" || error_exit "Falha ao clonar repositório"

# Cria estrutura de diretórios
log "Criando estrutura de diretórios..."
mkdir -p "$INSTALL_DIR"/{tmp,log}
chmod 755 "$INSTALL_DIR"/{tmp,log}

# Se existe configuração anterior, mescla com template
if [ -f "${CONFIG_FILE}.backup."* ]; then
    log "Mesclando configuração anterior..."
    latest_backup=$(ls -t ${CONFIG_FILE}.backup.* | head -1)
    bash "$INSTALL_DIR/tools/merge_config.sh" \
        "$INSTALL_DIR/config/migra.conf.template" \
        "$latest_backup" \
        "$CONFIG_FILE"
else
    log "Criando configuração inicial..."
    cp "$INSTALL_DIR/config/migra.conf.template" "$CONFIG_FILE"
    log "ATENÇÃO: Configure as variáveis específicas em $CONFIG_FILE"
fi

# Define permissões
chmod +x "$INSTALL_DIR/bin/"*.sh
chmod +x "$INSTALL_DIR/tools/"*.sh
chmod 644 "$CONFIG_FILE"

log "=== Instalação concluída ==="
log "Próximos passos:"
log "1. Configure as variáveis específicas em: $CONFIG_FILE"
log "2. Teste o backup: $INSTALL_DIR/bin/bkp_logico.sh <INSTANCE> <TIPO>"
log "3. Configure o crontab se necessário"
