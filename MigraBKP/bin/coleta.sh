set -x
#!/bin/ksh
#################################################
# Coleta de Estatisticas - MigraTI              #
# Blumenau - SC / +55 (47) 3328-0996            #
# Desenvolvido por Vinicius Gabriel Lana        #
#              <vinicius.gabriel@migrati.com.br>#
#                                               #
#        Tecnologia de uso privado!             #
#################################################

source /etc/migra.conf 
#Testando se a rotina não esta rodando
if ls ${DIR_TMP}/stats.pid 1> /dev/null 2>&1; then
    echo "ROTINA JA ESTA EM EXECUCAO"
    if [ "${TITAN}" == "S" ];  then
        $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Estatisticas_Oracle -s $T_Host -o 3
    fi

else
touch ${DIR_TMP}/stats.pid

DISPLAY(){
echo "[`date '+%d/%m/%Y %T'`] $*" >> $ARQ_LOG_GERAL
}

INICIO_STATS="`date '+%d/%m/%Y %T'`"

GERA_OWNER(){
# Funcao para Gerar Lista de todos os owner da base com tabelas
${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} 2>&1 <<EOF
whenever sqlerror exit sql.sqlcode ;
set tab off
set pagesize 0
set linesize 80
set feedback off
set termout off
spool ${ARQ_OWNER}
select distinct owner
from sys.dba_tables
where owner not in (select owner from migrabkp.exclude_owner)
order by 1;
spool off;
quit
EOF

if [ "$?" = "0" ]
then
  DISPLAY "Status da Lista de usuario..: OK"
  DISPLAY "==============================="
  DISPLAY "==============================="
else
  DISPLAY "Status da Lista de usuario..: ERRO"
fi
}

STATS_OWNER()
{
# Gera A lista de Usuarios com tabelas
GERA_OWNER
# executa Expdp

for USUARIO in `cat ${ARQ_OWNER}`
do

 
  ARQ_DATE=`date +%Y%m%d%H`
  LOG_STATS=${DIR_LOG}/gather_schema_stats_${USUARIO}_${ARQ_DATE}.log

  DISPLAY "Status do Usuario.............: ${USUARIO}"
  DISPLAY "Inicio........................: `date '+%d/%m/%Y %T'`"

${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} 2>&1 <<EOF
spool ${LOG_STATS}
exec dbms_stats.gather_schema_stats(ownname=>'${USUARIO}', cascade=> TRUE, estimate_percent=> 60, degree=> 8, options=> 'GATHER');
spool off;
quit
EOF

if [ "$?" = "0" ]
then
  DISPLAY "Status da Lista de usuario..: OK"
  DISPLAY "==============================="
  DISPLAY "==============================="
else
  DISPLAY "Status da Lista de usuario..: ERRO"
fi
#Verifica se o backup foi executado com sucesso
if [ -e ${LOG_STATS} ]
then
#       if [ grep -e "successfully completed"  ${DIR_DMP}/${ARQ_LOG} ]
	if [ "${ENGLISH}" == "S" ]; then
		if [ "$(cat ${LOG_STATS} | grep -e "procedure successfully completed")" ]
		then
            STATUS=OK
			STATUS_GERAL=OK
		else
			DISPLAY "Erro na coleta"
            STATUS=ERRO
			STATUS_GERAL=ERRO
		fi
	else
			if [ "$(cat ${LOG_STATS} | grep -e "concluido com sucesso")" ]
		then
            STATUS=OK
			STATUS_GERAL=OK
		else
			DISPLAY "Erro na coleta"
            STATUS=ERRO
			STATUS_GERAL=ERRO
		fi
	fi
else
  STATUS=ERRO
  STATUS_GERAL=ERRO
fi

#Verifica se todo o procedimento do backup de cada owner foi efetuado com sucesso
# Melhorar esta verificação.
DISPLAY ${STATUS}
  DISPLAY "==============================="
done


FIM_STATS="`date '+%d/%m/%Y %T'`"

DISPLAY "==============================="
DISPLAY "==============================="
DISPLAY "====R E S U M O   G E R A L===="
DISPLAY "Inicio da coleta..............: ${INICIO_STATS}"
DISPLAY "Fim da coleta.................: ${FIM_STATS}"


DISPLAY "Log da Execucao da coleta.....: ${ARQ_LOG_GERAL}"
DISPLAY "Status do Coleta..............: ${STATUS_GERAL}"
DISPLAY "==============================="
DISPLAY "==============================="

}


STATS_OWNER

# Manutencao arquivos
find ${DIR_LOG}/* -mtime +${RETENCAO_LOG} -print -exec rm -f {} \; > /dev/null 2>&1

if [ "${STATUS_GERAL}" = "OK" ]
then
STATUS_MOM=0
else
STATUS_MOM=1
fi
#/etc/zabbix/zabbix_sender -c /etc/zabbix/zabbix_agentd.conf -z 177.7.216.89 -k Backup_Logico -s oracle.hospital-lar.local -o $STATUS_MOM
if [ "${TITAN}" == "S" ];  then
        DISPLAY " Enviando resultado ao monitoramento "
        $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Estatisticas_Oracle -s $T_Host -o $STATUS_MOM
fi

rm -rf ${DIR_TMP}/stats.pid

fi


