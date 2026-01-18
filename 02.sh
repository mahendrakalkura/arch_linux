#!/bin/bash

echo "--- Arch Linux Configuration (Dotfiles) ---"

# 1. Get Dotfiles URL
echo ""
read -p "Enter your Dotfiles HTTPS URL (leave empty to skip): " DOTFILES_URL

if [ -z "$DOTFILES_URL" ]; then
    echo "Skipping dotfiles."
    exit 0
fi

# 2. Check for Chezmoi (Should be installed by Script 1, but safe check)
if ! command -v chezmoi &> /dev/null; then
    echo "Chezmoi not found (unexpected). Installing..."
    sudo pacman -S --needed --noconfirm chezmoi
fi

# 3. Apply
echo "--- Applying Dotfiles ---"
chezmoi init --apply "$DOTFILES_URL"

echo ""
echo "Configuration Complete!"
