#!/usr/bin/env bash
#
# Dotfiles bootstrap installer
# Clones alongside this script's repo checkout and sets up a fresh Arch
# machine to match: packages, shell, fonts, configs, keyboard layout.
#
set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_SUFFIX=".bak-$(date +%Y%m%d-%H%M%S)"

info()  { echo -e "\033[1;34m==>\033[0m $1"; }
warn()  { echo -e "\033[1;33m!!\033[0m $1"; }

if ! command -v pacman &>/dev/null; then
    echo "This installer targets Arch Linux (pacman not found). Aborting."
    exit 1
fi

if [ "$EUID" -eq 0 ]; then
    echo "Don't run this as root — it uses sudo where needed. Aborting."
    exit 1
fi

info "Installing official repo packages..."

PACMAN_PACKAGES=(
    hyprland
    foot
    kitty
    fish
    zsh
    nano
    fastfetch
    btop
    atuin
    lsd
    eza
    git
    base-devel
    ttf-jetbrains-mono-nerd
    quickshell
    gtk3
    gtk4
    xdg-desktop-portal-hyprland
    reflector
)

sudo pacman -S --needed --noconfirm "${PACMAN_PACKAGES[@]}"

info "Configuring reflector for automatic mirror updates..."

REFLECTOR_CONF="/etc/xdg/reflector/reflector.conf"
if [ -f "$REFLECTOR_CONF" ]; then
    sudo tee "$REFLECTOR_CONF" > /dev/null << 'EOF'
--save /etc/pacman.d/mirrorlist
--protocol https
--country Portugal
--latest 5
--sort rate
--age 12
EOF
    sudo systemctl enable --now reflector.timer
    sudo systemctl restart reflector.service
    info "reflector configured and mirrorlist refreshed."
else
    warn "$REFLECTOR_CONF not found — reflector package may not have installed correctly, skipping mirror setup."
fi

if ! command -v yay &>/dev/null; then
    info "yay not found, installing..."
    BUILD_DIR="$(mktemp -d)"
    git clone https://aur.archlinux.org/yay.git "$BUILD_DIR/yay"
    (cd "$BUILD_DIR/yay" && makepkg -si --noconfirm)
    rm -rf "$BUILD_DIR"
else
    info "yay already installed, skipping."
fi

info "Installing AUR packages..."

AUR_PACKAGES=(
    tabby-bin
)

yay -S --needed --noconfirm "${AUR_PACKAGES[@]}" || warn "Some AUR packages failed to install — check output above."

if [ ! -d "$HOME/.oh-my-zsh" ]; then
    info "Installing oh-my-zsh..."
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    info "oh-my-zsh already installed, skipping."
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/plugins"

clone_plugin() {
    local name="$1" url="$2"
    if [ ! -d "$ZSH_CUSTOM/plugins/$name" ]; then
        info "Cloning zsh plugin: $name"
        git clone --depth=1 "$url" "$ZSH_CUSTOM/plugins/$name"
    fi
}

clone_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions"
clone_plugin "you-should-use"      "https://github.com/MichaelAquilina/zsh-you-should-use"
clone_plugin "zsh-bat"             "https://github.com/fdellwing/zsh-bat"

if [ "$SHELL" != "$(command -v zsh)" ]; then
    info "Setting zsh as default login shell (you may be asked for your password)..."
    chsh -s "$(command -v zsh)"
else
    info "zsh is already the default shell."
fi

echo ""
read -rp "Install ASUS ROG keyboard/lighting control (asusctl + rog-control-center)? Only relevant on ASUS laptops. [y/N]: " INSTALL_ASUS
if [[ "$INSTALL_ASUS" =~ ^[Yy]$ ]]; then
    info "Installing asusctl and rog-control-center..."
    yay -S --needed --noconfirm asusctl rog-control-center || warn "Failed to install asusctl/rog-control-center — check output above."
    info "Starting asusd service..."
    sudo systemctl start asusd.service || warn "Could not start asusd — check asusctl install."
else
    info "Skipping ASUS ROG control tools."
