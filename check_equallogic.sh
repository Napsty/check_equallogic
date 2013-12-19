#!/bin/bash 
################################################################################
# Script:       check_equallogic                                               #
# Author:       Claudio Kuenzler www.claudiokuenzler.com                       #
# Purpose:      Monitor Dell Equallogic with Nagios                            #
# Description:  Checks Dell Equallogic via SNMP.                               #
#               Can be used to query status and performance info               #
# Tested on:    Check the following web page for compatibility matrix:         #
#               www.claudiokuenzler.com/nagios-plugins/check_equallogic.php    #
# License:      GPLv2                                                          #
# History:                                                                     #
# 20091109 Started Script programming checks:                                  #
#          health, disk, raid, uptime, ps, info                                #
# 20091112 Added ethif, conn                                                   #
# 20091118 Added diskusage                                                     #
# 20091119 Bugfix on Outputs (removed Pipes)                                   #
# 20091121 Public Release                                                      #
# 20091204 Bugfix (removed IP addresses)                                       #
# 20091206 Bugfix (removed SNMP community names)                               #
# 20091222 Fixed raid, ps, health and diskusage checks when multiple           #
#          member devices exists. Mathias Sundman <mathias@openvpn.se>         #
# 20100112 Successful tests on PS5000XV - thanks to Scott Sawin                #
# 20100209 Compatibility matrix now on website (see Tested on above)           #
# 20100416 Beta Testing for rewritten ethif check                              #
# 20100420 Corrected ethif output, finished new ethif check                    #
# 20100526 Using proper order of snmpwalk command, thanks Roland Ripoll        #
# 20100531 Added perfdata for diskusage and connections, thx to Benoit         #
# 20100630 Corrected perfdata output (+added thresholds), thx Christian        #
# 20100809 Fixed conn type -> total of all eql members of group                #
# 20101026 /bin/sh back to /bin/bash (Ubuntu problems with /bin/dash)          #
# 20101026 Bugfix snmpwalk (vqe instead of vq), thanks Fabio Panigatti         #
# 20101102 Added fan                                                           #
# 20101202 Added volumes (checks utilization of  all volumes)                  #
# 20110315 Bugfix in fan warning, diskusage output changed                     #
# 20110323 Mysteriously disappeared temp check type added again                #
# 20110328 Beta Testing for etherrors check by Martin Conzelmann               #
# 20110404 Added thresholds to etherrors check by Martin Conzelmann            #
# 20110404 Bugfix in volumes check                                             #
# 20110407 New temp check - more information in output. M. Conzelmann          #
# 20110725 New disk check by Amir Shakoor (Bugfixes by Claudio Kuenzler)       #
# 20110804 New poolusage check by Chris Funderburg and Markus Becker           #
# 20110808 New vol check - checks single volume for utilization                #
# 20111013 Bugfix in vol check for similar vol names by Matt White             #
# 20111031 Bugfix in ethif check for int response by Francois Borlet           #
# 20120104 Bugfix in temp check if only one controller available               #
# 20120104 Bugfix in info check if only one controller available               #
# 20120123 Bugfix in volumes check                                             #
# 20120125 Added perfdata in volumes check, volume names now w/o quotes        #
# 20120319 Added poolconn check by Erwin Bleeker                               #
# 20120330 Rewrite of poolusage (orig is now: memberusage) by E. Bleeker       #
# 20120405 Bugfix in poolusage to show result without thresholds               #
# 20120430 Added snapshots type by Roland Penner                               #
# 20120503 Rewrite of info check (Fix for multiple members, FW Check)          #
# 20120815 Added percentage of raid rebuild when raid reconstructing           #
# 20120821 Minor bugfix in vol/volumes check (added space in perfdata)         #
# 20120911 Added percentage of raid rebuild when raid expanding                #
# 20120913 Bugfix in percentage output in raid check                           #
# 20121204 Added percentage of raid rebuild when raid verifying                #
# 20121204 Changed raid percentage output when multiple members around         #
# 20121228 ps type now also checks for failed power supply fans                #
# 20130728 Added copy to spare raid status by Peter Lieven                     #
# 20131024 Bugfix in temp check (Backplane_sensor_0 was not shown)             #
# 20131025 Optical cleanup                                                     #
# 20131122 Bugfix in vol check when volumes spread across members              #
# 20131219 Bugfix in poolusage check when a pool was not used (0 size)         #
################################################################################
# Usage: ./check_equallogic -H host -C community -t type [-v volume] [-w warning] [-c critical]
################################################################################
help="check_equallogic (c) 2009-2013 Claudio Kuenzler (published under GPL licence)\n
Usage: ./check_equallogic -H host -C community -t type [-v volume] [-w warning] [-c critical]\n
Options:\n-H Hostname\n-C SNMP-Community name (at least read-only)\n-t Type to check, see list below\n-v Name of volume to check\n-w Warning Threshold\n-c Critical Threshold\n
Requirements: snmpwalk, awk, grep, wc\n
types:\nconn -> Checks total number of ISCSI connections (if no thresholds are given, outputs information)
disk -> Checks Status of all disks
diskusage -> Checks the actual usage of the defined raid (if no thresholds are given, outputs information)
etherrors -> Checks ethernet interfaces for ethernet packet errors (thresholds possible)
ethif -> Checks ethernet interfaces (if no thresholds are given, outputs information)
fan -> Status of Fans
health -> Overall health status of Equallogic device
info -> Shows some Information and checks for same firmware version
memberusage -> Shows disk utilisation of all members of the same group (if no thresholds are given, outputs information)
poolconn -> Check highest number of ISCSI connections per pool (if no thresholds are given, outputs information)
poolusage -> Checks utilization of pools (if no thresholds are given, outputs information)
ps -> Checks Power Supply/Supplies
raid -> Checks RAID status
snapshots -> Checks Snapshot Reserve status (warning level is taken from the equallogic volume config, critical level can be set with -c )
temp -> Checks Temperature sensors
uptime -> Shows uptime
vol -> Checks a single volume, must be used with -v option (if no thresholds are given, outputs information)
volumes -> Checks utilization of all ISCSI volumes (if no thresholds are given, outputs information)"

