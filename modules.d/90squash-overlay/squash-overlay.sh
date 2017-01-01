#!/bin/sh

. /lib/dracut-lib.sh

modprobe overlay

# Move root
# --move does not always work. Google >mount move "wrong fs"< for
#     details
mkdir -p /live/image
mount --bind $NEWROOT /live/image
umount $NEWROOT

mkdir -p /live/squash
mount -t squashfs /live/image/squashfs.img /live/squash -o loop

# Create tmpfs
mkdir /cow
mount -n -t tmpfs -o mode=0755 tmpfs /cow
mkdir /cow/work /cow/rw

# Merge both to new Filesystem
mount -t overlay -o noatime,lowerdir=/live/squash,upperdir=/cow/rw,workdir=/cow/work,default_permissions overlay $NEWROOT

# Let filesystems survive pivot
mkdir -p $NEWROOT/live/cow
mkdir -p $NEWROOT/live/image
mkdir -p $NEWROOT/live/squash
mount --bind /cow/rw $NEWROOT/live/cow
umount /cow
mount --bind /live/image $NEWROOT/live/image
umount /live/image
mount --bind /live/squash $NEWROOT/live/squash
umount /live/squash
