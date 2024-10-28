#!/bin/bash
#
# w11arm_addDrivers - add VMware network driver to "vanilla" Windows 11 ARM ISO
#
# Copyright (C) 2024 Paul Rockwell
#
# This program is free software; you can redistribute it and/or modify it to suit
# your needs.
# All I ask is that you provide proper attribution.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# 


readonly versionID="v1.0.0 (20241027)"
readonly version="w11arm_addDrivers ${versionID}\n"
readonly minDiskSpace=12

declare msISO
declare tempDir="."
declare fusionApp="/Applications/VMware Fusion.app"
declare toolsIso="${fusionApp}/Contents/Library/isoimages/arm64/windows.iso"
declare isoOutFile
declare isoMountFolder
declare retVal
declare elToritoBootFile

usage() {
	echo -e "Usage:\n"
	echo -e "$0 [-Vh] windows11-iso-file"
	echo -e "\nOptions:"
	echo -e "\t-h\tPrint usage and exit"
	echo -e "\t-V\tPrint program version and exit"
	echo
}

reportError() {
	local -r errInfo=$1

	echo -e "[ERROR] $errInfo"
}

programAbort() {
	local -r errCode=$1
	local -r keepWorkDir=$2

	echo -e "Program exiting, no ISO created"
	if (( $keepWorkDir == 0 )); then
		rm -rf "${wDir}"
	fi
	exit $errCode
}
copyDrivers() {
	echo -e "Mounting VMware Tools iso"
	hdiutil attach "${toolsIso}"
	retVal=$?
	if (( ${retVal} != 0 )); then
		reportError "VMware Tools ISO mount failed, error code ${retVal}"
		return $retVal
	fi
	echo -e "Copying vmxnet3 driver from Tools ISO to imaging folder"
	if [[ ! -d "${wDir}/ESD_ISO/\$WinPEDriver\$" ]] ; then
		mkdir "${wDir}/ESD_ISO/\$WinPEDriver\$"
	fi
	ditto -v "/Volumes/VMware Tools/vmxnet3" "${wDir}/\$WinPEDriver\$/vmxnet3"
	retVal=$?
	if (( ${retVal} != 0 )); then
		reportError "Driver copy failed, error code ${retVal}"
	fi
	chmod -R u+w "${wDir}/\$WinPEDriver\$/vmxnet3"
	echo -e "Dismounting VMware Tools ISO"
	hdiutil detach "/Volumes/VMware Tools"
	return $retVal
}

copyIso2Workdir(){

	echo -e "Mounting ISO ${msIso}"
	hdiutil attach "${msIso}" > "${wDir}/attachMsIso.log"
	retVal=$?
	if (( ${retVal} != 0 )); then
		reportError "ISO mount failed, error code ${retVal}"
		return ${retVal}
	fi
	isoMountFolder=$(cat "${wDir}/attachMsIso.log" | sed -e 's:.*/Volumes:/Volumes:' )
	if [[ -f "${isoMountFolder}/setup.exe" ]]; then
	
		echo -e "Copying ISO contents to imaging folder"
		ditto -v "${isoMountFolder}" "${wDir}/ESD_ISO"
		retVal=$?
		if (( ${retVal} != 0 )); then
			reportError "ISO copy failed, error code ${retVal}"
		fi
	else
		reportError "setup.exe doesn't exist in ISO, this may not be a Windows ISO file'"
	fi
	echo -e "Dismounting ISO ${msIso}"
	hdiutil detach "${isoMountFolder}"
	return $retVal
}

buildIso(){
	echo
	echo -e "Building ISO from imaging folder"
	if [[ -f "${isoOutFile}" ]]; then
		echo "${isoOutFile} already exists, deleting it"
		rm -rf "${isoOutFile}"
	fi
    elToritoBootFile="${wDir}/ESD_ISO/efi/microsoft/boot/efisys.bin"
	
	#
	# Experimental - change the efisys.bin file to eliminate the 
	# annoying "Press any key to boot from CD or DVD"
	# message
	
	(
		cd "${wDir}/ESD_ISO/efi/microsoft/boot"
		mv efisys.bin efisys_prompt.bin
		mv efisys_noprompt.bin efisys.bin
	)
	#
	# Create the ISO file
	#

	hdiutil makehybrid -o "${isoOutFile}" -iso -udf -udf-volume-name W11_ESD_VMWARE -hard-disk-boot -eltorito-boot "$elToritoBootFile" "${wDir}/ESD_ISO"
	retVal=$?
	if (( ${retVal} != 0 )); then
		reportError "ISO build failed, error code ${retVal}"
	fi

	return ${retVal}

}


#-------------------
#
# Start of program
#
#-------------------

#-------------------
# 
# Process arguments (the -d option is undocumented and enables debug mode)
# 
#-------------------

while getopts "hV" opt; do
  case ${opt} in
    h)
		usage
    	exit 1
    	;;
	V)
    	echo -e $version
    	exit 1
    	;;
    
    \?)
    	reportError "Invalid option: -$OPTARG"
    	usage
    	exit 1
    	;;
    esac
done
shift "$((OPTIND-1))"


#-------------------
# Check number of arguments
# No arguments are allowed
#-------------------

if (( $# == 0 )); then
	reportError "ISO file not specified"
	usage
	exit 1
fi

if (( $# > 1 )); then
	reportError "too many arguments specified"
	usage
	exit 1
fi

#-------------------
# Check if required utilities are installed
#-------------------

	
if [[ ! -d "${fusionApp}" ]]; then
	reportError "Fusion app not installed"
	exit 1
fi

msIso="$1"


if [[ ! -f "${msIso}" ]]; then
	reportError "${msIso} doesn't exist or is not a regular file"
	programAbort 1 0
fi

file -b "${msIso}" | grep -q "ISO 9660 CD-ROM filesystem"
retVal=$?
if (( ${retVal} != 0 )); then
	reportError "${msIso} is not an ISO file"
	programAbort 1 0
fi

isoOutFile=$(basename "${msIso}" .iso)
isoOutFile="./${isoOutFile}-vmware.iso"
 
#---------------
# Normal processing
#---------------
	
freeSpace=$(df -g "$tempDir" | awk '/^\/dev/ {print $4}' ) 

if (( freeSpace < minDiskSpace )) ; then
	reporError "$0 requires $minDiskSpace GB of free disk space in the current working folder\n\tand you have \n$freeSpace GB remaining."
	programAbort 1 0
fi

wDir=$(mktemp -q -d "${tempDir}/esd2iso_temp.XXXXXX")
retVal=$?
if (( $retVal != 0 )); then
	reportError "Unable to create temp directory, error code ${retVal}"
	programAbort $retVal 0
fi

copyIso2Workdir
retVal=$?
if (( $retVal != 0 )); then 
		programAbort $retVal 1
fi
	
copyDrivers
retVal=$?
if (( $retVal != 0 )); then
	programAbort $retVal 1
fi
	


buildIso
retVal=$?
if (( $retVal != 0 )); then
	programAbort $retVal 1
fi
echo -e "\nCleaning up..."
rm -rf "${wDir}"
echo -e "All done!"
echo
echo "Your new Windows ISO with VMware drivers is ${isoOutFile}"
exit 0
