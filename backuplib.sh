#!/bin/sh


function ensureDisk()
# Try to find one and only one USB disk connected starting with $1
# $1 = Disk name starting with
# external_set: diskPath, foundDiskName
{
	# External variables that will be set
	diskPath=""
	foundDiskName=""

	# Parameters
	local wantDiskName="$1"

	## Look if needed disk is connected (and only one !) and get its mounted path
	local mountedDisks=$(mount -l | grep /share/external/ | grep /dev/sd)
	IFS=$'\n' read -rd '' -a mountedDisks2 <<< "$mountedDisks"

	local foundDiskCount=0
	local step=0
	for i in ${mountedDisks2[@]}; do
		if [[ $step -eq 2 ]]; then
			diskPath=$i
			step=0
		fi
		if [[ $step -eq 1 ]]; then
			step=2
		fi
		
		if [[ $i = \/dev\/* ]] ; then
			local diskName=$(blkid -s LABEL -o value $i)
			if [[ "$diskName" = $wantDiskName* ]]; then
				foundDiskName=$diskName
				foundDiskCount=$((foundDiskCount+1))
				step=1
			fi
		fi
	done
	
	addLog "D" "FoundDiskName=$foundDiskName"

	if [ $foundDiskCount -eq 0 ]; then
		local mailMessage="No USB disk found starting with name $wantDiskName"
		echo "$mailMessage"
		sendMail "N" "QNAP - Missing disk" "$mailMessage"
		exit
	fi

	if [ $foundDiskCount -ne 1 ]; then
		local mailMessage="More than one USB disk found starting with name $wantDiskName"
		echo "$mailMessage"
		sendMail "N" "QNAP - More than one disk" "$mailMessage"
		exit
	fi

	## Verify if no error on disk
	local diskErrorFile="$dbDir/$wantDiskName..check"
	ls -R "$diskPath/" 1> /dev/null 2> "$diskErrorFile"
	local isError=$(ls -s "$diskErrorFile" | awk '{print $1}')
	if [ ! "$isError" = "0" ]; then
		local mailMessage="Disk $foundDiskName has errors. Please do a file verification."
		echo "$mailMessage" >&2
		sendMail "Y" "QNAP - Disk having errors" "$mailMessage"
		exit
	fi
	
	addLog "N" "Will backup on $diskPath named $foundDiskName"
}

function ensureDiskConnected()
# $1 = disk path
# $2 = disk name
{
	local diskPath="$1"
	local testingFile="$diskPath/test.testing$.$test"
	local mountExists=$(mount -l | grep $diskPath)
	local writePossible=$(echo "Y" > "$testingFile" && echo "1")
	
	###TODO: Shall not exit but return 1 if failing and 0 if success and the callee shall stop what it is doing to be able to send an error email
	if [ "$mountExists" = "" ] || [ "$writePossible" = "" ]; then
		echo "Disk $diskName disconnected or impossible to write a test file" >&2
		exit
	fi
	
	rm -rf "$testingFile" 2>/dev/null # Skip error once
	if [ $? -ne 0 ]; then
		rm -rf "$testingFile" 2>/dev/null
		echo "Disk $diskName disconnected or impossible to delete the test file" >&2
		exit
	fi
}

function getDiskFreeSpace()
# $1 = disk path to get free space
{
	local diskPath="$1"
	local diskSpaceLine2
	local diskSpaceLine=$(df -m $diskPath)
	IFS=' ' read -rd '' -a diskSpaceLine2 <<< "$diskSpaceLine"
	local freeSpace=$((${diskSpaceLine2[7]} - ${diskSpaceLine2[8]}))
	
	echo $freeSpace
}