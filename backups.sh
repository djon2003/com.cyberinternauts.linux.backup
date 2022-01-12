#!/bin/sh

# Switch to script directory
dirToNavigate=$(dirname "$0")
cd $dirToNavigate

# Ensure script is executed with parameter
fileName=$1

if [ "$#" -eq 0 ]; then
	echo "Backups shall be called with a filename that contains a list of configuration files"
	exit
fi

if [ ! -f "$fileName" ]; then
	echo "Configurations list file doesn't exist : $fileName"
	exit
fi

## Create data directory
dbDir=./.backup.db
if [ ! -d $dbDir ]; then
	mkdir $dbDir
fi

# Convert configurations list file
# Convert DOS to Unix newline char(s)
confFile=$(echo $fileName | awk -F "/" '{print $NF}')

tmpConf="$dbDir/$confFile.conf"
tr -d '\015' < $fileName > "$tmpConf"
fileName="$tmpConf"

# Remove first software arg
shift

# Call each backup
while IFS='' read -r line || [[ -n "$line" ]]; do
	i=${backups[$iK]}
	./backup.sh "$line" "$@"
done < "$fileName"