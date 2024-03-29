#!/bin/sh


## Load base library
scriptDir=$(dirname "$BASH_SOURCE")
source "$scriptDir/com.cyberinternauts.linux.libraries/baselib.sh"
source "$scriptDir/backuplib.sh"


## Ensure softwares needed exist, if so update it if necessary
isOpkgExisting=$(isProgramExist "opkg")
isDiffExisting=$(isProgramExist "diff")
if [ "$isDiffExisting" = "N" ]; then
	if [ "$isOpkgExisting" = "N" ]; then
		###TODO: The subdomain is not accessible anymore. Sent a message via http://www.zyxmon.org/kontakty/
		## The specific architecture here (in the URL) doesn't matter because the script manage it
		installScript=$(wget -O - http://entware.zyxmon.org/binaries/armv5/installer/entware_install.sh)
		if [ "$?" != "0" ]; then
			addLog "E" "Not able to download OPKG installer"
			exit
		fi
		/bin/sh <<< "$installScript"
	fi
	opkg install diffutils
elif [ "$isOpkgExisting" = "Y" ]; then
	opkg update
	opkg upgrade
fi


# Ensure "diff" exists (in case the download failed before)
ensureProgramExist "diff"

## Ensure launched only once
launchOnlyOnce

# Switch to script directory
switchToScriptDirectory

#### #### #### #### #### #### #### ####
## Base variables definitions
#### #### #### #### #### #### #### ####

defaultBaseDir="/share/homes"
declare -a params_needed
params_needed=("DISK" "FULL-RANGE" "EMAIL")
sentErrorMail="N"

#### #### #### #### #### #### #### ####
## Functions definitions
#### #### #### #### #### #### #### ####

function getParamValue()
# Param 1 = ParamKey
# Param 2 = DefaultValue
{
	local value="$2"
	for iK in ${!params_keys[@]}; do
		i=${params_keys[$iK]}
		if [ "$i" = "$1" ]; then
			value=${params_values[$iK]}
		fi
	done
	echo $value
}

renameFunction sendMail __sendMail
function sendMail()
# $1 = is this an error (Value "Y" means yes, all others mean no)
# $2 = email object
# $3 = email content
# $4 = attachmentFile
{
	local isError=$1
	if [ "$isError" = "Y" ]; then
		sentErrorMail="Y"
	else
		isError=""
	fi
	local emailObject=$2
	local emailContent=$3
	local attachmentFile=$4
	local email=$(getParamValue "EMAIL")
	local errorEmail=$(getParamValue "ERROR-EMAIL" "$email")
	
	if [ "$isError" != "" ]; then
		email="$errorEmail"
	fi
	
	if [ "$email" = "" ]; then
		return
	fi
	
	__sendMail "$emailObject" "$email" "$email" "$emailContent" "$attachmentFile"
}

function sendErrorMailOnExit()
{
	if [ "$sentErrorMail" = "Y" ]; then
		# Already sent email about the error
		return
	fi

	###TODO: When logs are set to BOTH, this code doesn't work because FD#3 is pointing to STDOUT. See my question: https://stackoverflow.com/questions/70836246/ . I use the "fake" FD#4 to make it work. If no new solution after a month. Remove this TODO. 
	## If errors happened, then send email
	local isFileDescriptor4Exist=$(command 2>/dev/null >&4 && echo "Y")
	if [ "$isFileDescriptor4Exist" = "Y" ]; then
		local logFile=$(readlink /proc/self/fd/4 | sed s/.log$/.err/)
		local logFileSize=$(stat -c %s "$logFile" 2>/dev/null)
		if [ "$logFileSize" -gt 0 ]; then
			addLog "N" "Sending error email"
			local logFileName=$(basename "$logFile")
			local logFileContent=$(cat "$logFile")
			sendMail "Y" "QNAP - Backup error" "Error happened on backup. See log file $logFileName"$'\n\nLog error file content:\n'"$logFileContent"
		fi
	fi
}
trap sendErrorMailOnExit EXIT


#### #### #### #### #### #### #### ####
## Execution of script
#### #### #### #### #### #### #### ####

addLog "N" "Backup started"

fileName=$1

if [ "$#" -eq 0 ]; then
	addLog "E" "Backup shall be called with a configuration filename"
	exit
fi

if [ ! -f "$fileName" ]; then
	addLog "E" "Configuration file doesn't exist : $fileName"
	exit
fi

## Create data directory
dbDir=$(pwd)/.backup.db

if [ ! -d $dbDir ]; then
	mkdir $dbDir
fi

## Read configuration file
addLog "N" "Reading configuration : $fileName"

# Convert DOS to Unix newline char(s)
confFile=$(echo $fileName | awk -F "/" '{print $NF}')

tmpConf="$dbDir/$confFile.conf"
tr -d '\015' < $fileName > "$tmpConf"
fileName="$tmpConf"

declare -a params_values
declare -a params_keys
declare -a folders
declare -a exclusions
p=0
f=0
e=0

# Read configuration file and transpose it to an array
while IFS='' read -r line || [[ -n "$line" ]]; do
	if [[ ! $line = \#* ]] ; then
		IFS='=' read -r -a sline <<< "$line"
		key="${sline[0]}"
		value="${sline[1]}"
		if [ "$key" = "FOLDER" ]; then
			if [ ! "$value" = "" ]; then
				folders[$f]="$value"
				f=$((f+1))
			fi
		elif [ "$key" = "EXCLUDE" ]; then
			if [ ! "$value" = "" ]; then
				exclusions[$e]="$value"
				e=$((e+1))
			fi
		elif [ ! "$key" = "" ]; then
			params_keys[$p]="$key"
			params_values[$p]="$value"
			p=$((p+1))
		fi
	fi
done < "$fileName"

exclusionFilter=""
if [ ${#exclusions[@]} -ne 0 ]; then
	exclusionFilter="("
	for exclusion in ${exclusions[@]}; do
		exclusion=$(escapeForRegEx "$exclusion")
		if [ ! "$exclusionFilter" = "(" ]; then
			exclusionFilter="$exclusionFilter|"
		fi
		exclusionFilter="$exclusionFilter$exclusion"
	done
	exclusionFilter="$exclusionFilter)"
fi

## Ensure all needed params were found in configuration file
confError=""
for iK in ${!params_needed[@]}; do
	foundKey=0
	valueKey=0
	i=${params_needed[$iK]}
	for kK in ${!params_keys[@]}; do
		k=${params_keys[$kK]}
		if [ "$k" = "$i" ]; then
			valueKey=$kK
			foundKey=1
		fi
	done
	
	if [ $foundKey -eq 0 ]; then
		confError="${confError}Key $i not found in configuration file"$'\n'
	else
		if [ "${params_values[$valueKey]}" = "" ]; then
			confError="${confError}Key $i is empty in configuration file"$'\n'
		fi
	fi
done


## Activate logs
logOutput=$(getParamValue "LOG-OUTPUT" "DISK")
logLevel=$(getParamValue "LOG-LEVEL" "NORMAL")
if [ "$logLevel" != "DEBUG" ] && [ "$logLevel" != "ERRORS" ]; then
	logLevel="NORMAL"
fi
activateLogs "$logOutput"


## Output configuration file errors after logs activation so it can be logged.
if [ "$confError" != "" ]; then
	addLog "E" "$confError"
	sendMail "Y" "Configuration file errors" "Configuration file: $1"$'\n\n'"$confError"
	exit
fi

## Add baseDir to relative folders and ensure each one exists
baseDir=$(getParamValue "BASE-DIR" "$defaultBaseDir")
for i in ${!folders[@]}; do
	value=${folders[$i]}
	if [[ ! "$value" = \/* ]]; then
		value="$baseDir/$value"
	fi
	if [ -d "$value" ]; then
		folders[$i]="$value"
	else
		unset 'folders[i]'
	fi
done


## Ensure at least one folder to synch
if [ ${#folders[@]} -eq 0 ]; then
	mailMessage="No folder set to backup."
	addLog "E" "$mailMessage"
	sendMail "N" "QNAP - Missing folder to backup" "$mailMessage"
	exit
fi

## Ensure USB disk is connected and OK
wantDiskName=$(getParamValue "DISK")
globalList="$dbDir/$wantDiskName..list"
ensureDisk "$wantDiskName" "$dbDir"

## Set FULL-RANGE-MAX and FULL-RANGE-MIN
fullRangeVal=$(getParamValue "FULL-RANGE")
IFS=$'-' read -r -a fullRange <<< "$fullRangeVal"
fullRangeMax=${fullRange[1]}
fullRangeMaxInKB=$(($fullRangeMax << 10))
fullRangeMin=${fullRange[0]}
fullRangeMinInKB=$(($fullRangeMin << 10))

## Choose LS method
lsMethod=2
ls -lLAesR 2>/dev/null
if [ $? -eq 0 ]; then lsMethod=1; fi

## Set REMOVE-FILES
removeFiles=$(getParamValue "REMOVE-FILES" "N")
if [ "$removeFiles" != "Y" ]; then
	removeFiles="N"
fi

## Set RECONSTRUCT-DB
reconstructDb=$(getParamValue "RECONSTRUCT-DB" "N")
if [ "$reconstructDb" != "Y" ]; then
	reconstructDb="N"
fi

## Set DELETE-EMPTY-FOLDERS
deleteEmptyFolders=$(getParamValue "DELETE-EMPTY-FOLDERS" "N")
if [ "$deleteEmptyFolders" != "Y" ]; then
	deleteEmptyFolders="N"
fi

## Ensure global list file exists
if [ ! -f "$globalList" ]; then
	touch "$globalList"
fi

## Loop through folders to backup
for iK in ${!folders[@]}; do
	ensureDiskConnected "$diskPath" "$foundDiskName"

	currentFolder="${folders[$iK]}"
	addLog "N" "Folder $currentFolder"
	folderDb=$(echo "$currentFolder" | tr / .)
	folderDb="$dbDir/$wantDiskName$folderDb"
	
	if [ "$deleteEmptyFolders" = "Y" ]; then
		find "$currentFolder" -type d -empty -delete
	fi
	
	prepareDatabase "$lsMethod" "$currentFolder" "$folderDb" "$exclusionFilter" "$diskPath" "$baseDir"
	
	if [ "$removeFiles" = "Y" ] || [ "$reconstructDb" = "Y" ]; then
		verifyFiles "$baseDir" "$folderDb" "$diskPath" "$foundDiskName" "$globalList" "$removeFiles" "$reconstructDb"
	fi

	copyFiles "$currentFolder" "$folderDb" "$diskPath" "$foundDiskName" "$fullRangeMin" "$baseDir" "$globalList" "$fullRangeMax"
	
	# Get space left on USB disk and stop backup if no more space and no DB reconstruction
	leftSpace=$(getDiskFreeSpace "$diskPath")
	addLog "D" "LeftSpace=$leftSpace"
	addLog "D" "FullRangeMin=$fullRangeMin"
	addLog "D" "FullRangeMinInKB=$fullRangeMinInKB"
	addLog "D" "FullRangeMax=$fullRangeMax"
	addLog "D" "FullRangeMaxInKB=$fullRangeMaxInKB"
	
	if [ "$reconstructDb" = "N" ] && [ "$removeFiles" = "N" ] && [ "$leftSpace" -ge "$fullRangeMinInKB" ] && [ "$leftSpace" -le "$fullRangeMaxInKB" ]; then
		addLog "D" "Stop copy because disk is full"
		break
	fi
done


## If disk free space under FULL-RANGE-MAX, then send email + copy DB if params say so
freeSpace=$(getDiskFreeSpace "$diskPath" "m")
if [ ! $freeSpace -gt $fullRangeMax ]; then
	shallCopyDB=$(getParamValue "COPY-DB-ON-DISK-FULL" "Y")
	if [ "$shallCopyDB" = "Y" ]; then
		cp -a "$dbDir" "$dbDir.save.$foundDiskName"
	fi
	
	attachList=$(getParamValue "ATTACH-LIST-ON-DISK-FULL" "Y")
	currentDiskList=""
	if [ "$attachList" = "Y" ] && [ -f "$globalList" ]; then
		(
			cd $(dirname "$globalList")
			globalList=$(basename "$globalList")
			awk "/^$foundDiskName:/" "$globalList" > "$globalList.$foundDiskName.txt"
			zip "$globalList.$foundDiskName.zip" "$globalList.$foundDiskName.txt" 1>/dev/null
			rm "$globalList.$foundDiskName.txt"
		)
		currentDiskList="$globalList.$foundDiskName.zip"
	fi
	addLog "D" "AttachList=$attachList"
	addLog "D" "GlobalList=$globalList"
	
	addLog "N" "Space minimum reached"
	sendMail "N" "QNAP - External disk full" "Disk $foundDiskName is full. Please remove this one and connect another one with a name starting with $wantDiskName" "$currentDiskList"
	rm "$currentDiskList" 2>/dev/null
fi

addLog "N" "Backup done"