STATE_OK=0              # define the exit code if status is OK
STATE_WARNING=1         # define the exit code if status is Warning
STATE_CRITICAL=2        # define the exit code if status is Critical
STATE_UNKNOWN=3         # define the exit code if status is Unknown
PATH=/usr/local/bin:/usr/bin:/bin # Set path

for cmd in snmpwalk awk grep wc [
do
 if ! `which ${cmd} 1>/dev/null`
 then
 echo "UNKNOWN: ${cmd} does not exist, please check if command exists and PATH is correct"
 exit ${STATE_UNKNOWN}
 fi
done

# Check for people who need help - aren't we all nice ;-)
#########################################################################
if [ "${1}" = "--help" -o "${#}" = "0" ];
       then
       echo -e "${help}";
       exit 1;
fi

# Get user-given variables
#########################################################################
while getopts "H:C:t:v:w:c:" Input;
do
       case ${Input} in
       H)      host=${OPTARG};;
       C)      community=${OPTARG};;
       t)      type=${OPTARG};;
       v)      volume=${OPTARG};;
       w)      warning=${OPTARG};;
       c)      critical=${OPTARG};;
       *)      echo "Wrong option given. Please use options -H for host, -C for SNMP-Community, -t for type, -w for warning and -c for critical"
               exit 1
               ;;
       esac
done


# Check Different Types
#########################################################################
case ${type} in

# --- Health --- #
health)
healthstatus=$(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.5.1.1)

s_crit=0; s_warn=0; s_ok=0; s_unknown=0
for s in $healthstatus
  do
  if [ "$s" = "3" ]; then s_crit=$((s_crit + 1)); fi
  if [ "$s" = "2" ]; then s_warn=$((s_warn + 1)); fi
  if [ "$s" = "1" ]; then s_ok=$((s_ok + 1)); fi
  if [ "$s" = "0" ]; then s_unkown=$((s_unknown + 1)); fi
done

if [ $s_crit -gt 0 ]; then echo "OVERALL HEALTH CRITICAL"; exit ${STATE_CRITICAL}; fi
if [ $s_warn -gt 0 ]; then echo "OVERALL HEALTH WARNING"; exit ${STATE_WARNING}; fi
if [ $s_unknown -gt 0 ]; then echo "OVERALL HEALTH UNKNOWN"; exit ${STATE_UNKNOWN}; fi
if [ $s_ok -gt 0 ]; then echo "OVERALL HEALTH OK"; exit ${STATE_OK}; fi
;;

# --- temp --- #
temp)
#get names and temperatures
declare -a sensornames=($(snmpwalk -v 2c -O vqe -c ${community} ${host} .1.3.6.1.4.1.12740.2.1.6.1.2 | tr ' ' '_' | tr -d '"' ))
declare -a sensortemp=($(snmpwalk -v 2c -O vqe -c ${community} ${host} .1.3.6.1.4.1.12740.2.1.6.1.3 | awk -F : '{print $1}'))
declare -a sensortemp_min=($(snmpwalk -v 2c -O vqe -c ${community} ${host} .1.3.6.1.4.1.12740.2.1.6.1.8 | awk -F : '{print $1}'))
declare -a sensortemp_max=($(snmpwalk -v 2c -O vqe -c ${community} ${host} .1.3.6.1.4.1.12740.2.1.6.1.6 | awk -F : '{print $1}'))

# put this name, temp... together
c=0
for line in ${sensornames[@]}
  do
  if [ ${sensortemp[${c}]} -gt 0 ]
    then
    perfdata=$perfdata" ${sensornames[$c]}=${sensortemp[${c}]};${sensortemp_min[${c}]};${sensortemp_max[${c}]}"
    #Check if state is CRITICAL. Compare against MIN and MAX               
    if [ ${sensortemp[${c}]} -gt ${sensortemp_max[${c}]} ] || [ ${sensortemp[${c}]} -lt ${sensortemp_min[${c}]} ]
      then
      sensorfinalcrit[${c}]="${sensornames[$c]} => ${sensortemp[${c}]}"
    fi
  fi
  let c++
done

#Cut leading blank
perfdata=$(echo $perfdata | sed 's/^ //')
if [[ ${#sensorfinalcrit[*]} -gt 0 ]]
  then echo "CRITICAL Sensor: ${sensorfinalcrit[*]} | $perfdata"; exit ${STATE_CRITICAL}
elif [[ ${#sensorfinalwarn[*]} -gt 0 ]]
  then echo "WARNING Sensor: ${sensorfinalwarn[*]} | $perfdata"; exit ${STATE_WARNING}
elif [[ ${#sensorunknown[*]} -gt 0 ]]
  then echo "UNKNOWN Check Sensors, an unknown error occured | $perfdata"; exit ${STATE_UNKNOWN}
else echo "All Sensors OK | $perfdata"; exit ${STATE_OK}
fi
;; 

# --- diskold (old disk check) --- #
diskold)
diskstatusok=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.3.1.1.1.8 | grep 1 | wc -l)
diskstatusspare=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.3.1.1.1.8 | grep 2 | wc -l)
diskstatusfailed=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.3.1.1.1.8 | grep 3 | wc -l)
diskstatusoff=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.3.1.1.1.8 | grep 4 | wc -l)
diskstatusaltsig=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.3.1.1.1.8 | grep 5 | wc -l)
diskstatustoosmall=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.3.1.1.1.8 | grep 6 | wc -l)
diskstatushistfailures=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.3.1.1.1.8 | grep 7 | wc -l)
diskstatusunsupported=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.3.1.1.1.8 | grep 8 | wc -l)
if [ ${diskstatusfailed} -gt  0 ] || [ ${diskstatustoosmall} -gt 0 ] || [ ${diskstatushistfailures} -gt 0 ] || [ ${diskstatusunsupported} -gt 0 ]
  then disksumcritical=$(($diskstatusfailed + $diskstatustoosmall + $diskstatushistfailures + $diskstatusunsupported))
  echo "DISK CRITICAL ${disksumcritical} disk(s) in critical state"; exit ${STATE_CRITICAL}
