#!/bin/bash

# Script para preparar clientes existentes para atualizações automáticas

set -e

SCRIPT_URL="https://raw.githubusercontent.com/VitorHugo-04/backup-oracle-migra/main/tools/zabbix_update_backup.sh"
SCRIPT_PATH="/usr/local/bin/zabbix_update_backup.sh"
ZABBIX_CONF="/etc/zabbix/zabbix_agentd.conf"

echo "=== Preparando cliente para atualizações automáticas ==="

# Baixar script de atualização
echo "Baixando script de atualização..."
wget -q "$SCRIPT_URL" -O "$SCRIPT_PATH" || {
    echo "ERRO: Falha ao baixar script"
    exit 1
}

# Dar permissão
chmod +x "$SCRIPT_PATH"
echo "Script instalado em: $SCRIPT_PATH"

# Configurar Zabbix Agent
if ! grep -q "backup.update" "$ZABBIX_CONF" 2>/dev/null; then
    echo "UserParameter=backup.update,$SCRIPT_PATH" >> "$ZABBIX_CONF"
    echo "UserParameter adicionado ao Zabbix"
else
    echo "UserParameter já existe no Zabbix"
fi

# Reiniciar Zabbix Agent
systemctl restart zabbix-agent
echo "Zabbix Agent reiniciado"

# Testar
echo "Testando configuração..."
if zabbix_get -s localhost -k backup.update >/dev/null 2>&1; then
    echo "✅ Cliente preparado com sucesso!"
    echo "Agora você pode executar atualizações via Zabbix"
else
    echo "⚠️  Teste falhou - verifique configuração do Zabbix"
fi
