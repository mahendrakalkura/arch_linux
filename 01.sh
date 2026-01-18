#!/bin/bash

# --- Interactive Prompts ---

# 1. Disk Selection
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

# 2. User & Host Info
read -p "Enter Hostname: " HOST_NAME
read -p "Enter Username: " USER_NAME
read -s -p "Enter Password: " USER_PASS
echo ""
echo ""

# 3. Microcode Selection
echo "Select CPU Microcode:"
select UCODE in "intel-ucode" "amd-ucode"; do
    [ -n "$UCODE" ] && break
done

# 4. GPU Selection (For Drivers)
echo "Select Graphics Driver:"
select GPU_OPT in "Intel" "AMD" "NVIDIA" "VirtualMachine"; do
    case $GPU_OPT in
        "Intel") GPU_PKG="mesa vulkan-intel intel-media-driver"; break ;;
        "AMD")   GPU_PKG="mesa vulkan-radeon xf86-video-amdgpu"; break ;;
        "NVIDIA") GPU_PKG="nvidia nvidia-utils nvidia-settings egl-wayland"; break ;;
        "VirtualMachine") GPU_PKG="mesa xf86-video-vmware"; break ;;
    esac
done

# --- Partitioning (UEFI + Swap) ---
# Layout: 1M BIOS Boot (for Hybrid/QEMU), 1G EFI, Swap=RAM, Rest=Root
RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
SWAP_GB=$(($RAM_KB / 1024 / 1024 + 1))

sgdisk -Z $TARGET
sgdisk -n 1:0:+1M -t 1:ef02 $TARGET    # BIOS Boot (Legacy Support)
sgdisk -n 2:0:+1G -t 2:ef00 $TARGET    # EFI System
sgdisk -n 3:0:+${SWAP_GB}G -t 3:8200 $TARGET # Swap
sgdisk -n 4:0:0 -t 4:8300 $TARGET      # Root

# Handle NVMe vs SATA naming
if [[ "$TARGET" == *"nvme"* ]]; then
  P2="${TARGET}p2"; P3="${TARGET}p3"; P4="${TARGET}p4"
else
  P2="${TARGET}2"; P3="${TARGET}3"; P4="${TARGET}4"
fi

# Format & Mount
mkfs.fat -F32 $P2
mkswap $P3
swapon $P3
mkfs.ext4 $P4

mount $P4 /mnt
mkdir -p /mnt/boot
mount $P2 /mnt/boot

# --- Installation (Base) ---
# Note: Added base-devel and git here as they are needed for Yay later
pacstrap /mnt base linux linux-firmware base-devel grub efibootmgr networkmanager openssh git nano $UCODE

# --- Configuration ---
genfstab -U /mnt >> /mnt/etc/fstab

# --- CHROOT SCRIPT GENERATION ---
cat <<EOF > /mnt/setup_internal.sh
#!/bin/bash

# 1. System Config
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf
echo "$HOST_NAME" > /etc/hostname

# 2. User & Permissions
echo "root:$USER_PASS" | chpasswd
useradd -m -G wheel -s /bin/bash $USER_NAME
echo "$USER_NAME:$USER_PASS" | chpasswd
echo "$USER_NAME ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER_NAME

# 3. Install Official Packages (Pacman)
# Note: Moved fasd to AUR list as it is not in official repos
PACMAN_PKGS=(
    "pipewire" "pipewire-pulse" "wireplumber" "bluez" "bluez-utils"
    "atuin" "btop" "chromium" "cliphist" "cmake" "cpio"
    "fd" "firefox" "fish" "fuzzel" "gammastep" "gcc" "git" "github-cli" "go"
    "grim" "htop" "hyprland" "hyprpaper" "jq" "kitty" "mc" "meson" "mpv"
    "nemo" "neovim" "noto-fonts-emoji" "pamixer" "pavucontrol" "pkg-config"
    "ripgrep" "slurp" "starship" "swaync" "ttf-jetbrains-mono-nerd"
    "udiskie" "unzip" "waybar" "wget" "wl-clipboard" "yazi" "zoxide"
    $GPU_PKG
)

echo "--- Installing Official Packages ---"
pacman -S --needed --noconfirm "\${PACMAN_PKGS[@]}"

# 4. Install AUR Helper & AUR Packages (AS USER)
# We must switch to the user to build packages
cat <<USERscript > /home/$USER_NAME/aur_install.sh
#!/bin/bash
mkdir -p ~/aur
cd ~/aur

# Install Yay
if ! command -v yay &> /dev/null; then
    echo "--- Building Yay ---"
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
fi

# Install User AUR List
# Added fasd here
AUR_PKGS=(
    "fasd"
    "clipit"
    "openvpn-update-systemd-resolved"
    "visual-studio-code-bin"
)

echo "--- Installing AUR Packages ---"
yay -S --needed --noconfirm "\${AUR_PKGS[@]}"
USERscript

# Execute the user script
chmod +x /home/$USER_NAME/aur_install.sh
chown $USER_NAME:$USER_NAME /home/$USER_NAME/aur_install.sh
su - $USER_NAME -c "/home/$USER_NAME/aur_install.sh"
rm /home/$USER_NAME/aur_install.sh

# 5. Enable Services
systemctl enable NetworkManager
systemctl enable sshd
systemctl enable bluetooth

# 6. Bootloader (GRUB) - Removable for QEMU safety
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg

exit
EOF

# --- Execute Chroot Script ---
chmod +x /mnt/setup_internal.sh
arch-chroot /mnt ./setup_internal.sh
rm /mnt/setup_internal.sh

# --- Finish ---
umount -R /mnt
echo "--------------------------------------"
echo "INSTALLATION COMPLETE"
echo "All packages (Official + AUR) installed."
echo "Type 'reboot' to restart."
echo "--------------------------------------"
