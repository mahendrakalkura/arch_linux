#!/bin/bash

# --- Interactive Prompts ---

# Disk Selection Menu
echo "Available Disks:"
lsblk -dnp -o NAME,SIZE,MODEL | grep -v "loop\|sr0"
echo ""

PS3="Select the target disk number: "
select DISK_PATH in $(lsblk -dnp -o NAME | grep -v "loop\|sr0"); do
    if [ -n "$DISK_PATH" ]; then
        TARGET="$DISK_PATH"
        echo "Targeting: $TARGET"
        break
    else
        echo "Invalid selection. Try again."
    fi
done

read -p "Enter Hostname: " HOST_NAME
read -p "Enter Username: " USER_NAME
read -s -p "Enter Password: " USER_PASS
echo ""
echo ""

echo "Select CPU Microcode:"
select UCODE in "intel-ucode" "amd-ucode"; do
    [ -n "$UCODE" ] && break
done

# --- Partitioning ---
# Layout: 1G EFI (/boot), Swap=RAM, Rest Root (/)

# Calculations
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
SWAP_GB=$(($RAM_KB / 1024 / 1024 + 1))

# Wipe and Partition
sgdisk -Z $TARGET
sgdisk -n 1:0:+1G -t 1:ef00 $TARGET
sgdisk -n 2:0:+${SWAP_GB}G -t 2:8200 $TARGET
sgdisk -n 3:0:0 -t 3:8300 $TARGET

# Define Partitions (Handle NVMe vs SATA naming)
if [[ "$TARGET" == *"nvme"* ]]; then
  P1="${TARGET}p1"
  P2="${TARGET}p2"
  P3="${TARGET}p3"
else
  P1="${TARGET}1"
  P2="${TARGET}2"
  P3="${TARGET}3"
fi

# Format
mkfs.fat -F32 $P1
mkswap $P2
swapon $P2
mkfs.ext4 $P3

# Mount
mount $P3 /mnt
mkdir -p /mnt/boot
mount $P1 /mnt/boot

# --- Installation ---
pacstrap /mnt base linux linux-firmware base-devel grub efibootmgr networkmanager openssh git nano $UCODE

# --- Configuration ---
genfstab -U /mnt >> /mnt/etc/fstab

# --- Chroot Operations ---
cat <<EOF > /mnt/setup_internal.sh
#!/bin/bash

ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc

echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "$HOST_NAME" > /etc/hostname

echo "root:$USER_PASS" | chpasswd

useradd -m -G wheel -s /bin/bash $USER_NAME
echo "$USER_NAME:$USER_PASS" | chpasswd

echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER_NAME

systemctl enable NetworkManager
systemctl enable sshd

grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

exit
EOF

chmod +x /mnt/setup_internal.sh
arch-chroot /mnt ./setup_internal.sh
rm /mnt/setup_internal.sh

# --- Finish ---
umount -R /mnt
echo "Installation Complete. Type 'reboot' to start your new system."