elif [ ${diskstatusoff} -gt 0 ] || [ ${diskstatusaltsig} -gt 0 ]
  then disksumwarning=$(( ${diskstatusoff} + ${diskstatusaltsig} ))
  echo "DISK WARNING $disksumwarning disk(s) in warning state"; exit ${STATE_WARNING}
else echo "DISK OK ${diskstatusok} disks OK ${diskstatusspare} disks spare"; exit ${STATE_OK}
fi
;;

# --- disk --- #
disk)
diskresult=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.3.1.1.1.8)
diskstatusok=0
diskstatusspare=0
diskstatusfailed=0
diskstatusoff=0
diskstatusaltsig=0
diskstatustoosmall=0
diskstatushistfailures=0
diskstatusunsupported=0

for s in $diskresult
  do
  if [ $s = 1 ]; then diskstatusok=$((diskstatusok + 1)); fi
  if [ $s = 2 ]; then diskstatusspare=$((diskstatusspare + 1)); fi
  if [ $s = 3 ]; then diskstatusfailed=$((diskstatusfailed + 1)); fi
  if [ $s = 4 ]; then diskstatusoff=$((diskstatusoff + 1)); fi
  if [ $s = 5 ]; then diskstatusaltsig=$((diskstatusaltsig + 1)); fi
  if [ $s = 6 ]; then diskstatustoosmall=$((diskstatustoosmall + 1)); fi
  if [ $s = 7 ]; then diskstatushistfailures=$((diskstatushistfailures + 1)); fi
  if [ $s = 8 ]; then diskstatusunsupported=$((diskstatusunsupported + 1)); fi
done

if [ ${diskstatusfailed:0} -gt  0 ] || [ ${diskstatustoosmall:0} -gt 0 ] || [ ${diskstatushistfailures} -gt 0 ] || [ ${diskstatusunsupported} -gt 0 ]
  then disksumcritical=$(($diskstatusfailed + $diskstatustoosmall + $diskstatushistfailures + $diskstatusunsupported))
  echo "DISK CRITICAL ${disksumcritical} disk(s) in critical state"; exit ${STATE_CRITICAL}
elif [ ${diskstatusoff} -gt 0 ] || [ ${diskstatusaltsig} -gt 0 ]
  then disksumwarning=$(( ${diskstatusoff} + ${diskstatusaltsig} ))
  echo "DISK WARNING $disksumwarning disk(s) in warning state"; exit ${STATE_WARNING}	
else echo "DISK OK ${diskstatusok} disks OK ${diskstatusspare} disks spare"; exit ${STATE_OK}
fi
;;

# --- diskusage --- #
diskusage)
totalstorage_list=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.10.1.1)
usedstorage_list=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.10.1.2)

totalstorage=0
for t_storage in $totalstorage_list
do
  totalstorage=$(($totalstorage + $t_storage))
done

usedstorage=0
for u_storage in $usedstorage_list
do
  usedstorage=$(($usedstorage + $u_storage))
done

usedpercent=$(( ($usedstorage * 100)/$totalstorage  ))
freestorage=$(( $totalstorage - $usedstorage))
totalstorage_perfdata=$(($totalstorage*1024*1024))
usedstorage_perfdata=$(($usedstorage*1024*1024))

# Human readable output in GB
finalusedstorage=`expr ${usedstorage} / 1024` 
finaltotalstorage=`expr ${totalstorage} / 1024` 

if [ -n "${warning}" ] || [ -n "${critical}" ]
  then
  if [ ${usedpercent} -ge ${warning} ] && [ ${usedpercent} -lt ${critical} ]
    then
    echo "DISKUSAGE WARNING Total ${finaltotalstorage}GB, Used ${finalusedstorage}GB (${usedpercent}%) | 'space used'=${usedstorage_perfdata}, 'total space'=${totalstorage_perfdata}"
    exit ${STATE_WARNING}
  elif [ ${usedpercent} -ge ${critical} ]
    then
    echo "DISKUSAGE CRITICAL Total ${finaltotalstorage}GB, Used ${finalusedstorage}GB (${usedpercent}%) | 'space used'=${usedstorage_perfdata}, 'total space'=${totalstorage_perfdata}"
    exit ${STATE_CRITICAL}
  else
    echo "DISKUSAGE OK Total ${finaltotalstorage}GB, Used ${finalusedstorage}GB (${usedpercent}%) | 'space used'=${usedstorage_perfdata}, 'total space'=${totalstorage_perfdata}"; exit ${STATE_OK}
  fi
else echo "Total ${finaltotalstorage}GB, Used ${finalusedstorage}GB (${usedpercent}%) | 'space used'=${usedstorage_perfdata}, 'total space'=${totalstorage_perfdata}"; exit ${STATE_OK}
fi
;;

# --- raid --- #
raid)
raidstatus=$(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.13.1.1)

