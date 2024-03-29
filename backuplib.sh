#!/bin/sh

function prepareDatabase()
# external_need: exclusions
# $1 = ls method to use: either 1 or 2
# $2 = currentFolder\
# $3 = folderDb
# $4 = exclusionFilter
# $5 = diskPath
# $6 = baseDir
{
	addLog "D" "-->function prepareDatabase"
	# Parameters
	local lsMethod="$1"
	local currentFolder="$2"
	local folderDb="$3"
	local exclusionFilter="$4"
	local diskPath="$5"
	local baseDir="$6"
	
	local lastDir=$(cutPath1FromPath2 "$baseDir" "$currentFolder")
	
	addLog "D" "BaseDir=$baseDir"
	addLog "D" "CurrentFolder=$currentFolder"
	addLog "D" "LastDir=$lastDir"
	addLog "D" "DiskPath=$diskPath"
	
	## List existing USB disk files of current folder
	printf "" > "$folderDb.usb-fetch-1"
	if [ -d "$diskPath/$lastDir" ]; then
		if [ $lsMethod -eq 1 ]; then
			executeAndFilterErrors "${errorsToFilter[@]}" "ls -lLAesR \"$diskPath/$lastDir\" >\"$folderDb.usb-fetch-1\""
		else
			# Columns of "ls" shall be SizeInBlock Rights User Group Size MonthAsThreeLetters DayOfMonth Time(HH:mm:ss) Year FileName
			executeAndFilterErrors "${errorsToFilter[@]}" "ls -lLAsR --time-style=\"+%b %d %H:%M:%S %Y\" \"$diskPath/$lastDir\" >\"$folderDb.usb-fetch-1\""
		fi
	fi

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
	local awkRearrange='{
		if ($0 ~ /^\/.*:$/)
		{
			# Line of folder
			path=$0;
			sub(/:$/, "", path);
		}
		else if (!($0 ~ /^total/) && $0 != "")
		{
			# Line of entry in the folder
			setDateAndFileName();
			
			fileDiskSize=$1;
			fileSize=$6;
			fileKey=path "/" fileName;
			gsub(" ", "_", fileKey);
			entryExtraInfo=substr($2, 1, 1);
			
			print fileKey" "entryExtraInfo" "fileDiskSize" "fileSize" "fileDate" "path"/"fileName;
		}
		}'
	if [ $lsMethod -eq 1 ]; then
		local awkSetDateAndFileName='
			function setDateAndFileName()
			{
				fileDate=$8" "$9" "$10" "$11;
				fileName=$0;
				gsub(/^ *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* /, "", fileName);
			}
			'
	else
		# Columns of "ls" shall be SizeInBlock Rights User Group Size MonthAsThreeLetters DayOfMonth Time(HH:mm:ss) Year FileName
		local awkSetDateAndFileName='
			function setDateAndFileName()
			{
				fileDate=$7" "$8" "$9" "$10;
				fileName=$0;
				gsub(/^ *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* *[^ ]* /, "", fileName);
			}
			'
	fi
	awkRearrange="$awkRearrange $awkSetDateAndFileName"
	awk "$awkRearrange" "$folderDb.fetch-2" > "$folderDb.fetch-3"
	awk "$awkRearrange" "$folderDb.usb-fetch-1" > "$folderDb.usb-fetch-2"
	
	## Replace $diskPath by $currentFolder in "usb-fetch-2" file
	cat "$folderDb.usb-fetch-2" | sed -E "s|([^ ]+)([^/]+)$diskPath|\1\2$baseDir|" > "$folderDb.usb-fetch-3"
	
	## Remove not desired entries
	if [ ! "$exclusionFilter" = "" ]; then
		addLog "N" "Using filter: $exclusionFilter"
		cat "$folderDb.fetch-3" | sed -E "s/^.*$exclusionFilter.*$//" | sed '/^$/d' > "$folderDb.fetch-4"
	else
		cp "$folderDb.fetch-3" "$folderDb.fetch-4"
	fi
	
	addLog "N" "Rearranging done"
	
	## Replace entry key by sha1 of file path
	if [ ! -f "$folderDb.hash" ]; then
		touch "$folderDb.hash"
	fi
	local awkGetFile='
		function getFile(nbMetaInfoColumns)
		{
			metaInfoLength=0
			for (i=1; i<=nbMetaInfoColumns; i++)
			{
				metaInfoLength += length($i) + 1;
			}
			return substr($0,metaInfoLength + 1);
		}
		'
	# Ref: https://stackoverflow.com/a/27931082/214898
	local awkHashReplacement='{
		if (FILENAME ~ /\.hash$/)
		{
			curFile=getFile( 1 );
			h[curFile]=$1;
		}
		else
		{
			curFile=getFile( 8 );
			if (curFile in h)
			{
				hash=h[curFile];
			}
			else
			{
				curFileEscaped=curFile
				gsub(/'"'"'/, "'"'\\\"'\\\"'"'", curFileEscaped); # Replacement of single quotes
				command = ("echo \047" curFileEscaped "\047 | sha1sum -b | cut -d\\  -f 1");
				command | getline hash;
				close(command);
				hash="/" hash
			}
			print hash " " $2 " " $3 " " $4 " " $5 " " $6 " " $7 " " $8 " " curFile; #Not using $0 because if curFile contains double spaces, it is replaced by one
		}
		}'"$awkGetFile"
	awk "$awkHashReplacement" "$folderDb.hash" "$folderDb.fetch-4" > "$folderDb.size"
	awk "$awkHashReplacement" "$folderDb.hash" "$folderDb.usb-fetch-3" > "$folderDb.usb-size"
	
	# Save already computed hash
	local awkHashSaving='{
		curFile=getFile(8);
		print $1 " " curFile;
		}'"$awkGetFile"
	awk "$awkHashSaving" "$folderDb.size" > "$folderDb.hash"
	awk "$awkHashSaving" "$folderDb.usb-size" >> "$folderDb.hash"
	
	addLog "N" "Hashing done"
	
	## Prepare DB files for comparison
	sort -f -k 9.1 "$folderDb.size" > "$folderDb.size-s"
	sort -f -k 9.1 "$folderDb.usb-size" > "$folderDb.toverify"

	if [ ! -f "$folderDb.list" ]; then
		touch "$folderDb.list"
	fi

	sort -f -k 9.1 "$folderDb.list" > "$folderDb.list-s"

	# Get differences between size-s and list-s
	diff -u "$folderDb.size-s" "$folderDb.list-s" > "$folderDb.size-diff"

	# Keep the ones that differ from .list (files not copied & modified ones)
	awk '{
		if (FNR == NR) 
		{
			if (substr($0,1,2) == "+/")
			{
				a[substr($1,2)]=$0;
			}
		}
		else if (substr($0,1,2) == "-/" && ($3 * 1024) >= $4)
		{
			if (substr($1,2) in a) 
			{
				gsub(" "$5" ", " |"$5" ");
			}
			print substr($0,2);
		}
		}' "$folderDb.size-diff" "$folderDb.size-diff" > "$folderDb.tocopy"
	
	addLog "N" "Files comparison done"
	addLog "D" "<--function prepareDatabase"
}

