#!/bin/bash

src_pool="$1"
dst_pool="$2"
volume="$3"

keep=20

prefix="auto"

#####################################################################
if [ "$src_pool" == "" ] || [ "$dst_pool" == "" ] || [ "$volume" == "" ]
then
  echo "[backup] misconfigured: src_pool=$src_pool, dst_pool=$dst_pool, volume=$volume"
  echo "[backup] misconfigured: src_pool=$src_pool, dst_pool=$dst_pool, volume=$volume" | logger
  exit 1
fi


echo "[backup] $src_pool/$volume to $dst_pool/$volume (prefix: $prefix)"
echo "[backup] $src_pool/$volume to $dst_pool/$volume (prefix: $prefix)" | logger

latest_src_snapshot=$(zfs list -H -o name -t snapshot | grep $src_pool/$volume | grep $prefix | tail -1)
latest_dst_snapshot=$(zfs list -H -o name -t snapshot | grep $dst_pool/$volume | grep $prefix | tail -1)

if [ "$latest_src_snapshot" = "" ]
then
  echo "[backup] $src_pool/$volume does not have snapshots with prefix: $prefix"
  echo "[backup] $src_pool/$volume does not have snapshots with prefix: $prefix" | logger
  exit 1
fi

if [ "$latest_dst_snapshot" = "" ]
then
  echo "[backup] performing initial backup to $dst_pool/$volume using $latest_src_snapshot" | logger
  zfs send $latest_src_snapshot | zfs receive -Fduv $dst_pool | logger
else
  src_snapshot_name=${latest_src_snapshot#"$src_pool/$volume@"}
  dst_snapshot_name=${latest_dst_snapshot#"$dst_pool/$volume@"}
  if [ "$src_snapshot_name" = "$dst_snapshot_name" ]
  then
    echo "[backup] the latest snapshot has already been sent"
   else
    echo "[backup] performing incremental backup to $dst_pool/$volume, current=$latest_dst_snapshot, src=$latest_src_snapshot" | logger
    zfs send -Ri $dst_snapshot_name $latest_src_snapshot | zfs receive -Fduv $dst_pool | logger
  fi
fi

new_dst_snapshot=$(zfs list -H -o name -t snapshot | grep $dst_pool/$volume | grep $prefix | tail -1)
echo "[backup] rollback to the latest snapshot: $new_dst_snapshot" | logger
zfs rollback $new_dst_snapshot | logger

snapshots_to_remove=($(zfs list -H -o name -t snapshot | grep $dst_pool/$volume | tail -r | tail +$((keep+1))))

if [ ${#snapshots_to_remove[@]} -eq 0 ]; then
    echo "[backup] no obsolete snapshots to remove" | logger
else
    for old_snapshot in "${snapshots_to_remove[@]}"
  do
    echo "[backup] removing obsolete snapshot $old_snapshot" | logger
    zfs destroy -r $old_snapshot | logger
  done
fi
