set -x
#!/bin/ksh

source /etc/migra.conf
STATUS=0
ERROR_COUNT=0

#Testando se a rotina esta rodando
if [ "${TITAN}" == "S" ]; then
    if ls ${DIR_TMP}/logico_${INSTANCE}.pid 1> /dev/null 2>&1; then
    echo "ROTINA JA ESTA EM EXECUCAO"
    $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Backup_Logico -s $T_Host -o 3
    exit 1
    else
    touch ${DIR_TMP}/logico_${INSTANCE}.pid
    fi
fi

DISPLAY(){
echo "[`date '+%d/%m/%Y %T'`] $*" >> $ARQ_LOG_GERAL
}

echo " " >> $ARQ_LOG_GERAL

INICIO_BACKUP="`date '+%d/%m/%Y %T'`"

# Recebe parametros
DISPLAY "Inicio do Backup .............: Expdp"
DISPLAY "Parametros Recebidos..........:"
DISPLAY "--> Instancia.................: ${INSTANCE}"
DISPLAY "--> Tipo do Backup............: ${TIPO}"
DISPLAY "--> Retencao dos DMPs.........: ${RETENCAO_DMP}"
DISPLAY "--> Retencao dos Logs.........: ${RETENCAO_LOG}"
DISPLAY "==============================="

EVENTO(){
# Funcao que efetua o envio de evento por e-mail

  NR_PARAMETRO=`echo $#`
  DESCRICAO_MENSAGEM="$1"
  SEVERIDADE_MENSAGEM=$2
  ANEXO_MENSAGEM=$3

}

# Funcao para derrubar os jobs falhados
KILL_DATAPUMPS(){
${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} <<EOF
set head off
set pages 0
set lines 200
set feedback off
SELECT 'drop table ' || owner_name || '.' || job_name || ';'
FROM dba_datapump_jobs WHERE state='NOT RUNNING' and attached_sessions=0 and owner_name = UPPER('${USER_EXPORT}');
spool $DIR_TMP/kill_datapumps.sql
/
spool off
exit
EOF
${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} <<EOF
@$DIR_TMP/kill_datapumps.sql
exit
EOF
}


# Cria Funcao para coletar os jobs falhados
COLETA_JOB(){
${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} 2>&1 <<EOF
whenever sqlerror exit sql.sqlcode ;
set tab off
set pagesize 0
set linesize 80
set feedback off
set termout off
spool ${DIR_TMP}/coleta_job.txt
select substr(count(*),1) FROM dba_objects o, dba_datapump_jobs j
WHERE o.owner=j.owner_name AND o.object_name=j.job_name
and o.owner=UPPER('${USER_EXPORT}') and j.state='NOT RUNNING';
spool off;
quit
EOF

       if [ $? -eq 0 ] && [ -s "$DIR_TMP/coleta_job.txt" ]; then
              DISPLAY "Função COLETA_JOB....: OK"
              COLETA_JOB_RESULT=`cat ${DIR_TMP}/coleta_job.txt`
       else
              DISPLAY "Função COLETA_JOB....: ERRO"
              DISPLAY "Falha na conexão com o banco de dados."
              echo "Falha na conexão com o banco de dados."
              exit 2
       fi
}

# Executa funcao COLETA_JOB
COLETA_JOB

if [ "${COLETA_JOB_RESULT}" -gt 0 ]; then
       DISPLAY "Realizado limpeza das tabelas orfãs de exportação, do user ${USER_EXPORT}."
       KILL_DATAPUMPS
       COLETA_JOB
fi

# COleta o resultado e envia para o monitoramento
if [ "${COLETA_JOB_RESULT}" -eq "0" ]; then
       $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Coleta_Job_Backup -s $T_Host -o 0
       DISPLAY "Não há tabelas orfãs de exportação, do user ${USER_EXPORT}."
elif [ "${COLETA_JOB_RESULT}" -ge "50" ]; then
       $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Coleta_Job_Backup -s $T_Host -o 2
else
# qualquer valor entre 1 e 49
       $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Coleta_Job_Backup -s $T_Host -o 1
fi

DISPLAY "==============================="
DISPLAY "==============================="

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
where owner not in (select owner from ${USER_EXPORT}.exclude_owner)
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

  EVENTO "Erro na Geracao da Lista de Usuarios do Backup via DATAPUMP" 2 ${ARQ_LOG_GERAL}

fi
}