s8=0; s7=0; s6=0; s5=0; s4=0; s3=0; s2=0; s1=0
for s in $raidstatus
  do
  if [ "$s" = "1" ]; then s1=$((s1 + 1)); fi
  if [ "$s" = "2" ]; then s2=$((s2 + 1)); fi
  if [ "$s" = "3" ]; then s3=$((s3 + 1)); fi
  if [ "$s" = "4" ]; then s4=$((s4 + 1)); fi
  if [ "$s" = "5" ]; then s5=$((s5 + 1)); fi
  if [ "$s" = "6" ]; then s6=$((s6 + 1)); fi
  if [ "$s" = "7" ]; then s7=$((s7 + 1)); fi
  if [ "$s" = "8" ]; then s8=$((s8 + 1)); fi
done

declare -a raidpercentage=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.13.1.2))
index=0
for value in ${raidpercentage[@]}; do if [[ $value -eq 0 ]]; then unset raidpercentage[$index]; fi; let index++; done

if [ $s6 -gt 0 ]; then echo "RAID CATASTROPHIC LOSS"; exit ${STATE_CRITICAL}; fi
if [ $s5 -gt 0 ]; then echo "RAID FAILED"; exit ${STATE_CRITICAL}; fi
if [ $s2 -gt 0 ]; then echo "RAID DEGRADED"; exit ${STATE_WARNING}; fi
if [ $s4 -gt 0 ]; then echo "RAID RECONSTRUCTING (${raidpercentage[@]}%)"; exit ${STATE_WARNING}; fi
if [ $s3 -gt 0 ]; then echo "RAID VERIFYING (${raidpercentage[@]}%)"; exit ${STATE_WARNING}; fi
if [ $s7 -gt 0 ]; then echo "RAID EXPANDING (${raidpercentage[@]}%)"; exit ${STATE_WARNING}; fi
if [ $s8 -gt 0 ]; then echo "RAID COPY TO SPARE (${raidpercentage[@]}%)"; exit ${STATE_WARNING}; fi
if [ $s1 -gt 0 ]; then echo "RAID OK"; exit ${STATE_OK}; fi
;;

# --- uptime --- #
uptime)
uptimestatus=$(snmpwalk -v 2c -O v -c ${community} ${host} 1.3.6.1.2.1.1.3.0)
echo "${uptimestatus}"
exit ${STATE_OK}
;;

# --- ps (power supplies) --- #
ps)
psstate=$(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.8.1.3)
psfanstate=$(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.8.1.4)

s3=0; s2=0; s1=0; ps_count=0
for s in $psstate
  do
  if [ "$s" = "1" ]; then s1=$((s1 + 1)); fi
  if [ "$s" = "2" ]; then s2=$((s2 + 1)); fi
  if [ "$s" = "3" ]; then s3=$((s3 + 1)); fi
  ps_count=$(($ps_count + 1))
done

if [ $s3 -gt 0 ]; then echo "$s3 of $ps_count PSU(s): FAILED"; exit ${STATE_CRITICAL}; fi
if [ $s2 -gt 0 ]; then echo "$s2 of $ps_count PSU(s): NO AC POWER"; exit ${STATE_CRITICAL}; fi
if [ $s1 -gt 0 ]
  then 
  fanfail=0; psfan_count=0
  for fan in $psfanstate
  do
    if [[ $fan -gt 1 ]]; then fanfail=$(($fanfail + 1)); fi
    let psfan_count++
  done

  if [[ $fanfail -gt 0 ]]; then echo "$fanfail of $psfan_count PSU Fan(s): FAN NOT OPERATIONAL"; exit ${STATE_CRITICAL}; fi

  echo "$s1 of $ps_count PSU(s): OK"; exit ${STATE_OK}
fi
;;

# --- info --- #
info)
membernumber=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.11.1.1 | wc -l)
declare -a modelnumber=($(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.11.1.1 | sort -u))
declare -a serialnumber=($(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.11.1.2))

controllers=0
for ctrl in $(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.11.1.3); do controllers=$((${controllers} + $ctrl)); done

disknumber=0
for disks in $(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.11.1.4); do disknumber=$((${disknumber} + $disks)); done

declare -a firmware=($(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.4.1.1.1.4.1 | cut -d " " -f 4 | sort -u))

if [ ${controllers} -gt 1 ]
  then
  memberstring="members"
  modelstring="models"
  serialstring="Serials"
  controllerstring="Controllers"
  else
  memberstring="member"
  modelstring="model"
  serialstring="Serial"
  controllerstring="Controller"
fi

if [ ${#firmware[*]} -gt 1 ]
  then echo "Warning: Different firmware versions used across members (${firmware[*]})"; exit ${STATE_WARNING}
fi

echo "$membernumber $memberstring in Group. Used $modelstring: ${modelnumber[*]}. $serialstring: ${serialnumber[*]}. $controllerstring: ${controllers}. Running Firmware: ${firmware}. Total disks: ${disknumber}."
exit ${STATE_OK}
;;

# --- ethif (Ethernet Interfaces) --- #
ethif)
i=0
for line in $(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.2.1.2.2.1.2)
  do ethnames[${i}]=$line; i=$(($i + 1 ))
done
j=0
for line in $(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.2.1.2.2.1.6)
  do ethmacs[${j}]=$line; j=$(($j + 1))
done
ethnumber=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.2.1.2.2.1.2 | grep -c eth)
k=0
for line in $(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.4.1.12740.4.1.1.1.9)
  do contrstatus[${k}]=$line; k=$(($k + 1))
done

if [ $ethnumber = 3 ]
  then ethinfo="${ethnames[0]} (${ethmacs[0]}), ${ethnames[1]} (${ethmacs[1]}), ${ethnames[2]} (${ethmacs[2]})"
