#!/bin/bash
# SPDX-License-Identifier: CC-BY-NC-ND-4.0
# SPDXVersion: SPDX-2.2
# SPDX-FileCopyrightText: Copyright 2022 Da Xue

if [ -z "$EMC2301_CLK" ]; then
	EMC2301_CLK=32768
fi
if [ -z "$EMC2301_I2C_ADDR" ]; then
	EMC2301_I2C_ADDR="0x2f"
fi
EMC2301_DRIVE_REG="0x30"
EMC2301_FANCFG_REG="0x32"
EMC2301_DRIVEMIN_REG="0x38"
EMC2301_TACHVALID_REG="0x39"
EMC2301_TACHTARGET_REG="0x3c"
EMC2301_TACHREAD_REG="0x3e"
EMC2301_PRODID_REG="0xfd"
EMC2301_MANUID_REG="0xfe"
EMC2301_REV_REG="0xff"
EMC2301_TACHVALID_SHIFT=5
EMC2301_FSCA_MASK=128
EMC2301_FSCA_SHIFT=7
EMC2301_RANGE_MASK=96
EMC2301_RANGE_SHIFT=5
EMC2301_EDGES_MASK=24
EMC2301_EDGES_SHIFT=3
EMC2301_TACHREAD_SHIFT=3
EMC2301_TACHTARGET_SHIFT=3
EMC2301_TACHTARGET_OFF=8191
EMC2301_PRODID_VAL="0x37"
EMC2301_MANUID_VAL="0x5d"
EMC2301_REV_VAL="0x80"

EMC2301_FSCA_LAST=
EMC2301_RANGE_LAST=
EMC2301_RANGE_RPM_MIN=
EMC2301_EDGES_LAST=
EMC2301_EDGES_TACH_MIN=

HEX_toDec(){
	printf "%d" "$1"
}
HEX_revByte(){
	local hex="${1,,}"
	if [ "${hex:0:2}" = "0x" ]; then
		hex=${hex:2}
	fi
	echo -n "0x"
	echo "$hex" | fold -w2 | tac | tr -d "\n"
}
DEC_toHexByte(){
	printf "0x%02x" "$1"
}
I2C_get(){
	i2cget -y "$1" "$2" "$3" "$4"
}

I2C_set(){
	i2cset -y "$1" "$2" "$3" "$4" "$5"
}
EMC2301_get(){
	I2C_get "$EMC2301_I2C_BUS" "$EMC2301_I2C_ADDR" "$1" "$2"
}
EMC2301_set(){
	I2C_set "$EMC2301_I2C_BUS" "$EMC2301_I2C_ADDR" "$1" "$2" "$3"
}
EMC2301_check(){
	local product_id=$(EMC2301_get "$EMC2301_PRODID_REG" b)
	[ "$product_id" = "$EMC2301_PRODID_VAL" ] || (echo "$FUNCNAME: $product_id does not match Product ID" >&2 && return 1)
	local manufacturer_id=$(EMC2301_get "$EMC2301_MANUID_REG" b)
	[ "$manufacturer_id" = "$EMC2301_MANUID_VAL" ] || (echo "$FUNCNAME: $manufacturer_id does not match Manufacturer ID" >&2 && return 1)
	local revision=$(EMC2301_get "$EMC2301_REV_REG" b)
	[ "$revision" = "$EMC2301_REV_VAL" ] || (echo "$FUNCNAME: $revision does not match Revision" >&2 && return 1)
}
EMC2301_getDrive(){
	local drive_scaled_hex=$(EMC2301_get $EMC2301_DRIVE_REG b)
	local drive_scaled=$(HEX_toDec $drive_scaled_hex)
	echo "scale=0; $drive_scaled*100/255" | bc -l
}
EMC2301_setDrive(){
	local drive="$1"
	if [ "$drive" -gt 100 ]; then
		echo "$FUNCNAME: $drive exceeds max (100)" >&2
		return 1
	elif [ "$drive" -lt 0 ]; then
		echo "$FUNCNAME: $drive below min (0)" >&2
		return 1
	fi
	local drive_scaled=$(echo "scale=0; $drive*255/100" | bc -l)
	local drive_scaled_hex=$(DEC_toHexByte $drive_scaled)
	EMC2301_set $EMC2301_DRIVE_REG $drive_scaled_hex b
}
EMC2301_getDriveMin(){
	local drivemin_scaled_hex=$(EMC2301_get $EMC2301_DRIVEMIN_REG b)
	local drivemin_scaled=$(HEX_toDec $drivemin_scaled_hex)
	echo "scale=0; $drivemin_scaled*100/255" | bc -l
}
EMC2301_setDriveMin(){
	local drivemin="$1"
	if [ "$drivemin" -gt 100 ]; then
		echo "$FUNCNAME: $drivemin exceeds max (100)" >&2
		return 1
	elif [ "$drivemin" -lt 0 ]; then
		echo "$FUNCNAME: $drivemin below min (0)" >&2
		return 1
	fi
	local drivemin_scaled=$(echo "scale=0; $drivemin*255/100" | bc -l)
	local drivemin_scaled_hex=$(DEC_toHexByte $drivemin_scaled)
	EMC2301_set $EMC2301_DRIVEMIN_REG $drivemin_scaled_hex b
}

