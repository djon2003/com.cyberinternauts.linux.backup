#!/bin/sh

function prepareDatabase()
# external_need: exclusions
# $1 = ls method to use: either 1 or 2
# $2 = currentFolder\
# $3 = folderDb
# $4 = exclusionFilter
{
	# Parameters
	local lsMethod="$1"
	local currentFolder="$2"
	local folderDb="$3"
	local exclusionFilter="$4"

	## List files/subfolders to backup
	local errorsToFilter=("${exclusions[@]}")
	if [ $lsMethod -eq 1 ]; then
		executeAndFilterErrors "${errorsToFilter[@]}" "ls -lLAesR \"$currentFolder\" >\"$folderDb.fetch-1\""
	else
		# Columns of "ls" shall be SizeInBlock Rights User Group Size MonthAsThreeLetters DayOfMonth Time(HH:mm:ss) Year FileName
		executeAndFilterErrors "${errorsToFilter[@]}" "ls -lLAsR --time-style=\"+%b %d %H:%M:%S %Y\" \"$currentFolder\" >\"$folderDb.fetch-1\""
	fi
	
	addLog "N" "Listing done"
	
	## Remove symbolic links
	cat "$folderDb.fetch-1" | grep -v "^[ ]*[0-9]\+[ ]\+l" > "$folderDb.fetch-2"
	
	## Rearrange file output to have a usable one
	if [ $lsMethod -eq 1 ]; then
		cat "$folderDb.fetch-2" | awk '/:$/&&f{s=$0;f=0}/:$/&&!f{sub(/:$/,"");s=$0;f=1;next}NF&&f{ sd=$1; sr=$6; dd=$8" "$9" "$10" "$11; gsub(/^ *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* /,"");mm=$0; ff=s"/"mm; $0=ff; gsub(" ","_"); print $0" "sd" "sr" "dd" "ff}' > "$folderDb.fetch-3"
	else
		# Columns of "ls" shall be SizeInBlock Rights User Group Size MonthAsThreeLetters DayOfMonth Time(HH:mm:ss) Year FileName
		cat "$folderDb.fetch-2" | sed '/^total/ d' | awk '/:$/&&f{s=$0;f=0}/:$/&&!f{sub(/:$/,"");s=$0;f=1;next}NF&&f{ sd=$1; sr=$6; dd=$7" "$8" "$9" "$10; gsub(/^ *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* /,"");mm=$0; ff=s"/"mm; $0=ff; gsub(" ","_"); print $0" "sd" "sr" "dd" "ff}' > "$folderDb.fetch-3"
	fi

	## Remove not desired folders
	if [ ! "$exclusionFilter" = "" ]; then
		addLog "N" "Using filter: $exclusionFilter"
		cat "$folderDb.fetch-3" | sed -E "s/^.*$exclusionFilter.*$//" | sed '/^$/d' > "$folderDb.size"
	else
		cp "$folderDb.fetch-3" "$folderDb.size"
	fi
	
	addLog "N" "Rearranging done"
	
	## Prepare DB files for comparison
	sort "$folderDb.size" > "$folderDb.size-s"

	if [ ! -f "$folderDb.list" ]; then
		touch "$folderDb.list"
	fi

	sort "$folderDb.list" > "$folderDb.list-s"

	if [ ! -f "$folderDb.size-old-s" ]; then
		touch "$folderDb.size-old-s"
	fi

	## Compare new and old lists (new files are considered only the second time the script is executed in case the file is currently beeing downloaded)
	#Get changes between .size-old-s & .size-s
	diff "$folderDb.size-s" "$folderDb.size-old-s" | grep "<" | sed 's/^< *//' > "$folderDb.size-diff"
	#Keep only the ones from .list
	awk 'FNR==NR {a[$1]=$0; gsub(" "$4" ", " |"$4" "); b[$1] = $0; next}; $0 != a[$1] && $1 in a {print b[$1]}' "$folderDb.size-diff" "$folderDb.list-s" | sed '/^$/d' > "$folderDb.size-diff-diff"

	# Get no changes between .size-old-s & .size-s (files completed)
	diff "$folderDb.size-s" "$folderDb.size-diff" | grep "<" | sed 's/^< *//' > "$folderDb.size-same"

	# Keep the ones that differ from .list
	diff "$folderDb.size-same" "$folderDb.list-s" > "$folderDb.size-same-diff0"
	awk 'FNR==NR && $1 == ">" {a[$2]=$0; next}; FNR==NR {next}; $1 == "<" && $2 in a {gsub(" "$5" ", " |"$5" "); print $0; next}; $1 == "<" {print $0}' "$folderDb.size-same-diff0" "$folderDb.size-same-diff0" | sed 's/^[<>] //' | sed '/^$/d' > "$folderDb.size-same-diff"
	
	# Combine changes
	cp "$folderDb.size-same-diff" "$folderDb.size-changes"
	cat "$folderDb.size-diff-diff" >> "$folderDb.size-changes"
	sort "$folderDb.size-changes" > "$folderDb.size-changes-s"
	
	# Create list of files to copy and ensure the files are complete
	awk '($2 * 1024) >= $3 {print $0;}' "$folderDb.size-changes-s" > "$folderDb.tocopy"
	
	# Copy .size-s over .size-old-s
	cp "$folderDb.size-s" "$folderDb.size-old-s"
	
	addLog "N" "Files comparison done"
}

