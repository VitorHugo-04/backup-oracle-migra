#!/bin/bash

# Script para mesclar configurações do migra.conf
# Mantém valores específicos do cliente e adiciona novas variáveis do template

TEMPLATE_FILE="$1"
CURRENT_CONFIG="$2"
OUTPUT_FILE="$3"

if [ $# -ne 3 ]; then
    echo "Uso: $0 <template_file> <current_config> <output_file>"
    exit 1
fi

# Função para extrair variáveis de um arquivo
extract_variables() {
    local file="$1"
    if [ -f "$file" ]; then
        grep -E "^\s*export\s+[A-Z_]+=.*" "$file" | sed 's/^\s*export\s*//' | sed 's/=.*//'
    fi
}

# Função para obter valor de uma variável
get_variable_value() {
    local file="$1"
    local var="$2"
    if [ -f "$file" ]; then
        grep -E "^\s*export\s+${var}=" "$file" | head -1 | sed 's/.*=//'
    fi
}

# Função para obter linha completa da variável (incluindo comentários acima)
get_variable_block() {
    local file="$1"
    local var="$2"
    local temp_file="/tmp/var_block_$$"
    
    if [ -f "$file" ]; then
        # Encontra a linha da variável e pega contexto anterior
        local line_num=$(grep -n "^\s*export\s*${var}=" "$file" | cut -d: -f1 | head -1)
        if [ -n "$line_num" ]; then
            # Pega até 3 linhas anteriores se forem comentários
            local start_line=$((line_num - 3))
            [ $start_line -lt 1 ] && start_line=1
            
            sed -n "${start_line},${line_num}p" "$file" | tac | while read line; do
                if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+${var}= ]]; then
                    echo "$line"
                    break
                elif [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
                    echo "$line"
                else
                    break
                fi
            done | tac
        fi
    fi
}

echo "# Configuração mesclada automaticamente em $(date)" > "$OUTPUT_FILE"
echo "# Template: $(basename "$TEMPLATE_FILE")" >> "$OUTPUT_FILE"
echo "# Configuração anterior preservada de: $(basename "$CURRENT_CONFIG")" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Extrai todas as variáveis do template e da configuração atual
template_vars=$(extract_variables "$TEMPLATE_FILE")
current_vars=$(extract_variables "$CURRENT_CONFIG")

# Processa cada seção do template
current_section=""
while IFS= read -r line; do
    # Detecta comentários de seção
    if [[ "$line" =~ ^#.*[Pp]arametr|^#.*[Vv]ariav|^#.*[Cc]opiar|^#.*[Mm]onitor ]]; then
        current_section="$line"
        echo "$line" >> "$OUTPUT_FILE"
        continue
    fi
    
    # Linhas vazias e outros comentários
    if [[ -z "${line// }" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
        echo "$line" >> "$OUTPUT_FILE"
        continue
    fi
    
    # Processa variáveis export
    if [[ "$line" =~ ^[[:space:]]*export[[:space:]]+([A-Z_]+)= ]]; then
        var_name="${BASH_REMATCH[1]}"
        
        # Se a variável existe na configuração atual, usa o valor atual
        if echo "$current_vars" | grep -q "^${var_name}$"; then
            current_value=$(get_variable_value "$CURRENT_CONFIG" "$var_name")
            echo "        export ${var_name}=${current_value}" >> "$OUTPUT_FILE"
        else
            # Nova variável do template
            echo "$line" >> "$OUTPUT_FILE"
        fi
    else
        # Outras linhas (não export)
        echo "$line" >> "$OUTPUT_FILE"
    fi
    
done < "$TEMPLATE_FILE"

# Adiciona variáveis que existem na configuração atual mas não no template
echo "" >> "$OUTPUT_FILE"
echo "# Variáveis específicas do cliente (não presentes no template)" >> "$OUTPUT_FILE"

for var in $current_vars; do
    if ! echo "$template_vars" | grep -q "^${var}$"; then
        current_value=$(get_variable_value "$CURRENT_CONFIG" "$var")
        echo "        export ${var}=${current_value}" >> "$OUTPUT_FILE"
    fi
done

echo "Configuração mesclada salva em: $OUTPUT_FILE"
