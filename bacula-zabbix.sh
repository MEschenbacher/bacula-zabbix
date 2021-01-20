#!/usr/bin/env bash

# Import configuration file
source ${BACULA_ZABBIX_CONFIG:-/etc/bacula/bacula-zabbix.conf}

clientName=${clientName:-Client.Name}

# Get Job ID from parameter
baculaJobId="$1"
if [ -z "$baculaJobId" ] ; then exit 3 ; fi

# Test if zabbix_sender exists and execute permission is granted, if not, exit
if [ ! -x "$zabbixSender" ] ; then exit 5 ; fi

# Chose which database command to use
case "$baculaDbSgdb" in
  P) sql="PGPASSWORD=$baculaDbPass $psqlBinary -h$baculaDbAddr -p$baculaDbPort -U$baculaDbUser -d$baculaDbName -c" ;;
  M) sql="$mysqlBinary -NB -h$baculaDbAddr -P$baculaDbPort -u$baculaDbUser -p$baculaDbPass -D$baculaDbName -e" ;;
  *) exit 7 ;;
esac

# Get Job type from database, then if it is a backup job, proceed, if not, exit
baculaJobType=$($sql "select Type from Job where JobId=$baculaJobId;" 2>/dev/null)
if [ "$baculaJobType" != "B" ] ; then exit 9 ; fi

# Get Job level from database and classify it as Full, Differential, or Incremental
baculaJobLevel=$($sql "select Level from Job where JobId=$baculaJobId;" 2>/dev/null)
case $baculaJobLevel in
  'F') level='full' ;;
  'D') level='diff' ;;
  'I') level='incr' ;;
  *)   exit 11 ;;
esac

# Get Job exit status from database and classify it as OK, OK with warnings, or Fail
baculaJobStatus=$($sql "select JobStatus from Job where JobId=$baculaJobId;" 2>/dev/null)
if [ -z "$baculaJobStatus" ] ; then exit 13 ; fi
case "$baculaJobStatus" in
  "T") status=0 ;;
  "W") status=1 ;;
  *)   status=2 ;;
esac

# Get client's name from database
baculaClientName=$($sql "select $clientName from Client,Job where Job.ClientId=Client.ClientId and Job.JobId=$baculaJobId;" 2>/dev/null)
if [ -z "$baculaClientName" ] ; then exit 15 ; fi

# Initialize return as zero
ret=0

# send status message to zabbix server
message=$(cat)
if ! $zabbixSender -z "$zabbixSrvAddr" -p "$zabbixSrvPort" -s "$baculaClientName" -k "bacula.$level.job.message" -o "$message" >/dev/null 2>&1; then
	ret=$((ret+1))
fi

# Send Job exit status to Zabbix server
if ! $zabbixSender -z "$zabbixSrvAddr" -p "$zabbixSrvPort" -s "$baculaClientName" -k "bacula.$level.job.status" -o "$status" >/dev/null 2>&1; then
	ret=$((ret+2))
fi

# Get from database the number of bytes transferred by the Job and send it to Zabbix server
baculaJobBytes=$($sql "select JobBytes from Job where JobId=$baculaJobId;" 2>/dev/null)
if ! $zabbixSender -z "$zabbixSrvAddr" -p "$zabbixSrvPort" -s "$baculaClientName" -k "bacula.$level.job.bytes" -o "$baculaJobBytes" >/dev/null 2>&1; then
	ret=$((ret+4))
fi

# Get from database the number of files transferred by the Job and send it to Zabbix server
baculaJobFiles=$($sql "select JobFiles from Job where JobId=$baculaJobId;" 2>/dev/null)
if ! $zabbixSender -z "$zabbixSrvAddr" -p "$zabbixSrvPort" -s "$baculaClientName" -k "bacula.$level.job.files" -o "$baculaJobFiles" >/dev/null 2>&1; then
	ret=$((ret+8))
fi

# Get from database the time spent by the Job and send it to Zabbix server
baculaJobTime=$($sql "select timestampdiff(second,StartTime,EndTime) from Job where JobId=$baculaJobId;" 2>/dev/null)
if ! $zabbixSender -z "$zabbixSrvAddr" -p "$zabbixSrvPort" -s "$baculaClientName" -k "bacula.$level.job.time" -o "$baculaJobTime" >/dev/null 2>&1; then
	ret=$((ret+16))
fi

# Get Job speed from database and send it to Zabbix server
baculaJobSpeed=$($sql "select round(JobBytes/timestampdiff(second,StartTime,EndTime)/1024,2) from Job where JobId=$baculaJobId;" 2>/dev/null)
if ! $zabbixSender -z "$zabbixSrvAddr" -p "$zabbixSrvPort" -s "$baculaClientName" -k "bacula.$level.job.speed" -o "$baculaJobSpeed" >/dev/null 2>&1; then
	ret=$((ret+32))
fi

# Get Job compression rate from database and send it to Zabbix server
baculaJobCompr=$($sql "select round(1-JobBytes/ReadBytes,2) from Job where JobId=$baculaJobId;" 2>/dev/null)
if ! $zabbixSender -z "$zabbixSrvAddr" -p "$zabbixSrvPort" -s "$baculaClientName" -k "bacula.$level.job.compr" -o "$baculaJobCompr" >/dev/null 2>&1; then
	ret=$((ret+64))
fi

# Exit with ret status
exit $ret