elif [ $ethnumber = 4 ]
  then ethinfo="${ethnames[0]} (${ethmacs[0]}), ${ethnames[1]} (${ethmacs[1]}), ${ethnames[2]} (${ethmacs[2]}), ${ethnames[3]} (${ethmacs[3]})"
fi

contr0ethstatus=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.2.1.2.2.1.7)
contr1ethstatus=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.2.1.2.2.1.8)
contr0ethup=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.2.1.2.2.1.7 | egrep -c "(up|1)")
contr1ethup=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.2.1.2.2.1.8 | egrep -c "(up|1)")
contr0ethdown=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.2.1.2.2.1.7 | egrep -c "(down|2)")
contr1ethdown=$(snmpwalk -v 2c -O vq -c ${community} ${host} 1.3.6.1.2.1.2.2.1.8 | egrep -c "(down|2)")

if [ ${contrstatus[0]} -lt ${contrstatus[1]} ]
  then ethup=${contr0ethup}; ethdown=${contr0ethdown}; contractive=0
else ethup=${contr1ethup}; ethdown=${contr1ethdown}; contractive=1
fi
if [ -n "${warning}" ] || [ -n "${critical}" ]
  then
  if [ ${ethdown} -ge ${warning} ] && [ ${ethdown} -lt ${critical} ]
    then echo "INTERFACES WARNING Total ${ethdown} interfaces down"; exit ${STATE_WARNING}
  elif [ ${ethdown} -ge ${critical} ]
    then echo "INTERFACES CRITICAL Total ${ethdown} interfaces down"; exit ${STATE_CRITICAL}
  else echo "INTERFACES OK ${ethup} interfaces up, Controller ${contractive} is active, $ethinfo";  exit ${STATE_OK}
  fi
else echo "INTERFACES OK ${ethup} interfaces up, Controller ${contractive} is active, $ethinfo"; exit ${STATE_OK}
fi
;;

# --- etherrors --- #
etherrors)
countCritical=0
countWarning=0
if [ -z $warning ]; then warning=0; fi
if [ -z $critical ]; then critical=0; fi

#get interface list
declare -a ifcount=($(snmpwalk -v 2c -O vqe -c ${community} ${host} .1.3.6.1.2.1.2.2.1.1 | wc -l ))

#loop to ifcount, starting at index 2 (0 and 1 are unused!?)
for ((i=2; i<=$(($ifcount+1)); i++))
  do
  iface[$i]=$(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.2.1.2.2.1.2.${i})  #IF-MIB::ifDescr.${i}
  inerr[$i]=$(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.2.1.2.2.1.14.${i}) #IF-MIB::ifInErrors.${i}
  outerr[$i]=$(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.2.1.2.2.1.20.${i}) #IF-MIB::ifOutErrors.${i}
  perfdata=$perfdata" ${iface[$i]}_in=${inerr[$i]};${warning};${critical} ${iface[$i]}_out=${outerr[$i]};${warning};${critical}"                          
  #...having errors...
  if [ ${inerr[$i]} -gt ${critical} ] || [ ${outerr[$i]} -gt ${critical} ]
    then
    statustext="${iface[$i]}: ${inerr[$i]}/${outerr[$i]}  $statustext"
    let countCritical++
  elif [ ${inerr[$i]} -gt ${warning} ] || [ ${outerr[$i]} -gt ${warning} ]
    then
    statustext="${iface[$i]}: ${inerr[$i]}/${outerr[$i]}  $statustext"
    let countcountWarning++
  fi
done

if [ ${countCritical} -gt 0 ]
  then
  echo "Ethernet Packets CRITICAL: $statustext | $perfdata"
  exit ${STATE_CRITICAL}
elif [ ${countWarning} -gt 0 ]
  then
  echo "Ethernet Packets WARNING: $statustext | $perfdata"
  exit ${STATE_WARNING}
else
  echo "Ethernet Packets OK | $perfdata"
  exit ${STATE_OK}
fi
;;

# --- conn (Connections) --- #
conn)
connections=0
for line in $(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.12.1.1)
  do connections=`expr ${connections} + ${line}`
done

if [ -n "${warning}" ] || [ -n "${critical}" ]
  then
  if [ ${connections} -ge ${warning} ] && [ ${connections} -lt ${critical} ]
    then echo "CONNECTIONS WARNING ${connections} ISCSI Connections (Threshold: ${warning}) | connections=${connections};${warning};${critical}"; exit ${STATE_WARNING}
  elif [ ${connections} -ge ${critical} ]
    then echo "CONNECTIONS CRITICAL ${connections} ISCSI Connections (Threshold: ${critical}) | connections=${connections};${warning};${critical}"; exit ${STATE_CRITICAL}
  else echo "CONNECTIONS OK ${connections} ISCSI Connections | connections=${connections};${warning};${critical}"; exit ${STATE_OK}
  fi
else
  echo "${connections} ISCSI Connections | connections=${connections}"; exit ${STATE_OK}
fi
;;

# --- poolconn (Pool Connections) --- #
poolconn)
highest=0
for line in $(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.12.1.1)
  do
  if [ "${line}" -ge "${highest}" ]
    then
    highest=${line}
  fi
done

if [ -n "${warning}" ] || [ -n "${critical}" ]
  then
  if [ ${highest} -ge ${warning} ] && [ ${highest} -lt ${critical} ]
    then echo "POOL CONNECTIONS WARNING ${highest} ISCSI Connections (Threshold: ${warning}) | connections=${highest};${warning};${critical}"; exit ${STATE_WARNING}
  elif [ ${highest} -ge ${critical} ]
    then echo "POOL CONNECTIONS CRITICAL ${highest} ISCSI Connections (Threshold: ${critical}) | connections=${highest};${warning};${critical}"; exit ${STATE_CRITICAL}
  else echo "POOL CONNECTIONS OK ${highest} ISCSI Connections | connections=${highest};${warning};${critical}"; exit ${STATE_OK}
  fi