function verifyFiles()
# $1 = baseDir
# $2 = folderDb
# $3 = diskPath
# $4 = foundDiskName
# $5 = globalList list file that contains all folders
# $6 = removeFiles
# $7 = reconstructDb
{
	addLog "D" "-->function verifyFiles"

	# Parameters
	local baseDir="$1"
	local folderDb="$2"
	local diskPath="$3"
	local foundDiskName="$4"
	local globalList="$5"
	local removeFiles="$6"
	local reconstructDb="$7"
	
	## Loop through files to delete and ensure it doesn't exist anymore in backup folder (and if so, delete the file on USB disk)
	local line elementToVerify toEnsure toEnsureDiskSize elementToVerifyKey elementToVerifyKeyEscaped toEnsureDate listLine
	if [ "$removeFiles" = "Y" ]; then
		while IFS='' read -r line || [[ -n "$line" ]]; do
			toEnsure=$(echo "$line" | sed 's|^[^ ]* [^/]*||')
			elementToVerify=$(echo "$toEnsure" | sed "s|^$baseDir|$diskPath|")
			toDisplay=$(echo "$toEnsure" | sed "s|^$baseDir||")
			elementToVerifyKey=$(echo "$line" | awk '{print $1}')
			elementToVerifyKeyEscaped=$(escapeForRegEx "$elementToVerifyKey")
			
			addLog "D" "Line=$line"
			addLog "D" "ElementToVerify=$elementToVerify"
			addLog "D" "ToEnsure=$toEnsure"
			addLog "D" "ElementToVerifyKey=||$elementToVerifyKey||"
					
			if [ ! -f "$toEnsure" ] && [ ! -d "$toEnsure" ] && ([ -f "$elementToVerify" ] || [ -d "$elementToVerify" ]) ; then
				# Delete file or folder from USB disk
				addLog "N" "Deleting on disk \"$foundDiskName\" : $toDisplay"
				
				rm -rf "$elementToVerify"
			fi
			if [ ! -f "$toEnsure" ] && [ ! -d "$toEnsure" ]; then
				# Remove entry from list file. It is done appart the first IF because if a folder is deleted, then the files underneath wouldn't be removed from the list file.
				addLog "D" "Removed from list file"
				
				sed -i "/^$elementToVerifyKeyEscaped /d" "$folderDb.list"
				sed -i "/^$foundDiskName:$elementToVerifyKeyEscaped /d" "$globalList"
			fi
		done < "$folderDb.toverify"
	fi
	
	## Reconstruct database using USB disk files
	if [ "$reconstructDb" = "Y" ]; then
		awk '{
			if (FILENAME ~ /\.size$/)
			{
				# build array of keys from size file
				a[$1]=$0;
			}
			else if (FILENAME ~ /\.list$/)
			{
				# build array of keys from list file
				b[$1]="a"; # value is not used
			}
			else if ($1 in a && !($1 in b))
			{
				split(a[$1],sizeInfo," ");
				shallPrint=1
				entryType=substr($2, 1, 1)
				if (entryType != "d")
				{
					# Compare meta information to determinate if the file is the same (starting at position 4 to skip the key, entry extra infos and disk size)
					for(i=4; i<=8; i++)
					{
						if ($i != sizeInfo[i]) {
							shallPrint=0;
							break;
						}
					}
				}
				if (shallPrint == 1)
				{
					print a[$1];
				}
			}
			}' "$folderDb.size" "$folderDb.list" "$folderDb.toverify" > "$folderDb.list-r"
		
		reconstructDbContentSize=$(stat -c %s "$folderDb.list-r" 2>/dev/null)
		if [ "$reconstructDbContentSize" != "" ] && [ "$reconstructDbContentSize" -gt 0 ]; then
			# Add reconstruct DB to list files
			cat "$folderDb.list-r" >> "$folderDb.list"
			awk "{print \"$foundDiskName\" \":\" \$0;}" "$folderDb.list-r" >> "$globalList"
			# Remove from files to be copied/rsync
			awk '{
				if (FILENAME ~ /\.list\-r$/)
				{
					# build array of keys from size file
					a[$1]=$0;
				}
				else if (!($1 in a))
				{
					print $0;
				}
				}' "$folderDb.list-r" "$folderDb.tocopy" >> "$folderDb.tocopy-r"
			rm "$folderDb.tocopy"
			mv "$folderDb.tocopy-r" "$folderDb.tocopy"
		fi
		rm "$folderDb.list-r"
	fi
	
	addLog "D" "<--function verifyFiles"
}