CAPTURA_SCN(){
#Funcao para capturar scn para gerar backup consistente
${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} 2>&1 <<EOF
whenever sqlerror exit sql.sqlcode ;
set tab off
set pagesize 0
set linesize 80
set feedback off
set termout off
spool ${SCN_ATUAL}
select trim(to_char(current_scn)) from v\$database;
spool off;
quit
EOF

if [ "$?" = "0" ]
then
  DISPLAY "Status da Captura do SCN do Banco..: OK"
  DISPLAY "==============================="
  DISPLAY "==============================="
else
  DISPLAY "Status da Captura do SCN do Banco..: ERRO"
  ERROR_COUNT=`expr $ERROR_COUNT + 1`
  EVENTO "Erro no SELECT do SCN do Banco de Dados" 2 ${ARQ_LOG_GERAL}

fi

}

EXPORT_OWNER(){
# Função para backup dos schemas quando informado o tipo de backup owner na chamada do script.

GERA_OWNER

# Caso o banco de dados seja em portugues, altera temporariamente a lingaugem do SO para gerar logfile em ingles.
if [ ${ENGLISH} == "N" ]; then
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
fi

for USUARIO in `cat ${ARQ_OWNER}`
do

       #Captura SCN da base de dados
       CAPTURA_SCN
       SCN=`cat ${SCN_ATUAL}`
       ARQ_DATE=`date +%Y%m%d%H`
       ARQ_LOG=${INSTANCE}.${USUARIO}.`date +%Y%m%d%H`.log
       ARQ_DMP=${INSTANCE}.${USUARIO}%U.`date +%Y%m%d%H`.dmp

       DISPLAY "###############################"
       DISPLAY "Iniciando expdp schema.............: ${USUARIO}"

       expdp userid=${USER_EXPORT}/${USER_EXPORT_PASSWORD}@$INSTANCE DIRECTORY=${DIRECTORY_ORACLE} FLASHBACK_SCN=$SCN SCHEMAS='\"'${USUARIO}'\"' DUMPFILE=${ARQ_DMP} logfile=${ARQ_LOG} filesize=${FILESIZE} exclude=statistics 1>>/dev/null 2>>/dev/null

       #Verifica se o backup foi executado com sucesso
       if [ -e "${DIR_DMP}/logico/${ARQ_LOG}" ]; then
              if grep -q -e "Export terminated unsuccessfully" -e "ORA-" -e "error" -e "EXP-" "${DIR_DMP}/logico/${ARQ_LOG}"; then
                     DISPLAY "Finalizando expdp schema ${USUARIO}.............: ERRO"
                     mv ${DIR_DMP}/logico/${ARQ_LOG} ${DIR_LOG}/${ARQ_LOG}.erro
                     DISPLAY "Falha no expdp do schema ${USUARIO}, para mais detalhes verifique: ${DIR_LOG}/${ARQ_LOG}.erro"
                     ERROR_COUNT=`expr $ERROR_COUNT + 1`
              else
                     mv ${DIR_DMP}/logico/${ARQ_LOG} ${DIR_LOG}/${ARQ_LOG}.ok
                     DISPLAY "Finalizando expdp schema ${USUARIO}.............: OK"
                     DISPLAY "Log Execucao..................: ${DIR_LOG}/${ARQ_LOG}.ok"
              fi
       else
              ERROR_COUNT=`expr $ERROR_COUNT + 1`
              DISPLAY "Arquivo "${DIR_DMP}/logico/${ARQ_LOG}" não encontrado. Falha na exportação do schema ${USUARIO}"
       fi

       COMPACT_DUMPS
done
}

