set -x
#!/bin/ksh

source /etc/migra.conf
#Testando se a rotina não esta rodando
if ls ${DIR_TMP}/fisico.pid 1> /dev/null 2>&1; then
    echo "ROTINA JA ESTA EM EXECUCAO"
    if [ "${TITAN}" == "S" ];  then
        $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Backup_Fisico -s $T_Host -o 3
    fi

else
if [ "${TITAN}" == "S" ];  then
        touch ${DIR_TMP}/fisico.pid
fi

DISPLAY(){
echo "[`date '+%d/%m/%Y %T'`] $*" >> $ARQ_LOG_GERAL
}


DISPLAY "--> Instancia.....: ${INSTANCE}"
DISPLAY "==============================="
DISPLAY "==============================="
DISPLAY "--> Tipo do Bkp.....: HOTBACKUP"
DISPLAY "==============================="
DISPLAY "==============================="
DISPLAY " Inicio do Backup fisico "
DISPLAY "==============================="
DISPLAY "==============================="

EVENTO(){
# Funcao que efetua o envio de evento por e-mail

  NR_PARAMETRO=`echo $#`
  DESCRICAO_MENSAGEM="$1"
  SEVERIDADE_MENSAGEM=$2
  ANEXO_MENSAGEM=$3
}



DISPLAY "==============================="
DISPLAY " Gerando a lista de Tablespace "
DISPLAY "==============================="

${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} <<EOF
set head off
set pages 0
set lines 200
set feedback off
alter system switch logfile;
select 'alter tablespace '||tablespace_name||' begin backup;' from dba_tablespaces where CONTENTS!='TEMPORARY';
spool $DIR_TMP/begin_backup.sql
/
spool off
exit
EOF

${ORACLE_HOME}/bin/sqlplus -s "/ as sysdba" <<EOF
@$DIR_TMP/begin_backup.sql
exit
EOF
if [ "$?" = "0" ]
then
  DISPLAY "Status do Begin Backup: OK"
else
  DISPLAY "Status da Begin Backup: ERRO"
  LVL_ERRO=5
fi


DISPLAY "==============================="
DISPLAY "      Copiando Datafiles       "
DISPLAY "==============================="

${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} <<EOF
set head off
set pages 0
set lines 200
set feedback off
select 'gzip -c '||file_name||' > $DIR_DMP/fisico/'|| substr(file_name, instr(file_name, '/', -1, 1) +1) ||'.gz '  from dba_data_files;
spool $DIR_TMP/copia_backup.sh
/
spool off
exit
EOF
sh $DIR_TMP/copia_backup.sh > $DIR_TMP/copia.log
if [ "$?" = "0" ]
then
  DISPLAY "Status do Backup: OK"
else
  DISPLAY "Status do Backup: ERRO"
  LVL_ERRO=1
fi

DISPLAY "==============================="
DISPLAY "     Finalizando Datafiles     "
DISPLAY "==============================="


${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} <<EOF
set head off
set pages 0
set lines 200
set feedback off
alter database backup controlfile to '$DIR_DMP/fisico/ctlfile_backup_$1.ctl' reuse;
select 'alter tablespace '||tablespace_name||' end backup;' from dba_tablespaces where CONTENTS!='TEMPORARY';
spool $DIR_TMP/end_backup.sql
/
spool off
exit
EOF

${ORACLE_HOME}/bin/sqlplus -s "/ as sysdba" <<EOF
@$DIR_TMP/end_backup.sql
exit
EOF

if [ "$?" = "0" ]
then
  DISPLAY "Status do END Backup: OK"
else
  DISPLAY "Status da END Backup: ERRO"
  LVL_ERRO=6
fi

DISPLAY "==============================="
DISPLAY "    Testando o ControlFile     "
DISPLAY "==============================="

export result=`find $DIR_DMP/fisico/*ctl -mtime -1`
if [ "${result}" == "${DIR_DMP}/fisico/ctlfile_backup_$1.ctl" ]; then
        export STATUS_GERAL=OK
else
        export STATUS_GERAL=ERRO
	LVL_ERRO=7

fi
if [ "${REMOTE_MODE}" == "S" ];  then
        mount ${REMOTE_STRING}
        DISPLAY "==============================="
        DISPLAY "==============================="
        DISPLAY "====== Copiando via Rede ======"

                cp $DIR_DMP/fisico/* $REMOTE_STRING/$PATH_REMOTO/fisico/.
		if [ "$?" = "0" ]
		then
		  DISPLAY "Status da copia de rede: OK"
		else
		  DISPLAY "Status da copia de rede: ERRO"
		  LVL_ERRO=2
		fi

                umount ${REMOTE_STRING}
        DISPLAY "==============================="
        DISPLAY "     Copiado com sucesso       "
        DISPLAY "==============================="

else
        DISPLAY "==============================="
        DISPLAY "   Nao esta configurado a      "
        DISPLAY "  copia remota para este BKP   "
        DISPLAY "==============================="
fi
DISPLAY "==============================="
DISPLAY "==============================="
DISPLAY "     Fim do Backup fisico      "
DISPLAY "==============================="
DISPLAY "==============================="
DISPLAY "  Efetuando limpeza na rotina  "
rm -f $DIR_TMP/end_backup.sql
rm -f $DIR_TMP/copia_backup.sh
rm -f $DIR_TMP/begin_backup.sql
rm -f $DIR_TMP/remove.sh
DISPLAY "==============================="

if [ "${TITAN}" == "S" ];  then
        if [ "${STATUS_GERAL}" == "OK" ]; then
                DISPLAY " Enviando sucesso ao monitoramento "
                $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Backup_Fisico -s $T_Host -o 0
        else
                DISPLAY " Enviando ERRO ao monitoramento "
                $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Backup_Fisico -s $T_Host -o 1
        fi
fi
rm -rf ${DIR_TMP}/fisico.pid
fi

