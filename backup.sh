#!/bin/bash
# Copyright (C) Jörg Binnewald. All rights reserved.  

# Pool mit den zu sichernden Daten
MASTERPOOL="ZRAID5"

# Backup-Pool
BACKUPPOOL="EXTBACKUP"

# Datasets, die in das Backup sollen
DATASETS=("data" "home")

# Anzahl der zu behaltenden letzten Snapshots, mindestens 1
KEEPOLD=3

# Praefix fuer Snapshot-Namen
PREFIX="offsite"

# -------------- ab hier nichts aendern ---------------

zpool import $BACKUPPOOL

KEEPOLD=$(($KEEPOLD + 1))

for DATASET in ${DATASETS[@]}
do
    # Namen des aktuellsten Snapshots aus dem Backup holen
	recentBSnap=$(zfs list -rt snap -H -o name "${BACKUPPOOL}/${DATASET}" | grep "@${PREFIX}-" | tail -1 | cut -d@ -f2)
	if [ -z "$recentBSnap" ] 
		then
			dialog --title "Kein Snapshot gefunden" --yesno "Es existiert kein Backup-Snapshot in ${BACKUPPOOL}/${DATASET}. Soll ein neues Backup angelegt werden? (Vorhandene Daten in ${BACKUPPOOL}/${DATASET} werden ueberschrieben.)" 15 60
			ANTWORT=${?}
			if [ "$ANTWORT" -eq "0" ]
				then
					# Backup initialisieren
					NEWSNAP="${MASTERPOOL}/${DATASET}@${PREFIX}-$(date '+%Y%m%d-%H%M%S')"
					zfs snapshot -r $NEWSNAP
					zfs send -v $NEWSNAP | zfs recv -F "${BACKUPPOOL}/${DATASET}"
			fi
			continue
	fi
	
	# Check ob der korrespondierende Snapshot im Master-Pool existiert
	origBSnap=$(zfs list -rt snap -H -o name "${MASTERPOOL}/${DATASET}" | grep $recentBSnap | cut -d@ -f2)
	if [ "$recentBSnap" != "$origBSnap" ]
		then
			echo "Fehler: Zum letzten Backup-Spanshot ${recentBSnap} existiert im Master-Pool kein zugehoeriger Snapshot."
			continue
	fi
	
	echo "aktuellster Snapshot im Backup: ${BACKUPPOOL}/${DATASET}@${recentBSnap}"
	
	# Name fuer neuen Snapshot
	NEWSNAP="${MASTERPOOL}/${DATASET}@${PREFIX}-$(date '+%Y%m%d-%H%M%S')"
	# neuen Snapshot anlegen
	zfs snapshot -r $NEWSNAP
	echo "neuen Snapshot angelegt: ${NEWSNAP}"
	
	# neuen Snapshot senden
	zfs send -v -i $recentBSnap $NEWSNAP | zfs recv "${BACKUPPOOL}/${DATASET}"
	
	# alte Snapshots loeschen
	zfs list -rt snap -H -o name "${BACKUPPOOL}/${DATASET}" | grep "@${PREFIX}-" | tac | tail +$KEEPOLD | xargs -n 1 zfs destroy -r
    zfs list -rt snap -H -o name "${MASTERPOOL}/${DATASET}" | grep "@${PREFIX}-" | tac | tail +$KEEPOLD | xargs -n 1 zfs destroy -r
done

zpool export $BACKUPPOOL
