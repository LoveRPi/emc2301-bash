#!/bin/bash
# SPDX-License-Identifier: CC-BY-NC-ND-4.0
# SPDXVersion: SPDX-2.2
# SPDX-FileCopyrightText: Copyright 2022 Da Xue

set -e

cd $(readlink -f $(dirname ${BASH_SOURCE[0]}))

. emc2301.ini
. emc2301.sh
. daemon.ini

DAEMON_TACH_MIN=
DAEMON_RPM_MAX=
DAEMON_TACH_TARGET=
DAEMON_FSCA=
if [ -z "$VERBOSE" ]; then
	VERBOSE=0
fi

EMC2301_daemon(){
	EMC2301_check && echo "EMC2301 detected" || (echo "EMC2301 not detected" && return 1)
	if EMC2301_isFSCAEnabled; then
		echo "$FUNCNAME: Fan Speed Control Algorithm is enabled, disabling"
		EMC2301_setFSCAEnable 0
	else
		echo "$FUNCNAME: Fan Speed Control Algorithm is disabled"
	fi
	EMC2301_setDriveMin $DAEMON_FAN_DRIVEMIN
	echo "$FUNCNAME: Minimum Drive set to $DAEMON_FAN_DRIVEMIN"
	EMC2301_setRange $DAEMON_FAN_RANGE
	echo "$FUNCNAME: Range set to $DAEMON_FAN_RANGE ($EMC2301_RANGE_RPM_MIN RPM min)"
	EMC2301_setEdges $DAEMON_FAN_EDGES
	echo "$FUNCNAME: Edges set to $DAEMON_FAN_EDGES ($EMC2301_EDGES_TACH_MIN Tach Edges)"
	EMC2301_setDrive 100
	echo "$FUNCNAME: Drive set to max for $DAEMON_FAN_DET_SEC seconds"
	sleep $DAEMON_FAN_DET_SEC
	DAEMON_TACH_MIN=$(EMC2301_getTach)
	DAEMON_RPM_MAX=$(EMC2301_getRPM)
	echo "$FUNCNAME: Max RPM: $DAEMON_RPM_MAX	Tach: $DAEMON_TACH_MIN"
	EMC2301_setFSCAEnable 1 && DAEMON_FSCA=1
	echo "$FUNCNAME: Fan Speed Control Algorithm enabled"
	DAEMON_TACH_TARGET=$(EMC2301_getTachTarget)
	while true; do
		#read -e input
		#$input
		#continue
		EMC2301_monitor
		sleep $DAEMON_FREQ_SEC
	done
}
EMC2301_convertTempRaw(){
	local temp_raw=$1
	echo $(((temp_raw + 500) / 1000))
}
EMC2301_monitor(){
	local temp_raw=$(cat $DAEMON_TEMP_SOURCE)
	local temp=$(EMC2301_convertTempRaw "$temp_raw")
	local temps_count=${#DAEMON_TEMPS[@]}
	local speed=0
	for i in $(seq 0 $((temps_count - 1))); do
		if [ $temp -ge ${DAEMON_TEMPS[$i]} ]; then
			speed=${DAEMON_SPEED[$i]}
		else
			break
		fi
	done
	if [ $speed -ge 100 ]; then
		echo "$FUNCNAME: Disabling FSCA, Set Drive to max"
		EMC2301_setFSCAEnable 0 && DAEMON_FSCA=0
		EMC2301_setDrive 100
		return
	elif [ $DAEMON_FSCA -eq 0 ]; then
		echo "$FUNCNAME: Enabling FSCA"
		EMC2301_setFSCAEnable 1 && DAEMON_FSCA=1
	fi
	local rpm_target=0
	local tach_target=
	if [ $speed -le 0 ]; then
		tach_target=$EMC2301_TACHTARGET_OFF
	else
		#echo "$FUNCNAME: rpm_target=$(DAEMON_RPM_MAX-$EMC2301_RANGE_RPM_MIN)*$speed/100+$EMC2301_RANGE_RPM_MIN"
		rpm_target=$(((DAEMON_RPM_MAX-EMC2301_RANGE_RPM_MIN)*speed/100+EMC2301_RANGE_RPM_MIN))
		tach_target=$(EMC2301_convertTachRPM $rpm_target)
	fi
	if [ $tach_target != $DAEMON_TACH_TARGET ]; then
		if [ "$VERBOSE" -eq 1 ]; then
			echo "$FUNCNAME: Temperature: $temp	Target RPM: $rpm_target	Target Tach: $tach_target"
		fi
		EMC2301_setTachTarget $tach_target
		DAEMON_TACH_TARGET=$tach_target
	fi
}
EMC2301_daemon