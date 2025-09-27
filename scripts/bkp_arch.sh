#!/bin/ksh
#!/bin/bash
set -x
source /etc/migra.conf
#Testando se a rotina nãesta rodando
if ls ${DIR_TMP}/bkp.pid 1> /dev/null 2>&1; then
    echo "JA EXISTE UMA ROTINA EM EXECUCAO"
	if [ "${TITAN}" == "S" ];  then
          $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Backup_Arch -s $T_Host -o 4
        fi
else

if ls ${DIR_TMP}/arch.pid 1> /dev/null 2>&1; then
    echo "ROTINA JA ESTA EM EXECUCAO"
    if [ "${TITAN}" == "S" ];  then
        $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Backup_Arch -s $T_Host -o 3
    fi

else

if [ "${TITAN}" == "S" ];  then
	touch ${DIR_TMP}/arch.pid
fi


${ORACLE_HOME}/bin/sqlplus -s ${USER_EXPORT}/$USER_EXPORT_PASSWORD@${INSTANCE} <<EOF
alter system switch logfile;
exit
EOF

export ORACLE_SID=${INSTANCE}
${ORACLE_HOME}/bin/sqlplus -s "/as sysdba" <<EOF
spool ${DIR_TMP}/origem_archive.txt
archive log list;
spool off
exit
EOF

if [ "${ENGLISH}" == "S" ]; then
        ORIGEM=`cat ${DIR_TMP}/origem_archive.txt |grep "Archive destination" |awk -F 'Archive destination            ' '{print $2}'`
else
        ORIGEM=`cat ${DIR_TMP}/origem_archive.txt |grep "Destino de arquivamento" |awk -F 'Destino de arquivamento            ' '{print $2}'`
fi


if [ "${REMOTE_MODE}" == "S" ]; then
  if grep -qs ${REMOTE_STRING} /proc/mounts; then
   echo "unidade ja montada"
  else 
   mount ${REMOTE_STRING}
  fi
fi


# Cria lista de arquivos que vao fazer backup
cd ${ORIGEM}
     for FILE in ${EXTENTION} ; do
        gzip -c ${FILE} > "${DIR_DMP}/arch/${FILE}.gz"
if [ "${COMPACT_ORIGEM}" == "S" ]; then
        mv ${FILE} ${FILE}.bkp
	gzip ${FILE}.bkp
else
	mv ${FILE} ${FILE}.bkp
fi
        if [ "${REMOTE_MODE}" == "S" ]; then
        #mount ${REMOTE_STRING}
            cp ${DIR_DMP}/arch/${FILE}.gz ${REMOTE_STRING}/$PATH_REMOTO/arch/.
        fi
        if [ "${CLOUD}" == "S" ]; then
           /usr/bin/azcopy --source ${DIR_DMP}/arch/${FILE}.gz --exclude-older --destination ${CLOUDPATH}/arch/${FILE}.gz --dest-key "XyuoIvYP4vSEkf/BkB7mEMyjk6AKCnm72JjYcOZks+pVsmPyseStp6GEoecvkEgrWAR/23lONoVeUI5qIMw8fw==" > $DIR_LOG/arch_cloud.log
	fi
    done

###Remoção dos backups
find ${DIR_DMP}/arch/ -name "*.gz" -type f -mtime +${RETENTION_DEST} -exec rm -f {} \;
find ${ORIGEM} -name "*.bkp*" -type f -mtime +${RETENTION_ORI} -exec rm -f {} \;
   if [ "${REMOTE_MODE}" == "S" ]; then
        find ${REMOTE_STRING}/$PATH_REMOTO/arch -name "*.gz" -type f -mtime +${RETENTION_DEST} -exec rm -f {} \;
        umount $REMOTE_STRING
   fi

if [ "${TITAN}" == "S" ];  then
        $PATH_TITAN/$SENDER -c $T_CONF -z $T_IP -k Backup_Arch -s $T_Host -o 0
fi

rm -rf ${DIR_TMP}/arch.pid
fi
fi