function copyFiles()
# $1 = currentFolder
# $2 = folderDb
# $3 = diskPath
# $4 = foundDiskName
# $5 = fullRangeMin
# external_out: continueNextFolder
{
	local currentFolder="$1"
	local folderDb="$2"
	local diskPath="$3"
	local foundDiskName="$4"
	local fullRangeMin="$5"

	## For each elements to copy
	## - Ensure not a folder
	## - Check if enough space to copy on disk and would still be over FULL-RANGE-MIN after copy
	## - Copy on disk
	## - Add to the .list
	local lastDir=$(echo "$currentFolder" | awk -F "/" '{print $NF}')
	local elementToCopyKey elementToCopySize elementToCopyHasChanged elementToCopy line leftSpace=0 fileName pathEnd
	while IFS='' read -r line || [[ -n "$line" ]]; do
		if [ "$line" = "" ]; then
			continue
		fi
		
		elementToCopyKey=$(echo "$line" | awk '{print $1}')
		elementToCopySize=$(echo "$line" | awk '{print $2}')
		elementToCopyHasChanged=$(echo "$line" | awk '{print $4}' | sed 's/[A-Za-z]//g')
		if [ "$elementToCopyHasChanged" = "" ]; then
			elementToCopyHasChanged=0
		else
			elementToCopyHasChanged=1
		fi
		
		elementToCopy=$(echo "$line" | sed 's|^[^ ]* [^/]*||')
		line=$(echo "$line" | sed 's/|//')
		
		addLog "D" "||E=$elementToCopy||"
		addLog "D" "||L=$line||"
		addLog "D" "||EK=$elementToCopyKey||"
		addLog "D" "||ES=$elementToCopySize||$elementToCopyHasChanged||"
		
		if [ -d "$elementToCopy" ]; then
			if [ "$elementToCopyHasChanged" = "1" ]; then
				sed "\|^$elementToCopyKey |d" "$folderDb.list" > "$folderDb.list2"
				cp "$folderDb.list2" "$folderDb.list"
			fi
			echo "$line" >> "$folderDb.list"
		else
			ensureDiskConnected "$diskPath" "$foundDiskName"

			addLog "N" "To copy : $elementToCopy"
			leftSpace=$(getDiskFreeSpace "$diskPath")
			addLog "D" "||LS=$leftSpace||"
			leftSpace=$((($leftSpace << 10) - ($elementToCopySize) - ($fullRangeMin << 10)))
			addLog "D" "||LS=$leftSpace||"
			
			if [ "$leftSpace" -gt 0 ]; then
				fileName=$(echo "$elementToCopy" | awk -F "/" '{print $NF}')
				pathEnd=$(dirname "$elementToCopy")
				if [ "$pathEnd" = "$currentFolder" ]; then
					pathEnd=""
				else
					pathEnd=$(echo "$pathEnd" | sed "s|^$currentFolder/||")
					pathEnd="$pathEnd/"
				fi
				
				mkdir -p "$diskPath/$lastDir/$pathEnd"
				addLog "N" "Copying : $diskPath/$lastDir/$pathEnd$fileName"
				addLog "D" "CopyingFrom=$elementToCopy"
				addLog "D" "CopyingTo=$diskPath/$lastDir/$pathEnd$fileName"
				addLog "D" "DiskPath=$diskPath"
				addLog "D" "LastDir=$lastDir"
				addLog "D" "PathEnd=$pathEnd"
				addLog "D" "FileName=$fileName"
				if [ -f "$diskPath/$lastDir/$pathEnd$fileName" ]; then
					rsync -a --no-compress "$elementToCopy" "$diskPath/$lastDir/$pathEnd$fileName"
				else
					cp -a "$elementToCopy" "$diskPath/$lastDir/$pathEnd$fileName"
				fi
				if [ "$?" -eq "0" ]; then
					if [ "$elementToCopyHasChanged" = "1" ]; then
						sed "\|^$elementToCopyKey |d" "$folderDb.list" > "$folderDb.list2"
						cp "$folderDb.list2" "$folderDb.list"
					fi
					echo "$line" >> "$folderDb.list"
				else
					echo "Error - exit code: $?" >&2
				fi
			else
				break
			fi
		fi
	done < "$folderDb.tocopy"
	
	if [ ! "$leftSpace" -gt 0 ]; then
		continueNextFolder=1
	fi
	
	continueNextFolder=0
}


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

