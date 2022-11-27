#!/bin/bash


EMC2301_test(){
	echo -n "$FUNCNAME: Drive "
	EMC2301_getDrive
	EMC2301_setFSCAEnable 0
	local i=0;
	while [ $i -lt 5 ]; do
		local i_rand=$((RANDOM % 101))
		echo "$FUNCNAME: Set Drive $i_rand"
		EMC2301_setDrive "$i_rand"
		sleep 3
		((i+=1))
	done
	echo -n "$FUNCNAME: FSCA "
	EMC2301_isFSCAEnabled && echo 1 || echo 0
	EMC2301_setFSCAEnable 1
	echo -n "$FUNCNAME: FSCA "
	EMC2301_isFSCAEnabled && echo 1 || echo 0
	sleep 5
	EMC2301_setDrive 0
}