function copyFiles()
# $1 = currentFolder
# $2 = folderDb
# $3 = diskPath
# $4 = foundDiskName
# $5 = fullRangeMin
# $6 = baseDir
# $7 = globalList list file that contains all folders
# $8 = fullRangeMax
{
	addLog "D" "-->function copyFiles"
	# Parameters
	local currentFolder="$1"
	local folderDb="$2"
	local diskPath="$3"
	local foundDiskName="$4"
	local fullRangeMin="$5"
	local baseDir="$6"
	local globalList="$7"
	local fullRangeMax="$8"

	## For each elements to copy
	## - Ensure not a folder
	## - Check if enough space to copy on disk and would still be over FULL-RANGE-MIN after copy
	## - Copy on disk
	## - Add to the .list
	local lastDir=$(cutPath1FromPath2 "$baseDir" "$currentFolder")
	local fullRangeMinInKB=$(($fullRangeMin << 10))
	local fullRangeMaxInKB=$(($fullRangeMax << 10))
	
	local elementToCopyKey elementToCopyDiskSize elementToCopyHasChanged elementToCopy
	local line leftSpace=0 fileName pathEnd toFile toFileSize toFileDiskSize
	local triedToCopy=1 backupResult
	while IFS='' read -r line || [[ -n "$line" ]]; do
		if [ "$line" = "" ]; then
			continue
		fi
		
		elementToCopyKey=$(echo "$line" | awk '{print $1}')
		elementToCopyExtraInfos=$(echo "$line" | awk '{print $2}')
		elementToCopyDiskSize=$(echo "$line" | awk '{print $3}')
		elementToCopySize=$(echo "$line" | awk '{print $4}')
		elementToCopyHasChanged=$(echo "$line" | awk '{print $5}' | sed 's/[A-Za-z]//g')
		if [ "$elementToCopyHasChanged" = "" ]; then
			elementToCopyHasChanged=0
		else
			elementToCopyHasChanged=1
		fi
		
		elementToCopy=$(echo "$line" | sed 's|^[^ ]* [^/]*||')
		line=$(echo "$line" | sed 's/|//')
		
		addLog "D" "ElementToCopy=$elementToCopy"
		addLog "D" "Line=$line"
		addLog "D" "ElementToCopyKey=$elementToCopyKey"
		addLog "D" "ElementToCopySize(s)=$elementToCopySize||$elementToCopyDiskSize||$elementToCopyHasChanged"
		
		if [ -d "$elementToCopy" ]; then
			addLog "D" "Adding folder to list file"
		
			# If it is a folder, then only add it to the file list so it doesn't take any useless space on the backup disk
			if [ "$elementToCopyHasChanged" = "1" ]; then
				sed -i "\|^$elementToCopyKey |d" "$folderDb.list"
				sed -i "\|^$foundDiskName:$elementToCopyKey |d" "$globalList"
			fi
			echo "$line" >> "$folderDb.list"
			echo "$foundDiskName:$line" >> "$globalList"
		else
			# If it is a file, then backup if needed
			ensureDiskConnected "$diskPath" "$foundDiskName"
			addLog "N" "To copy : $elementToCopy"
			
			# Set path of "copying to" file
			fileName=$(echo "$elementToCopy" | awk -F "/" '{print $NF}')
			pathEnd=$(dirname "$elementToCopy")
			if [ "$pathEnd" = "$currentFolder" ]; then
				pathEnd=""
			else
				pathEnd=$(echo "$pathEnd" | sed "s|^$currentFolder/||")
				pathEnd="$pathEnd/"
			fi
			
			toFile="$diskPath/$lastDir/$pathEnd$fileName"
			toFileSize=$(stat -c %s "$toFile" 2>/dev/null)
			toFileDiskSize=0
			if [ "$toFileSize" != "" ]; then
				toFileDiskSize=$(du "$toFile" | awk '{print $1}')
			fi
			
			# Get space left on USB disk and stop backup if no more space and no DB reconstruction
			leftSpace=$(getDiskFreeSpace "$diskPath")
			addLog "D" "LeftSpace=$leftSpace"
			addLog "D" "FullRangeMin=$fullRangeMin"
			addLog "D" "FullRangeMinInKB=$fullRangeMinInKB"
			addLog "D" "FullRangeMax=$fullRangeMax"
			addLog "D" "FullRangeMaxInKB=$fullRangeMaxInKB"
			
			if [ "$leftSpace" -ge "$fullRangeMinInKB" ] && [ "$leftSpace" -le "$fullRangeMaxInKB" ]; then
				addLog "D" "Stop copy because disk is full"
				break
			fi
			
			leftSpace=$((($leftSpace) - ($fullRangeMinInKB) - ($elementToCopyDiskSize) + ($toFileDiskSize))) # All sizes have to be in kilobytes
			addLog "D" "LeftSpaceAdjusted=$leftSpace"
			
			# Echo debug informations
			addLog "D" "CopyingFrom=$elementToCopy"
			addLog "D" "CopyingTo=$toFile"
			addLog "D" "DiskPath=$diskPath"
			addLog "D" "CurrentFolder=$currentFolder"
			addLog "D" "LastDir=$lastDir"
			addLog "D" "PathEnd=$pathEnd"
			addLog "D" "FileName=$fileName"
			addLog "D" "ToFileSize=$toFileSize"
			
			# Rsync / copy file
			triedToCopy=0
			if ([ "$toFileSize" = "$elementToCopySize" ] && [ "$leftSpace" -le 0 ]) || ([ -f "$toFile" ] && [ "$leftSpace" -gt 0 ]); then
				# if same file size and no more space, try rsynch to ensure same file so it will be added to the "list" file
				# or if still free space for the file and the file already exists
				triedToCopy=1
				addLog "N" "Synchronizing : $toFile"
				rsync -a --no-compress "$elementToCopy" "$toFile"
				backupResult="$?"
			elif [ "$leftSpace" -gt 0 ]; then
				# if file doesn't exist and still free space for the file
				triedToCopy=1
				addLog "N" "Copying : $toFile"
				mkdir -p "$diskPath/$lastDir/$pathEnd" # Create toFolder only if copying the file, otherwise it would fill the USB disk with empty folders
				cp -a "$elementToCopy" "$toFile"
				backupResult="$?"
			elif [ -f "$toFile" ]; then
				# if file exists, not the same size and missing space to rsync it
				addLog "N" "Removing due to file change, but missing space on USB disk : $toFile"
				rm "$toFile"
			fi
			
			# If tried to rsync/copy the file, then upon success or failure act accordingly
			if [ $triedToCopy -eq 1 ] && [ "$backupResult" -eq "0" ]; then
				if [ "$elementToCopyHasChanged" = "1" ]; then
					# Remove current entry in the list file because of some changes (size, date)
					sed -i "\|^$elementToCopyKey |d" "$folderDb.list"
					sed -i "\|^$foundDiskName:$elementToCopyKey |d" "$globalList"
				fi
				# Add rsync/copy file to the list file
				echo "$line" >> "$folderDb.list"
				echo "$foundDiskName:$line" >> "$globalList"
			elif [ $triedToCopy -eq 1 ]; then
				# Remove the copied file upon failure
				rm "$toFile"
				addLog "E" "Error - copy/rsync exit code: $backupResult"
			fi
		fi
	done < "$folderDb.tocopy"
	
	addLog "D" "<--function copyFiles"
}