else
  echo "${highest} ISCSI Connections | connections=${highest}"; exit ${STATE_OK}
fi
;;

# --- fan --- #
fan)
declare -a fannames=($(snmpwalk -v 2c -O vqe -c ${community} ${host} .1.3.6.1.4.1.12740.2.1.7.1.2 | tr '\n' ' '))

#find out which fans are in critical state
declare -a fancrit=($(snmpwalk -v 2c -O vqe -c ${community} ${host} .1.3.6.1.4.1.12740.2.1.7.1.4 | grep -n "3" | awk -F : '{print $1}' | tr '\n' ' '))
c=0
for line in ${fancrit[@]}
  do fancrit[$c]=`expr ${fancrit[$c]} - 1`
  let c++
done

# find the corresponding names of the critical fans
c=0
for line in ${fancrit[@]}
  do fanfinalcrit[${c}]=${fannames[$line]}
  let c++
done

#find out which fans are in warning state
declare -a fanwarn=($(snmpwalk -v 2c -O vqe -c ${community} ${host} .1.3.6.1.4.1.12740.2.1.7.1.4 | grep -n "2" | awk -F : '{print $1}' | tr '\n' ' '))
w=0
for line in ${fanwarn[@]}
  do fanwarn[$w]=`expr ${fanwarn[$w]} - 1`
  let w++
done

# find the corresponding names of the warning fans
w=0
for line in ${fanwarn[@]}
  do fanfinalwarn[${w}]=${fannames[$line]}
  let w++
done

#find out which fans are in unknown state
declare -a fanunknown=($(snmpwalk -v 2c -O vqe -c ${community} ${host} .1.3.6.1.4.1.12740.2.1.7.1.4 | grep -n "0" | awk -F : '{print $1}' | tr '\n' ' '))

if [[ ${#fanfinalcrit[*]} -gt 0 ]]
  then echo "CRITICAL Enclosure Fans: ${fanfinalcrit[*]}"; exit ${STATE_CRITICAL}
elif [[ ${#fanfinalwarn[*]} -gt 0 ]]
  then echo "WARNING Enclosure Fans: ${fanfinalwarn[*]}"; exit ${STATE_WARNING}
elif [[ ${#fanunknown[*]} -gt 0 ]]
  then echo "UNKNOWN Check Enclosure Fans, an unknown error occured"; exit ${STATE_UNKNOWN}
else echo "All Enclosure Fans OK"; exit ${STATE_OK}
fi
;;

# --- poolusage --- #
poolusage)
exitstate=0
c=1
for x in `snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.16.1.2.1.1`
  do
  pooltotal[$c]=${x}
  let c=c+1
done

c=1
for x in `snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.16.1.2.1.2`
  do
  poolused[$c]=${x}
  let c=c+1
done

c=1
for x in `snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.16.1.2.1.17`
  do
  pooldelegated[$c]=${x}
  let c=c+1
done

c=1
for x in `snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.16.1.2.1.9`
  do
  poolreplication[$c]=${x}
  let c=c+1
done

c=1
for x in `snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.16.1.1.1.3`
  do
  poolname[$c]=${x}
  let c=c+1
done

c2=1
detailed=""
while [ $c2 -lt $c ]
  do
  poolinuse=$(( ${poolused[$c2]}+${pooldelegated[$c2]}+${poolreplication[$c2]} ))
  freestorage=$(( (${pooltotal[$c2]} - ${poolinuse})/1024 ))
  if [[ ${poolinuse} -gt 0 && ${pooltotal[$c2]} -gt 0 ]]
    then usedpercent=$(( (${poolinuse} * 100)/${pooltotal[$c2]} ))
    else usedpercent=0
  fi
  let pooltotal[$c2]=pooltotal[$c2]/1024
  let pooldelegated[$c2]=pooldelegated[$c2]/1024
  let poolreplication[$c2]=poolreplication[$c2]/1024
  let poolinuse=poolinuse/1024
  let poolused[$c2]=poolused[$c2]/1024

  result="Pool ${poolname[c2]} Size ${pooltotal[$c2]}GB, Total In Use ${poolinuse}GB (${usedpercent}%) = (Used ${poolused[$c2]}GB + Delegated ${pooldelegated[$c2]}GB + Replication ${poolreplication[$c2]}GB), Free ${freestorage}GB //"

  if [ -n "${warning}" ] || [ -n "${critical}" ]
    then
    if [ ${usedpercent} -ge ${warning} ] && [ ${usedpercent} -lt ${critical} ]
      then
      echo -n "WARNING: ${result}"
      if [ ${exitstate} -ne 2 ]
        then
        exitstate=${STATE_WARNING}
      fi
      elif [ ${usedpercent} -ge ${critical} ]
        then
        echo -n "CRITICAL: ${result}"
        exitstate=${STATE_CRITICAL}
      else
        echo -n "OK: ${result}"
      fi
    else
      echo -n "OK: "${result}
  fi

  echo -n " "
  let c2=c2+1
done

exit ${exitstate}
;;

# --- memberusage --- #
memberusage)
bad=0
c=1
for x in `snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.10.1.1`
  do
  pooltotal[$c]=$x
  let c=c+1
done

c=1
for x in `snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.2.1.10.1.2`
  do
  poolused[$c]=$x
  let c=c+1
done

c2=1
while [ $c2 -lt $c ]
  do
  usedpercent=$(( (${poolused[$c2]} * 100)/${pooltotal[$c2]}  ))
  freestorage=$(( ${pooltotal[$c2]} - ${poolused[$c2]}))
  pooltotal_perfdata=$(( ${pooltotal[$c2]}*1024*1024))
  poolused_perfdata=$(( ${poolused[$c2]}*1024*1024))
  let pooltotal[$c2]=pooltotal[$c2]/1024
  let poolused[$c2]=poolused[$c2]/1024

  if [ -n "${warning}" ] || [ -n "${critical}" ]
    then
    if [ ${usedpercent} -ge ${warning} ] && [ ${usedpercent} -lt ${critical} ]
      then
      echo -n "WARNING: Pool $c2 Total ${pooltotal[$c2]}GB, Used ${poolused[$c2]}GB (${usedpercent}%)|'space used'=${poolused_perfdata}, 'total space'=${pooltotal_perfdata}"
      if [ $bad -ne 2 ]
        then
        bad=1
      fi
    elif [ ${usedpercent} -ge ${critical} ]
      then
      echo -n "CRITICAL: Pool $c2 Total ${pooltotal[$c2]}GB, Used ${poolused[$c2]}GB (${usedpercent}%)|'space used'=${poolused_perfdata}, 'total space'=${pooltotal_perfdata}"
      bad=2
    else
      echo -n "OK: Pool $c2 Total ${pooltotal[$c2]}GB, Used ${poolused[$c2]}GB (${usedpercent}%)|'space used'=${poolused_perfdata}, 'total space'=${pooltotal_perfdata}"
    fi
  else
    echo -n "OK: Pool $c2 Total ${pooltotal[$c2]}GB, Used ${poolused[$c2]}GB (${usedpercent}%)|'space used'=${poolused_perfdata}, 'total space'=${pooltotal_perfdata}"
  fi

  let c2=c2+1
done

exit $bad
;;

# --- volumes --- #
volumes)
volumescount=$(snmpwalk -v 2c -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.4 | wc -l)
declare -a volumenames=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.4 | tr '\n' ' '))
declare -a volumeavailspace=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.8 | tr '\n' ' '))
declare -a volumeusedspace=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.7.1.13 | tr '\n' ' '))

