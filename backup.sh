#!/bin/sh


## Load base library
scriptDir=$(dirname "$BASH_SOURCE")
source "$scriptDir/com.cyberinternauts.linux.libraries/baselib.sh"


### TODO: Delete: /share/homes/Spectacles/@Test && /share/homes/Spectacles/@__thumb
echo "WORKING"

## Ensure softwares needed exist, if so update it if necessary
isExisting=$(isProgramExist "diff")
if [ "$isExisting" = "N" ]; then
	isExisting=$(isProgramExist "opkg")
	if [ "$isExisting" = "N" ]; then
		## The specific architecture here (in the URL) doesn't matter because the script manage it
		wget -O - http://entware.zyxmon.org/binaries/armv5/installer/entware_install.sh | /bin/sh
	fi
	opkg install diffutils
else
	opkg update
	opkg upgrade
fi

# Ensure "diff" exists (in case the download failed before)
ensureProgramExist "diff"

## Ensure launched only once
launchOnlyOnce

# Switch to script directory
setDirToScriptOne

#### #### #### #### #### #### #### ####
## Base variables definitions
#### #### #### #### #### #### #### ####

defaultBaseDir="/share/homes"
declare -a params_needed
params_needed=("DISK" "FULL-RANGE" "EMAIL")

#### #### #### #### #### #### #### ####
## Functions definitions
#### #### #### #### #### #### #### ####

function getDiskFreeSpace()
{
	local diskSpaceLine2
	local diskSpaceLine=$(df -m $diskPath)
	IFS=' ' read -rd '' -a diskSpaceLine2 <<< "$diskSpaceLine"
	local freeSpace=$((${diskSpaceLine2[7]} - ${diskSpaceLine2[8]}))
	
	echo $freeSpace
}

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