function cutPath1FromPath2()
# $1 = path1
# $2 = path2
{
	local path1="$1"
	local path2="$2"
	
	local dir1Length=$(echo "$path1" | wc -c)
	dir1Length=$(($dir1Length + 1))
	local cutPath=$(echo "$path2" | cut -c $dir1Length-)
	echo $cutPath
}

function ensureDisk()
# Try to find one and only one USB disk connected starting with $1
# $1 = Disk name starting with
# $2 = Database path
# external_set: diskPath, foundDiskName
{
	# External variables that will be set
	diskPath=""
	foundDiskName=""

	# Parameters
	local wantDiskName="$1"
	local dbDir="$2"

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
		addLog "N" "$mailMessage" # Not considered as an error so the email used is not the one for errors
		sendMail "N" "QNAP - Missing disk" "$mailMessage"
		exit
	fi

	if [ $foundDiskCount -ne 1 ]; then
		local mailMessage="More than one USB disk found starting with name $wantDiskName"
		addLog "N" "$mailMessage" # Not considered as an error so the email used is not the one for errors
		sendMail "N" "QNAP - More than one disk" "$mailMessage"
		exit
	fi

	## Verify if no error on disk
	local diskErrorFile="$dbDir/$wantDiskName..check"
	ls -R "$diskPath/" 1> /dev/null 2> "$diskErrorFile"
	local isError=$(ls -s "$diskErrorFile" | awk '{print $1}')
	if [ ! "$isError" = "0" ]; then
		local mailMessage="Disk $foundDiskName has errors. Please do a file verification."
		addLog "E" "$mailMessage"
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
	
	if [ "$mountExists" = "" ] || [ "$writePossible" = "" ]; then
		addLog "E" "Disk $diskName disconnected or impossible to write a test file"
		exit
	fi
	
	rm -rf "$testingFile" 2>/dev/null # Skip error once
	if [ $? -ne 0 ]; then
		rm -rf "$testingFile" 2>/dev/null
		addLog "E" "Disk $diskName disconnected or impossible to delete the test file"
		exit
	fi
}