COMPACT_DUMPS(){

       DISPLAY "==============================="
       DISPLAY "==============================="
       DISPLAY "==== Compactando arquivos ====="
       DISPLAY "==============================="
       DISPLAY "==============================="

       gzip ${DIR_DMP}/logico/*.dmp

       #Verifica se a compactacao dos dumps foi efetuada com sucesso
       if [[ "$?" = "0" && ${STATUS} = "0" ]]
       then
              DISPLAY "Status Compactacao...............: OK "
       else
              STATUS=3
              DISPLAY "Status Compactacao...............: ERRO "
       fi

       DISPLAY "==============================="
       DISPLAY "==============================="

}

COPIA_REMOTA(){
#Função para copia remota dos arquivos de backup
       if [ ${REMOTE_MODE} = "S" ]; then
              DISPLAY "Iniciando copia remota....."

              #valida se o disco já esta montado antes de montar
              if ! mount | grep -q "$REMOTE_STRING"; then
                     mount $REMOTE_STRING

                     if [ "$?" = "0" ]; then
                            DISPLAY "Montagem unidade remota.....OK"
                     else
                            DISPLAY "Montagem unidade remota.....ERRO"
                            STATUS=2
                            RETENCAO_BACKUP
                            return 1
                     fi
              fi

              DISPLAY "Iniciando copia dos arquivos....."
              DISPLAY ${DIR_DMP}/logico/*${ARQ_DATE}.dmp.gz $REMOTE_STRING/$PATH_REMOTO/logico
              #copia dos arquivos locais para storage remoto
              cp ${DIR_DMP}/logico/*${ARQ_DATE}.dmp.gz $REMOTE_STRING/$PATH_REMOTO/logico/

              #valida se deu tudo certo.
              if [ "$?" = "0" ]; then
                     DISPLAY "Finalizando copia dos arquivos....."
                     DISPLAY "Status Copia Remota..........: OK "
              else
                     DISPLAY "Finalizando copia dos arquivos....."
                     DISPLAY "Status Copia Remota..........: ERRO "
                     STATUS=2
              fi


              #valida se o cliente possui uma copia remota extra, caso sim copia os arquivos de bkp
              if [ ${REMOTE_EXTRA} = "S" ]; then
                     if ! mount | grep -q "$REMOTE_STRING2"; then
                            mount $REMOTE_STRING2

                            if [ "$?" = "0" ]; then
                                   DISPLAY "Montagem unidade remota 2.....OK"
                            else
                                   DISPLAY "Montagem unidade remota 2.....ERRO"
                                   STATUS=2
                                   RETENCAO_BACKUP
                                   return 1
                            fi
                     fi

                     DISPLAY "Inicianco segunda copia dos arquivos....."
                     DISPLAY ${DIR_DMP}/logico/*${ARQ_DATE}.dmp.gz $REMOTE_STRING2/$PATH_REMOTO2/logico
                     #copia dos arquivos locais para storage remoto
                     cp ${DIR_DMP}/logico/*${ARQ_DATE}.dmp.gz $REMOTE_STRING2/$PATH_REMOTO2/logico/

                     #valida se deu tudo certo.
                     if [ "$?" = "0" ]; then
                            DISPLAY "Finalizando segunda copia dos arquivos....."
                            DISPLAY "Status Copia Remota 2..........: OK "
                     else
                            DISPLAY "Finalizando segunda copia dos arquivos....."
                            DISPLAY "Status Copia Remota 2..........: ERRO "
                            STATUS=2
                     fi
              fi

       fi

       DISPLAY "==============================="
       DISPLAY "==============================="


       RETENCAO_BACKUP
}

RETENCAO_BACKUP(){
#função para retenção dos backups locais, backups remotos e arquivos de log.
       DISPLAY "Iniciando retenção dos backups locais....."
       #limpa arquivos de log
       find ${DIR_LOG}/* -mtime +${RETENCAO_LOG} -print -exec rm -f {} \; > /dev/null 2>&1

       #limpeza dos arquivos de bkp
       find ${DIR_DMP}/logico/*.dmp.gz -mtime +${RETENCAO_DMP} -print -exec rm -f {} \; > /dev/null 2>&1
       DISPLAY "Finalizando retenção dos backups locais....."

       #limpeza dos arquivos de bkp remoto
       if [ ${REMOTE_MODE} = "S" ]; then
              DISPLAY "Iniciando retenção dos backups remotos....."
              find $REMOTE_STRING/$PATH_REMOTO/logico/*.dmp.gz -mtime +${RETENCAO_DMP_REMOTO} -print -exec rm -f {} \; > /dev/null 2>&1
              DISPLAY "Finalizando retenção dos backups remotos....."

              DISPLAY "Desmontando unidade de rede...."
              umount $REMOTE_STRING
       fi

       #limpeza dos arquivos de bkp do segundo storage (caso possua)
       if [ ${REMOTE_EXTRA} = "S" ]; then
              DISPLAY "Iniciando retenção dos backups remotos 2....."
              find $REMOTE_STRING2/$PATH_REMOTO2/logico/*.dmp.gz -mtime +${RETENCAO_DMP_REMOTO2} -print -exec rm -f {} \; > /dev/null 2>&1
              DISPLAY "Finalizando retenção dos backups remotos 2....."

              DISPLAY "Desmontando unidade de rede 2...."
              umount $REMOTE_STRING2
       fi

       DISPLAY "==============================="
       DISPLAY "==============================="

       FINALIZA
}

### Função para expdp FULL, quanto utilizado o tipo FULL na chamada do script.
EXPORT_FULL(){

# Caso o banco de dados seja em portugues, altera temporariamente a lingaugem do SO para gerar logfile em ingles.
if [ ${ENGLISH} == "N" ]; then
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
fi

CAPTURA_SCN
SCN=`cat ${SCN_ATUAL}`
ARQ_LOG=${INSTANCE}.FULL.`date +%Y%m%d%H`.log
ARQ_DMP=${INSTANCE}.FULL%U.`date +%Y%m%d%H`.dmp

expdp userid=${USER_EXPORT}/${USER_EXPORT_PASSWORD}@$INSTANCE DIRECTORY=${DIRECTORY_ORACLE} FLASHBACK_SCN=$SCN FULL=Y DUMPFILE=${ARQ_DMP} logfile=${ARQ_LOG} filesize=${FILESIZE} 1>>/dev/null 2>>/dev/null

       #Verifica se o backup foi executado com sucesso
       if [ -e "${DIR_DMP}/logico/${ARQ_LOG}" ]; then
              if grep -q -e "Export terminated unsuccessfully" -e "ORA-" -e "error" -e "EXP-" "${DIR_DMP}/logico/${ARQ_LOG}"; then
                     DISPLAY "Finalizando expdp FULL.............: ERRO"
                     ERROR_COUNT=1
                     mv ${DIR_DMP}/logico/${ARQ_LOG} ${DIR_LOG}/${ARQ_LOG}.erro
                     DISPLAY "Falha no expdp FULL, para mais detalhes verifique: ${DIR_LOG}/${ARQ_LOG}.erro"
              else
                     mv ${DIR_DMP}/logico/${ARQ_LOG} ${DIR_LOG}/${ARQ_LOG}.ok
                     DISPLAY "Finalizando expdp FULL.............: OK"
                     DISPLAY "Log Execucao..................: ${DIR_LOG}/${ARQ_LOG}.ok"
                     ERROR_COUNT=0
              fi
       else
              ERROR_COUNT=1
              DISPLAY "Arquivo "${DIR_DMP}/logico/${ARQ_LOG}" não encontrado. Falha na exportação."
       fi

       DISPLAY "==============================="
       DISPLAY "==============================="

       COMPACT_DUMPS
}

# Função para encaminhar e-mail ao cliente. Utilizar o procedimento "Configurar e-mail no linux" do onenote para configurar o sendmail.
SEND_MAIL(){

cat $ARQ_LOG_GERAL |grep `date +%d/%m/%Y` |grep Status > ${DIR_DMP}/logico/email.log
/bin/mail -s "Backup Logico: $STATUS_GERAL" "$EMAIL_AVISO" < ${DIR_DMP}/logico/email.log 
sleep 5;
rm -rf ${DIR_DMP}/logico/email.log
}

FINALIZA(){
#função para fazer as considerações finais no arquivo de log e envio ao monitoramento (caso for monitorado)

       if [ ${ERROR_COUNT} -gt 0 ] && [ "${TIPO}" = "FULL" ]; then
              STATUS_GERAL="ERRO Expdp Full"
              STATUS_MOM=4
       elif [ ${ERROR_COUNT} -gt 0 ]; then
              STATUS_GERAL="ERRO Expdp"
              STATUS_MOM=1
       elif [ ${STATUS} = 2 ]; then
              STATUS_GERAL="ERRO Copia Remota"
              STATUS_MOM=${STATUS}
       elif [ ${STATUS} = 3 ]; then
              STATUS_GERAL="ERRO Compactacao"
              STATUS_MOM=${STATUS}
       else
              STATUS_GERAL="OK"
              STATUS_MOM=0
       fi

       FIM_BACKUP="`date '+%d/%m/%Y %T'`"

       DISPLAY "==============================="
       DISPLAY "==============================="
       DISPLAY "====R E S U M O   G E R A L===="
       DISPLAY "Inicio do Backup..............: ${INICIO_BACKUP}"
       DISPLAY "Fim do Backup.................: ${FIM_BACKUP}"
       if [ "${TIPO}" = "OWNER" ]; then
       DISPLAY "QTD owners com Erro...............: ${ERROR_COUNT}"
       fi
       DISPLAY "Log da Execucao do Backup.....: ${ARQ_LOG_GERAL}"
       DISPLAY "Status do Backup..............: ${STATUS_GERAL}"
       DISPLAY "==============================="
       DISPLAY "==============================="

       if (( STATUS == 0 && ERROR_COUNT <= 0 )); then
              EVENTO "Sucesso na execucao do backup OWNER via DATAPUMP" 0
       else
              EVENTO "ERRO na execucao do backup OWNER via DATAPUMP" 2 ${ARQ_LOG_GERAL}
       fi

       if [ "${TITAN}" == "S" ];  then
              DISPLAY " Enviando resultado ao monitoramento "
              $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Backup_Logico -s $T_Host -o $STATUS_MOM
              rm -rf ${DIR_TMP}/logico_${INSTANCE}.pid
       fi

       if [ ${EMAIL} == "S" ]; then
              SEND_MAIL
       fi

       rm -rf ${DIR_TMP}/coleta_job.txt
}

# Valida qual o tipo de backup
if [ "${TIPO}" = "OWNER" ]; then
       EXPORT_OWNER
elif [ "${TIPO}" = "FULL" ];then
       EXPORT_FULL
else
       DISPLAY "Parametro Invalido..........: TIPO=${TIPO}"
       exit 3;
fi

#executa a função de copia remota após os backups e compactação.
COPIA_REMOTA
