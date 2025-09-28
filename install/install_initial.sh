#!/bin/bash

# Instalação Inicial SEM Git - Copia arquivos locais
# Para usar após extrair o tar.gz

set -e

INSTALL_DIR="/u01/app/oracle/MigraTI/MigraBKP"
CONFIG_FILE="/etc/migra.conf"
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $1"
    exit 1
}

log "=== Instalação Inicial do Sistema de Backup (Sem Git) ==="

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

# Criar estrutura de diretórios
log "Criando estrutura de diretórios..."
mkdir -p "$INSTALL_DIR"/{bin,tmp,log}

# Copiar arquivos do pacote extraído
log "Copiando scripts..."
cp -r "$CURRENT_DIR"/../scripts/* "$INSTALL_DIR/bin/" || error_exit "Falha ao copiar scripts"

log "Copiando ferramentas..."
mkdir -p "$INSTALL_DIR/tools"
cp -r "$CURRENT_DIR"/../tools/* "$INSTALL_DIR/tools/" || error_exit "Falha ao copiar tools"

# Configuração
if [ -f "${CONFIG_FILE}.backup."* ]; then
    log "Mesclando configuração anterior..."
    latest_backup=$(ls -t ${CONFIG_FILE}.backup.* | head -1)
    bash "$INSTALL_DIR/tools/merge_config.sh" \
        "$CURRENT_DIR/../config/migra.conf.template" \
        "$latest_backup" \
        "$CONFIG_FILE" || error_exit "Falha ao mesclar configurações"
else
    log "Criando configuração inicial..."
    cp "$CURRENT_DIR/../config/migra.conf.template" "$CONFIG_FILE" || error_exit "Falha ao criar configuração"
    log "ATENÇÃO: Configure as variáveis específicas em $CONFIG_FILE"
fi

# Definir permissões
chmod +x "$INSTALL_DIR/bin/"*.sh
chmod +x "$INSTALL_DIR/tools/"*.sh
chmod 644 "$CONFIG_FILE"

# Configurar Zabbix
log "Configurando Zabbix Agent..."
cp "$INSTALL_DIR/tools/zabbix_update_backup.sh" /usr/local/bin/
chmod +x /usr/local/bin/zabbix_update_backup.sh

# Adicionar UserParameter se não existir
if ! grep -q "backup.update" /etc/zabbix/zabbix_agentd.conf 2>/dev/null; then
    echo "UserParameter=backup.update,/usr/local/bin/zabbix_update_backup.sh" >> /etc/zabbix/zabbix_agentd.conf
    log "UserParameter adicionado ao Zabbix"
fi

log "=== Instalação concluída ==="
log "Próximos passos:"
log "1. Configure as variáveis específicas em: $CONFIG_FILE"
log "2. Reinicie o Zabbix Agent: systemctl restart zabbix-agent"
log "3. Teste o backup: $INSTALL_DIR/bin/bkp_logico.sh <INSTANCE> <TIPO>"