EMC2301_isFSCAEnabled(){
	if [ ! -z "$EMC2301_FSCA_LAST" ]; then
		[ $EMC2301_FSCA_LAST -eq 1 ]
	else
		local fancfg_hex=$(EMC2301_get $EMC2301_FANCFG_REG b)
		local fsca_cur=$(((fancfg_hex & EMC2301_FSCA_MASK) >> EMC2301_FSCA_SHIFT))
		[ $fsca_cur -eq 1 ]
	fi
}
EMC2301_setFSCAEnable(){
	local fsca="$1"
	local fancfg_hex=$(EMC2301_get $EMC2301_FANCFG_REG b)
	local fsca_cur=$(((fancfg_hex & EMC2301_FSCA_MASK) >> EMC2301_FSCA_SHIFT))
	local fancfg
	if [ $fsca_cur != "$fsca" ]; then
		fancfg=$(((fancfg_hex ^ (fsca << $EMC2301_FSCA_SHIFT)) & $EMC2301_FSCA_MASK ^ fancfg_hex))
		EMC2301_set $EMC2301_FANCFG_REG $(DEC_toHexByte "$fancfg") b
	fi
	EMC2301_FSCA_LAST="$1"
}
EMC2301_getRange(){
	if [ ! -z "$EMC2301_RANGE_LAST" ]; then
		echo $EMC2301_RANGE_LAST
	else
		local fancfg_hex=$(EMC2301_get $EMC2301_FANCFG_REG b)
		echo $(((fancfg_hex & EMC2301_RANGE_MASK) >> EMC2301_RANGE_SHIFT))
	fi
}
EMC2301_getRangeMultiplier(){
	local range=$(EMC2301_getRange)
	echo $((1 << $range))
}
EMC2301_setRange(){
	local range="$1"
	if [ "$range" -gt 3 ]; then
		echo "$FUNCNAME: $range exeeds max (3)" >&2
		return 1
	elif [ "$range" -lt 0 ]; then
		ehoc "$FUNCNAME: $range below min (0)" >&2
		return 1
	fi
	local fancfg_hex=$(EMC2301_get $EMC2301_FANCFG_REG b)
	local range_cur=$(((fancfg_hex & EMC2301_RANGE_MASK) >> $EMC2301_RANGE_SHIFT))
	local fancfg
	if [ $range_cur != "$range" ]; then
		fancfg=$(((fancfg_hex ^ (range << EMC2301_RANGE_SHIFT)) & EMC2301_RANGE_MASK ^ fancfg_hex))
		EMC2301_set $EMC2301_FANCFG_REG $(DEC_toHexByte "$fancfg") b
	fi
	EMC2301_RANGE_RPM_MIN=$((500*(1 << $range)))
	EMC2301_RANGE_LAST=$range
}
EMC2301_getEdges(){
	if [ ! -z "$EMC2301_EDGES_LAST" ]; then
		echo $EMC2301_EDGES_LAST
	else
		local fancfg_hex=$(EMC2301_get $EMC2301_FANCFG_REG b)
		echo $(((fancfg_hex & EMC2301_EDGES_MASK) >> EMC2301_EDGES_SHIFT))
	fi
}
EMC2301_getEdgesMultiplier(){
	local edges=$(EMC2301_getEdges)
	echo "scale=1; 0.5*($edges+1)" | bc
}
EMC2301_setEdges(){
	local edges="$1"
	if [ "$edges" -gt 3 ]; then
		echo "$FUNCNAME: $edges exeeds max (3)" >&2
		return 1
	elif [ "$edges" -lt 0 ]; then
		ehoc "$FUNCNAME: $edges below min (0)" >&2
		return 1
	fi
	local fancfg_hex=$(EMC2301_get $EMC2301_FANCFG_REG b)
	local edges_cur=$(((fancfg_hex & EMC2301_EDGES_MASK) >> EMC2301_EDGES_SHIFT))
	local fancfg
	if [ $edges_cur != "$edges" ]; then
		fancfg=$(((fancfg_hex ^ (edges << EMC2301_EDGES_SHIFT)) & EMC2301_EDGES_MASK ^ fancfg_hex))
		EMC2301_set $EMC2301_FANCFG_REG $(DEC_toHexByte "$fancfg") b
	fi
	EMC2301_EDGES_TACH_MIN=$((2 * $edges + 3))
	EMC2301_EDGES_LAST=$edges
}
EMC2301_getTachValid(){
	local fantach_valid_hex=$(EMC2301_get $EMC2301_TACHVALID_REG w)
	local fantach_valid=$(HEX_toDec $fantach_valid_hex)
	echo $((fantach_valid << EMC2301_TACHVALID_SHIFT))
}
EMC2301_getTachValidRPM(){
	echo $(EMC2301_convertTachRPM $(EMC2301_getTachValid))
}
EMC2301_setTachValid(){
	local fantach_valid=$1
	local fantach_valid_hex=$(DEC_toHexByte $((fantach_valid >> EMC2301_TACHVALID_SHIFT)))
	EMC2301_set $EMC2301_TACHVALID_REG $fantach_valid_hex w
}
EMC2301_setTachValidRPM(){
	EMC2301_setTachValid $(EMC2301_convertTachRPM $1)
}
EMC2301_getTach(){
	local fantach_hex=$(EMC2301_get $EMC2301_TACHREAD_REG w)
	fantach_hex=$(HEX_revByte "$fantach_hex")
	local fantach=$(HEX_toDec $fantach_hex)
	echo $((fantach >> EMC2301_TACHREAD_SHIFT))
}
EMC2301_getTachTarget(){
	local fantach_target_hex=$(EMC2301_get $EMC2301_TACHTARGET_REG w)
	local fantach_target=$(HEX_toDec "$fantach_target_hex")
	echo $((fantach_target >> EMC2301_TACHTARGET_SHIFT))
}
EMC2301_setTachTarget(){
	local fantach=$1
	local fantach_hex=$(DEC_toHexByte $((fantach << EMC2301_TACHTARGET_SHIFT)))
	EMC2301_set $EMC2301_TACHTARGET_REG $fantach_hex w
}
EMC2301_getRPM(){
	EMC2301_convertTachRPM $(EMC2301_getTach)
}
EMC2301_getRPMTarget(){
	EMC2301_convertTachRPM $(EMC2301_getTachTarget)
}
EMC2301_setRPMTarget(){
	EMC2301_setTachTarget $(EMC2301_convertTachRPM $1)
}
EMC2301_convertTachRPM(){
	echo "scale=0; ($EMC2301_EDGES_TACH_MIN-1)*$EMC2301_CLK*60*$(EMC2301_getRangeMultiplier)/$EMC2301_FAN_POLES/$1" | bc -l
}