fi

backup_and_copy() {
    local src="$1"
    local dest="$2"
    if [ ! -e "$src" ]; then
        return
    fi
    if [ -e "$dest" ] && [ ! -L "$dest" ]; then
        info "Backing up $dest -> $dest$BACKUP_SUFFIX"
        mv "$dest" "$dest$BACKUP_SUFFIX"
    elif [ -L "$dest" ]; then
        rm "$dest"
    fi
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
    echo "Installed $dest"
}

info "Copying config files..."
mkdir -p "$HOME/.config" "$HOME/.local/bin"

backup_and_copy "$DOTFILES_DIR/hypr"       "$HOME/.config/hypr"
backup_and_copy "$DOTFILES_DIR/panacea"    "$HOME/.config/panacea"
backup_and_copy "$DOTFILES_DIR/quickshell" "$HOME/.config/quickshell"
backup_and_copy "$DOTFILES_DIR/foot"       "$HOME/.config/foot"
backup_and_copy "$DOTFILES_DIR/kitty"      "$HOME/.config/kitty"
backup_and_copy "$DOTFILES_DIR/tabby"      "$HOME/.config/tabby"
backup_and_copy "$DOTFILES_DIR/fish"       "$HOME/.config/fish"
backup_and_copy "$DOTFILES_DIR/fastfetch"  "$HOME/.config/fastfetch"
backup_and_copy "$DOTFILES_DIR/atuin"      "$HOME/.config/atuin"
backup_and_copy "$DOTFILES_DIR/btop"       "$HOME/.config/btop"
backup_and_copy "$DOTFILES_DIR/gtk-3.0"    "$HOME/.config/gtk-3.0"
backup_and_copy "$DOTFILES_DIR/gtk-4.0"    "$HOME/.config/gtk-4.0"
backup_and_copy "$DOTFILES_DIR/zsh/.zshrc"    "$HOME/.zshrc"
backup_and_copy "$DOTFILES_DIR/nano/.nanorc"  "$HOME/.nanorc"

if [ -f "$DOTFILES_DIR/mimeapps.list" ]; then
    cp "$DOTFILES_DIR/mimeapps.list" "$HOME/.config/mimeapps.list"
fi

if [ -d "$DOTFILES_DIR/bin" ]; then
    cp -r "$DOTFILES_DIR/bin/." "$HOME/.local/bin/"
    chmod +x "$HOME/.local/bin/"* 2>/dev/null || true
fi

echo ""
info "Keyboard layout setup"
read -rp "Enter your Hyprland/Wayland keyboard layout code (e.g. pt, us, ru) [pt]: " KB_LAYOUT
KB_LAYOUT="${KB_LAYOUT:-pt}"

INPUT_LUA="$HOME/.config/hypr/lua/input.lua"
if [ -f "$INPUT_LUA" ]; then
    sed -i "s/kb_layout\s*=\s*\"[^\"]*\"/kb_layout  = \"$KB_LAYOUT\"/" "$INPUT_LUA"
    echo "Set kb_layout = \"$KB_LAYOUT\" in $INPUT_LUA"
else
    warn "$INPUT_LUA not found, skipping Hyprland keyboard layout"
fi

read -rp "Also set the console/TTY keymap to match? [y/N]: " SET_CONSOLE
if [[ "$SET_CONSOLE" =~ ^[Yy]$ ]]; then
    read -rp "Enter console keymap (e.g. pt-latin9, us) [pt-latin9]: " CONSOLE_KEYMAP
    CONSOLE_KEYMAP="${CONSOLE_KEYMAP:-pt-latin9}"
    sudo localectl set-keymap "$CONSOLE_KEYMAP"
    echo "Console keymap set to $CONSOLE_KEYMAP"
fi

echo ""
info "All done."
echo "  - Log out and back in (or reboot) for the shell change and Hyprland to take effect."
echo "  - Run 'hyprctl reload' if you're already inside Hyprland."
echo "  - If you installed ASUS ROG tools, run 'asusctl led-mode -h' to see keyboard lighting options."