function ensureDiskConnected()
{
	local testingFile="$diskPath/test.testing$.$test"
	local mountExists=$(mount -l | grep $diskPath)
	local writePossible=$(echo "Y" > "$testingFile" && echo "1")
	
	###TODO: Shall not exist but return 1 if failing and 0 if success and the callee shall stop what it is doing to be able to send an error email
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

renameFunction sendMail __sendMail
function sendMail()
# $1 = is this an error (Value "Y" means yes, all others mean no)
# $2 = email object
# $3 = email content
{
	local isError=$1
	if [ "$isError" != "Y" ]; then
		isError=""
	fi
	local emailObject=$2
	local emailContent=$3
	local email=$(getParamValue "EMAIL")
	local errorEmail=$(getParamValue "ERROR-EMAIL" "$email")
	
	if [ "$isError" != "" ]; then
		email="$errorEmail"
	fi
	
	if [ "$email" = "" ]; then
		return
	fi
	
	__sendMail "$emailObject" "$email" "$email" "$emailContent"
}

function addLog()
# $1 level of the log (D or DEBUG, N or NORMAL)
# $2 log content
{
	local thisLogLevel=$1
	local thisLog=$2
	if [ "$logLevel" != "DEBUG" ] && ([ "$thisLogLevel" = "D" ] || [ "$thisLogLevel" = "DEBUG" ]); then
		return
	fi
	
	echo "$thisLog"
}

#### #### #### #### #### #### #### ####
## Execution of script
#### #### #### #### #### #### #### ####

echo "Backup started"

fileName=$1

if [ "$#" -eq 0 ]; then
	echo "Backup shall be called with a configuration filename" >&2
	exit
fi

if [ ! -f "$fileName" ]; then
	echo "Configuration file doesn't exist : $fileName" >&2
	exit
fi

## Create data directory
dbDir=$(pwd)/.backup.db

if [ ! -d $dbDir ]; then
	mkdir $dbDir
fi

## Read configuration file
echo "Reading configuration : $fileName"

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
		confError="${confError}Key $i not found in configuration file\n"
	else
		if [ "${params_values[$valueKey]}" = "" ]; then
			confError="${confError}Key $i is empty in configuration file\n"
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
	printf "$confError" >&2
	sendMail "Y" "Configuration file errors" "Configuration file: $1\n\n$confError"
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
	echo "$mailMessage" >&2
	sendMail "N" "QNAP - Missing folder to backup" "$mailMessage"
	exit
fi

## Look if needed disk is connected (and only one !) and get its mounted path
mountedDisks=$(mount -l | grep /share/external/ | grep /dev/sd)
IFS=$'\n' read -rd '' -a mountedDisks2 <<< "$mountedDisks"

foundDiskCount=0
diskPath=""
getDiskPath=0
wantDiskName=$(getParamValue "DISK")
foundDiskName=""
for i in ${mountedDisks2[@]}; do
	if [[ $getDiskPath -eq 2 ]]; then
		diskPath=$i
		getDiskPath=0
	fi
	if [[ $getDiskPath -eq 1 ]]; then
		getDiskPath=2
	fi
	
	if [[ $i = \/dev\/* ]] ; then
		diskName=$(blkid -s LABEL -o value $i)
		if [[ "$diskName" = $wantDiskName* ]]; then
			foundDiskName=$diskName
			foundDiskCount=$((foundDiskCount+1))
			getDiskPath=1
		fi
	fi
done

if [ $foundDiskCount -eq 0 ]; then
	mailMessage="No USB disk found starting with name $wantDiskName"
	echo "$mailMessage" >&2
	sendMail "N" "QNAP - Missing disk" "$mailMessage"
	exit
fi

if [ $foundDiskCount -ne 1 ]; then
	mailMessage="More than one USB disk found starting with name $wantDiskName"
	echo "$mailMessage" >&2
	sendMail "N" "QNAP - More than one disk" "$mailMessage"
	exit
fi

## Verify if no error on disk
diskErrorFile="$dbDir/$wantDiskName..check"
ls -R "$diskPath/" 1> /dev/null 2> "$diskErrorFile"
isError=$(ls -s "$diskErrorFile" | awk '{print $1}')
if [ ! "$isError" = "0" ]; then
	mailMessage="Disk $foundDiskName has errors. Please do a file verification."
	echo "$mailMessage" >&2
	sendMail "Y" "QNAP - Disk having errors" "$mailMessage"
fi

## Set FULL-RANGE-MAX and FULL-RANGE-MIN
fullRangeVal=$(getParamValue "FULL-RANGE")
IFS=$'-' read -r -a fullRange <<< "$fullRangeVal"
fullRangeMax=${fullRange[1]}
fullRangeMin=${fullRange[0]}

## Ensure space is enough high on disk
addLog "N" "Will backup on $diskPath named $foundDiskName"
freeSpace=$(getDiskFreeSpace)
if [ ! $freeSpace -gt $fullRangeMin ]; then
	addLog "N" "Space minimum reached"
	sendMail "N" "QNAP - External disk full" "Disk $foundDiskName is full. Please remove this one and put another one with the name starting with $wantDiskName"
	exit
fi
leftSpace=1 # Set it over zero because if first folder to copy only has empty folders (which are not copied), then condition at the end of the loop shall pass

## Choose LS method
lsMethod=2
ls -lLAesR 2>/dev/null
if [ $? -eq 0 ]; then lsMethod=1; fi

initialDir=$(pwd)

## Loop through folders to backup
for iK in ${!folders[@]}; do
	ensureDiskConnected

	i="${folders[$iK]}"
	addLog "N" "Folder $i"
	folderDb=$(echo "$i" | tr / .)
	folderDb="$dbDir/$wantDiskName$folderDb"
	
	###D
	#if [ 1 = 2 ]; then
	## List files/folders to backup
	errorsToFilter=("${exclusions[@]}")
	if [ $lsMethod -eq 1 ]; then
		executeAndFilterErrors "${errorsToFilter[@]}" "ls -lLAesR \"$i\" >\"$folderDb.fetch-1\""
	else
		# Columns of "ls" shall be SizeInBlock Rights User Group Size MonthAsThreeLetters DayOfMonth Time(HH:mm:ss) Year FileName
		executeAndFilterErrors "${errorsToFilter[@]}" "ls -lLAsR --time-style=\"+%b %d %H:%M:%S %Y\" \"$i\" >\"$folderDb.fetch-1\""
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
	
	exit
	###D
	#fi
	
	## For each elements to copy
	## - Ensure not a folder
	## - Check if enough space to copy on disk and would still be over FULL-RANGE-MIN after copy
	## - Copy on disk
	## - Add to the .list
	lastDir=$(echo "$i" | awk -F "/" '{print $NF}')
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
		###D
		#if [ ! "/share/homes/external/externe1/Séries télévisés intégrale/Sense & Sensibility/Raison et sentiments INTEGRAL FRENCH DVDRip XviD-LKT/Raison et sentiments episode 2 FRENCH DVDRip XviD-LKT.avi" = "$elementToCopy" ]; then
		#	continue
		#fi
		
		line=$(echo "$line" | sed 's/|//')
		
		addLog "D" "||E=$elementToCopy||"
		addLog "D" "||L=$line||"
		addLog "D" "||EK=$elementToCopyKey||"
		addLog "D" "||ES=$elementToCopySize||$elementToCopyHasChanged||"
		
		if [ -d "$elementToCopy" ]; then
			if [ "$elementToCopyHasChanged" = "1" ]; then
				###D
				a=1
				sed "\|^$elementToCopyKey |d" "$folderDb.list" > "$folderDb.list2"
				cp "$folderDb.list2" "$folderDb.list"
			fi
			###D 
			echo "$line" >> "$folderDb.list"
		else
			ensureDiskConnected

			addLog "N" "To copy : $elementToCopy"
			leftSpace=$(getDiskFreeSpace)
			###D 
			addLog "D" "||LS=$leftSpace||"
			leftSpace=$((($leftSpace << 10) - ($elementToCopySize) - ($fullRangeMin << 10)))
			###D 
			addLog "D" "||LS=$leftSpace||"
			
			if [ "$leftSpace" -gt 0 ]; then
				fileName=$(echo "$elementToCopy" | awk -F "/" '{print $NF}')
				pathEnd=$(dirname "$elementToCopy")
				if [ "$pathEnd" = "$i" ]; then
					pathEnd=""
				else
					pathEnd=$(echo "$pathEnd" | sed "s|^$i/||")
					pathEnd="$pathEnd/"
				fi
				
				###D 
				mkdir -p "$diskPath/$lastDir/$pathEnd"
				addLog "N" "Copying : $diskPath/$lastDir/$pathEnd$fileName"
				if [ -f "$diskPath/$lastDir/$pathEnd$fileName" ]; then
					a=1
					###D 
					rsync -a --no-compress "$elementToCopy" "$diskPath/$lastDir/$pathEnd$fileName"
				else
					a=1
					###D 
					cp -a "$elementToCopy" "$diskPath/$lastDir/$pathEnd$fileName"
				fi
				if [ "$?" -eq "0" ]; then
					if [ "$elementToCopyHasChanged" = "1" ]; then
						###D 
						a=1
						sed "\|^$elementToCopyKey |d" "$folderDb.list" > "$folderDb.list2"
						cp "$folderDb.list2" "$folderDb.list"
					fi
					###D 
					echo "$line" >> "$folderDb.list"
				else
					echo "Error - exit code: $?" >&2
				fi
			else
				break
			fi
		fi
		
		###D		exit
	done < "$folderDb.tocopy"
	
	if [ ! "$leftSpace" -gt 0 ]; then
		break
	fi
done


## If disk free space under FULL-RANGE-MAX, then send email + copy DB if params say so
freeSpace=$(getDiskFreeSpace)
if [ ! $freeSpace -gt $fullRangeMax ]; then
	shallCopyDB=$(getParamValue "COPY-DB-ON-DISK-FULL" "Y")
	if [ "$shallCopyDB" = "Y" ]; then
		cp -a "$dbDir" "$dbDir.save.$foundDiskName"
	fi

	addLog "N" "Space minimum reached"
	sendMail "N" "QNAP - External disk full" "Disk $foundDiskName is full. Please remove this one and connect another one with a name starting with $wantDiskName"
	exit
fi

## If errors happened, then send email
isFileDescriptor3Exist=$(command 2>/dev/null >&3 && echo "Y")
if [ "$isFileDescriptor3Exist" = "Y" ]; then
	logFile=$(readlink /proc/self/fd/3 | sed s/.log$/.err/)
	logFileSize=$(stat -c %s "$logFile")
	if [ $logFileSize -gt 0 ]; then
		addLog "N" "Sending error email"
		logFileName=$(basename "$logFile")
		logFileContent=$(cat "$logFile")
		sendMail "Y" "QNAP - Backup error" "Error happened on backup. See log file $logFileName\n\nLog error file content:\n$logFileContent"
		exit
	fi
fi

addLog "N" "Backup done"