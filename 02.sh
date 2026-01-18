#!/bin/bash

# Ensure script is NOT run as root
if [ "$EUID" -eq 0 ]; then
  echo "Please run this script as your NORMAL user, not root."
  exit
fi

echo "--- Arch Linux Hyprland (Custom) Setup ---"

# 1. Update System
echo "Updating repositories..."
sudo pacman -Syu --noconfirm

# 2. Hardware / GPU Selection
echo ""
echo "Select your Graphics Driver:"
options=("Intel (Modern)" "AMD (Open Source)" "NVIDIA (Proprietary)" "Virtual Machine (QEMU/VBox)")
select opt in "${options[@]}"; do
    case $opt in
        "Intel (Modern)")
            GPU_PKG="mesa vulkan-intel intel-media-driver"
            break
            ;;
        "AMD (Open Source)")
            GPU_PKG="mesa vulkan-radeon xf86-video-amdgpu"
            break
            ;;
        "NVIDIA (Proprietary)")
            GPU_PKG="nvidia nvidia-utils nvidia-settings egl-wayland"
            break
            ;;
        "Virtual Machine (QEMU/VBox)")
            GPU_PKG="mesa xf86-video-vmware"
            break
            ;;
        *) echo "Invalid option";;
    esac
done

# 3. Dotfiles URL
echo ""
read -p "Enter your Dotfiles HTTPS URL (leave empty to skip): " DOTFILES_URL

# --- INSTALLATION START ---

# Custom Hyprland Package List
# Note: hyprpolkitagent is in the official repos (Extra).
HYPR_PKG="hyprland waybar fuzzel kitty swaync \
xdg-desktop-portal-hyprland hyprpolkitagent \
qt5-wayland qt6-wayland dolphin"

echo "--- Installing Essentials & Hyprland ---"
sudo pacman -S --needed --noconfirm \
    pipewire pipewire-pulse wireplumber \
    bluez bluez-utils \
    noto-fonts noto-fonts-cjk noto-fonts-emoji ttf-jetbrains-mono-nerd \
    firefox neofetch unzip unrar p7zip ripgrep \
    git base-devel \
    $GPU_PKG $HYPR_PKG

# Enable Services
sudo systemctl enable --now NetworkManager
sudo systemctl enable --now bluetooth
# Note: SDDM is removed. You will boot into TTY.

# Install AUR Helper (Yay)
if ! command -v yay &> /dev/null; then
    echo "--- Installing Yay (AUR Helper) ---"
    git clone https://aur.archlinux.org/yay.git
    cd yay
    makepkg -si --noconfirm
    cd ..
    rm -rf yay
else
    echo "Yay is already installed."
fi

# Apply Dotfiles (Chezmoi)
if [ -n "$DOTFILES_URL" ]; then
    echo "--- Setting up Dotfiles via Chezmoi ---"
    if ! command -v chezmoi &> /dev/null; then
        sudo pacman -S --needed --noconfirm chezmoi
    fi
    chezmoi init --apply "$DOTFILES_URL"
fi

echo "--- Setup Complete! Rebooting in 5 seconds... ---"
sleep 5
reboot
