# com.cyberinternauts.linux.backup

## Speech
This backup is useful to copy big/huge NAS to smaller disks. As back in the 90s (1990s), when we had to copy a software on multiple floppy disks, now with NAS having the possibility to store few dozens of TB or even hundreds, what can you do to copy them on smaller disks? Well, using this script!

## Why it has been created?
Using a NAS in RAID-5 or even RAID-1 (or others) can protect you against a disk or even half of the NAS disks failure at once, but what happens if it burns or if it is stolen. So, there was borned the idea to backup NAS disks onto external smaller ones that can be moved to another physical location.

## Usage
- Download all files or clone the repository.
- Setup the configuration file "conf/test.conf" or create your own.
- Connect a USB drive on your NAS having a name starting with what you set in the configuration file.
- Ensure the file "backup.sh" is executable: use chmod.
- Execute the script "backup.sh CONFIGURATION_FILE_PATH" twice. (Twice because the first execution list files and second compare what has changed)

## Recommended usage
- Schedule the script to be executed twice each day (the second one being executed 30-60 minutes later).
- Ensure to have an email address set in the configuration file.

With this setup you will receive an email when the external disk is full and you need to plug another one.

# Any ideas or want to participate... don't hesitate