# Determine special Equallogic volumes and remove them from array
ignorevolumes=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.8 | grep -n -w "0" | awk -F : '{print $1}' | tr '\n' ' '))
k=0
while [ ${k} -lt ${#ignorevolumes[@]} ]
  do
  finalignore[$k]=`expr ${ignorevolumes[$k]} - 1`
  unset volumenames[${finalignore[$k]}]
  unset volumeavailspace[${finalignore[$k]}]
  unset volumeusedspace[${finalignore[$k]}]
  let k++
done

# How many real volumes (manmade) do exist
realvolumescount=`expr ${volumescount} - ${#ignorevolumes[@]}`

# Calculate Free Space and Percentage per Volume
i=0
while [ ${i} -le ${volumescount} ]
  do
  if [ ${volumenames[${i}]} ]
    then
    volumefreespace[${i}]=`expr ${volumeavailspace[${i}]} - ${volumeusedspace[${i}]}`
    volumepercentage[${i}]=`expr ${volumeusedspace[${i}]} \* 100 / ${volumeavailspace[${i}]}`
    #       echo "$i: ${volumenames[$i]}, free Space: ${volumefreespace[${i}]} used: ${volumepercentage[${i}]} %" # For Debug
    perfavailspace[${i}]=$((${volumeavailspace[${i}]}*1024*1024))
    perfusedspace[${i}]=$((${volumeusedspace[${i}]}*1024*1024))
    perffreespace[${i}]=$((${volumefreespace[${i}]}*1024*1024))
    perfdata[${i}]="${volumenames[$i]}=${perfusedspace[${i}]};${perffreespace[${i}]};${perfavailspace[${i}]};"
    let i++
  else
    let i++
  fi
done

# Output Warning and Critical
if [ -n "${warning}" ] || [ -n "${critical}" ]
  then
  j=0
  while [ ${j} -le ${volumescount} ]
    do
    if [ ${volumenames[${j}]} ]
      then
      if [ ${volumepercentage[${j}]} -ge ${warning} ] && [ ${volumepercentage[${j}]} -lt ${critical} ]
        then volumewarning[${j}]="${volumenames[${j}]}: ${volumepercentage[${j}]}% used "
      elif [ ${volumepercentage[${j}]} -ge ${critical} ]
        then volumecritical[${j}]="${volumenames[${j}]}: ${volumepercentage[${j}]}% used "
      else volumeok[${j}]="${volumenames[$j]}: ${volumepercentage[${j}]}% used "
      fi
      let j++
    else
    let j++
    fi
  done

  if [ ${#volumewarning[@]} -gt 0 ] && [ ${#volumecritical[@]} -lt 1 ]
    then echo "WARNING ${volumewarning[@]}|${perfdata[*]}"; exit ${STATE_WARNING}
  elif [ ${#volumecritical[@]} -ge 1 ]
    then echo "CRITICAL ${volumecritical[@]}|${perfdata[*]}"; exit ${STATE_CRITICAL}
  else
    echo "OK ${volumeok[*]}|${perfdata[*]}"; exit ${STATE_OK}
  fi

  # Output without thresholds
else
  j=0
  while [ ${j} -le ${volumescount} ]
    do
    if [ ${volumenames[${j}]} ]
      then
      volumefinaloutput[${j}]="${volumenames[$j]}: ${volumepercentage[${j}]}% used "
      let j++
    else
      let j++
    fi
  done
  echo "${volumefinaloutput[*]}|${perfdata[*]}"
  exit ${STATE_OK}
fi
;;

# --- vol (single volume) --- #
vol)	
# Get Array No. for wanted Volume Name: ./check_equallogic -H x.x.x.x -C public -t vol -v-v  V2
if [ -z "${volume}" ]
  then
  echo "CRITICAL - No volume name given."; exit 2
fi
volarray=$(snmpwalk -v 2c -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.4 | grep -n "\"${volume}\"" | sed -n '1p' | cut -d : -f1)
volavailspace=$(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.8 | awk "NR==${volarray}")
humanavailspace=$((${volavailspace} / 1024))
perfavailspace=$((${volavailspace}*1024*1024))
volusedspace=$(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.7.1.13 | awk "NR==${volarray}")
humanusedspace=$((${volusedspace} / 1024))
perfusedspace=$((${volusedspace}*1024*1024))
volpercentage=$(expr ${volusedspace[${i}]} \* 100 / ${volavailspace[${i}]})

if [ -n "${warning}" ] || [ -n "${critical}" ]
  then
  if [ ${volpercentage} -ge ${warning} ] && [ ${volpercentage} -lt ${critical} ]
    then echo "WARNING - Volume ${volume} used ${humanusedspace}GB of ${humanavailspace}GB (${volpercentage}%)|'volavail'=${perfavailspace}, 'volused'=${perfusedspace}"
    exit ${STATE_WARNING}
  elif [ ${volpercentage} -ge ${critical} ]
    then echo "CRTICAL - Volume ${volume} used ${humanusedspace}GB of ${humanavailspace}GB (${volpercentage}%)|'volavail'=${perfavailspace}, 'volused'=${perfusedspace}"
    exit ${STATE_CRITICAL}
  else echo "OK - Volume ${volume} used ${humanusedspace}GB of ${humanavailspace}GB (${volpercentage}%)|'volavail'=${perfavailspace}, 'volused'=${perfusedspace}"
  exit ${STATE_OK}
  fi
else echo "OK - Volume ${volume} used ${humanusedspace}GB of ${humanavailspace}GB (${volpercentage}%)|'volavail'=${perfavailspace}, 'volused'=${perfusedspace}"
exit ${STATE_OK}
fi
;;

# --- snapshots --- #
snapshots)
volumescount=$(snmpwalk -v 2c -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.4 | wc -l)
declare -a volumenames=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.4 | tr '\n' ' '))
#Get the configured warning theshold stored in the unit for each volume
declare -a volumesnapwarnlevel=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.11 | tr '\n' ' '))
#Get the total amount of reserve space allocated for snapshots for each volume
declare -a volumestatusreservedspace=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.7.1.2 | tr '\n' ' '))
#Get the amount of reserve snapshot space that is available for each volume
declare -a volumestatusreservedspaceavail=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.7.1.3 | tr '\n' ' '))
# Determine special Equallogic volumes and remove them from array
ignorevolumes=($(snmpwalk -v 2c -O vqe -c ${community} ${host} 1.3.6.1.4.1.12740.5.1.7.1.1.8 | grep -n -w "0" | awk -F : '{print $1}' | tr '\n' ' '))
k=0
while [ ${k} -lt ${#ignorevolumes[@]} ]
  do
  finalignore[$k]=`expr ${ignorevolumes[$k]} - 1`
  unset volumenames[${finalignore[$k]}]
  unset volumeavailspace[${finalignore[$k]}]
  unset volumeusedspace[${finalignore[$k]}]
  let k++
done

# How many real volumes (manmade) do exist
realvolumescount=`expr ${volumescount} - ${#ignorevolumes[@]}`

# Calculate Percentage Free space for snapshots and compare with Warn Level
i=0
while [ ${i} -le ${realvolumescount} ]
  do
  if [ ${volumenames[${i}]} ] && [ ${volumestatusreservedspace[${i}]} -gt 0 ]
    then
    volumesnapfree[${i}]=`expr ${volumestatusreservedspaceavail[${i}]} \* 100 / ${volumestatusreservedspace[${i}]}`
    #echo "$i: ${volumenames[$i]}, percentfree: ${volumesnapfree[${i}]} %, warnlevel ${volumesnapwarnlevel[${i}]} %" # For Debug
    let i++
  else
    let i++
  fi
done

# Output Warning and Critical
j=0
while [ ${j} -le ${realvolumescount} ]
  do
  if [ ${volumenames[${j}]} ]  && [ ${volumestatusreservedspace[${j}]} -gt 0 ]
    then
    #If a critical threshold is specific at run time, check to make sure this ammount of space if available
    if [ -n "${critical}" ] && [ `expr 100 - ${volumesnapfree[${j}]}` -ge  ${critical} ]
      then volumecritical[${j}]="${volumenames[${j}]}: ${volumesnapfree[${j}]}% free"
    #If the amount of reserve space is below the threshold set for that volume, issue a warning
    elif [  ${volumesnapfree[${j}]} -lt  ${volumesnapwarnlevel[${j}]} ]
      then volumewarning[${j}]="${volumenames[${j}]}: ${volumesnapfree[${j}]}% free"
    else volumeok[${j}]="${volumenames[$j]}: ${volumesnapfree[${j}]}% free"
    fi
  let j++
  else
    let j++
  fi
done

if [ ${#volumewarning[@]} -gt 0 ] && [ ${#volumecritical[@]} -lt 1 ]
  then echo "WARNING ${volumewarning[@]}"; exit ${STATE_WARNING}
elif [ ${#volumecritical[@]} -ge 1 ]
  then echo "CRITICAL ${volumecritical[@]}"; exit ${STATE_CRITICAL}
else
  echo "OK ${volumeok[*]}"; exit ${STATE_OK}
fi
;;


esac


echo "UNKNOWN: should never reach this part"
exit ${STATE_UNKNOWN}
