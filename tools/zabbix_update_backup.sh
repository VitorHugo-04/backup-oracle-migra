#!/bin/bash

# Script de Atualização para execução via Zabbix
# Versão: 1.1 - Detecta ORACLE_BASE automaticamente

set -e

# Configurações
REPO_URL="https://github.com/VitorHugo-04/backup-oracle-migra/archive/refs/heads/main.tar.gz"
LOG_FILE="/var/log/backup_update.log"

# Detectar ORACLE_BASE automaticamente
detect_oracle_base() {
    # Método 1: Variável de ambiente
    if [ -n "$ORACLE_BASE" ]; then
        echo "$ORACLE_BASE"
        return
    fi
    
    # Método 2: Ler do migra.conf atual (via link simbólico)
    if [ -f "/etc/migra.conf" ]; then
        local oracle_base=$(grep "export ORACLE_BASE=" "/etc/migra.conf" | cut -d'=' -f2)
        if [ -n "$oracle_base" ]; then
            echo "$oracle_base"
            return
        fi
    fi
    
    # Método 3: Procurar diretórios comuns
    for path in /u01/app/oracle /opt/oracle /oracle; do
        if [ -d "$path" ]; then
            echo "$path"
            return
        fi
    done
    
    # Método 4: Procurar pela estrutura MigraTI existente
    local migra_path=$(find /u01 /opt /oracle -name "MigraTI" -type d 2>/dev/null | head -1)
    if [ -n "$migra_path" ]; then
        echo "$(dirname "$migra_path")"
        return
    fi
    
    # Padrão se não encontrar
    echo "/u01/app/oracle"
}

ORACLE_BASE=$(detect_oracle_base)
INSTALL_DIR="$ORACLE_BASE/MigraTI/MigraBKP"
CONFIG_FILE="$INSTALL_DIR/bin/migra.conf"
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
    log "ORACLE_BASE detectado: $ORACLE_BASE"
    log "Diretório de instalação: $INSTALL_DIR"
    
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
        log "Backup da instalação atual criado"
    fi
    
    # Copiar nova versão
    log "Instalando nova versão..."
    mkdir -p "$INSTALL_DIR"/{bin,tmp,log,tools}
    cp -r "$extracted_dir/scripts/"* "$INSTALL_DIR/bin/"
    cp -r "$extracted_dir/tools/"* "$INSTALL_DIR/tools/"
    
    # Mesclar configurações se existir backup
    if ls ${CONFIG_FILE}.backup.* >/dev/null 2>&1; then
        log "Mesclando configurações..."
        latest_backup=$(ls -t ${CONFIG_FILE}.backup.* | head -1)
        bash "$INSTALL_DIR/tools/merge_config.sh" \
            "$extracted_dir/config/migra.conf.template" \
            "$latest_backup" \
            "$CONFIG_FILE" || error_exit "Falha ao mesclar configurações"
    else
        # Primeira instalação - usar template
        log "Primeira instalação - criando configuração inicial..."
        cp "$extracted_dir/config/migra.conf.template" "$CONFIG_FILE"
        # Atualizar ORACLE_BASE no arquivo
        sed -i "s|export ORACLE_BASE=.*|export ORACLE_BASE=$ORACLE_BASE|" "$CONFIG_FILE"
    fi
    
    # Criar/recriar link simbólico /etc/migra.conf -> arquivo real
    log "Criando link simbólico..."
    ln -sf "$CONFIG_FILE" "/etc/migra.conf"
    
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
