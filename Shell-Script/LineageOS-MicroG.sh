#!/bin/bash

# ================================
# Colors
# ================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

# ================================
# Terminal Setup
# ================================
echo -en "\033[?25l"  # hide cursor
trap 'echo -en "\033[?12l\033[?25h"' EXIT  # restore on exit

# ================================
# Helper Functions
# ================================
error_exit() {
    local message="$1"
    local exit_code="${2:-1}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[ERROR] ${timestamp} - ${message}${RESET}" >&2
    exit "$exit_code"
}

print_header() {
    local message="$1"
    local border_char="${2:-=}"
    local color="${3:-$GREEN}"
    local length=${#message}
    local border=$(printf "%${length}s" | tr " " "$border_char")
    echo -e "${color}${border}${RESET}"
    echo -e "${color}${message}${RESET}"
    echo -e "${color}${border}${RESET}"
}

cleanup_repos() {
    echo -e "${YELLOW}Performing cleanup...${RESET}"
    rm -rf .repo/local_manifests/
    rm -rf hardware/qcom-caf/common
    rm -rf packages/apps/ThemePicker
    rm -rf vendor/qcom/opensource/healthd-ext
    rm -rf vendor/lineage
    print_header "Cleanup completed"
}

clone_repo() {
    local repo_url=$1
    local branch=$2
    local dest=$3

    echo -e "${CYAN}Cloning $dest...${RESET}"

    [ -d "$dest" ] && rm -rf "$dest"

    git clone --depth 1 -b "$branch" "$repo_url" "$dest" || error_exit "Failed to clone $dest"

    print_header "$dest clone success"
}

clone_hal() {
    local url=$1
    local path=$2
    local branch=$3
    rm -rf "$path"
    git clone --depth 1 -b "$branch" "$url" "$path" || error_exit "Failed to clone HAL $path"
}

add_to_device_mk() {
    local package=$1
    local device_mk="device/xiaomi/sapphire/device.mk"

    if [ ! -f "$device_mk" ]; then
        echo -e "${YELLOW}device.mk not found, skipping $package addition${RESET}"
        return
    fi

    if ! grep -q "^PRODUCT_PACKAGES += $package$" "$device_mk"; then
        echo "PRODUCT_PACKAGES += $package" >> "$device_mk"
        print_header "$package added to device.mk"
    else
        echo -e "${YELLOW}$package already exists in device.mk${RESET}"
    fi
}

patch_signature_spoofing() {
    local COMPUTER_ENGINE="frameworks/base/services/core/java/com/android/server/pm/ComputerEngine.java"

    if [ ! -f "$COMPUTER_ENGINE" ]; then
        echo -e "${YELLOW}ComputerEngine.java not found, skipping patch${RESET}"
        return
    fi

    cp "$COMPUTER_ENGINE" "${COMPUTER_ENGINE}.backup"

    if grep -q 'if (!isDebuggable())' "$COMPUTER_ENGINE"; then
        sed -i '/if (!isDebuggable()) {/{N;N;d}' "$COMPUTER_ENGINE"
        print_header "Signature Spoofing patch applied"
    else
        echo -e "${YELLOW}Signature Spoofing patch: block not found or already patched${RESET}"
    fi
}

patch_version_mk() {
    local version_mk="vendor/lineage/config/version.mk"

    if [ ! -f "$version_mk" ]; then
        echo -e "${YELLOW}version.mk not found, skipping MicroG suffix patch${RESET}"
        return
    fi

    cp "$version_mk" "${version_mk}.backup"

    if grep -q "MicroG" "$version_mk"; then
        echo -e "${YELLOW}MicroG suffix already patched${RESET}"
        return
    fi

    sed -i '/^LINEAGE_VERSION_SUFFIX := .*/a \
\
# Add MICROG to suffix if WITH_GMS is true\
ifeq ($(WITH_GMS),true)\
    LINEAGE_VERSION_SUFFIX := $(LINEAGE_VERSION_SUFFIX)-MicroG\
endif\
\
# Add custom build tag/feature to suffix if BUILD_TAG is defined\
ifneq ($(BUILD_TAG),)\
    LINEAGE_VERSION_SUFFIX := $(LINEAGE_VERSION_SUFFIX)-$(BUILD_TAG)\
endif' "$version_mk"

    if grep -q "MICROG" "$version_mk"; then
        print_header "MicroG suffix patch applied successfully"
    else
        echo -e "${YELLOW}Warning: MicroG suffix patch may not have been applied${RESET}"
    fi
}

# ================================
# Check/Create LineageOS-MicroG directory
# ================================
setup_lineage_dir() {
    LINEAGE_DIR="LineageOS-MicroG"
    TARGET_DIR="$HOME/$LINEAGE_DIR"

    cd_or_exit() {
        cd "$1" || error_exit "Failed to cd to $1"
    }

    if [ "$(basename "$PWD")" != "$LINEAGE_DIR" ]; then
        echo -e "${CYAN}Not in $LINEAGE_DIR directory. Checking/Creating...${RESET}"

        if [ -d "$TARGET_DIR" ]; then
            cd_or_exit "$TARGET_DIR"
            echo -e "${GREEN}Changed to existing directory: $PWD${RESET}"
        else
            echo -e "${YELLOW}Creating $TARGET_DIR...${RESET}"
            mkdir -p "$TARGET_DIR" || error_exit "Failed to create $TARGET_DIR"
            cd_or_exit "$TARGET_DIR"
            echo -e "${GREEN}Created and changed to: $PWD${RESET}"
        fi
    else
        echo -e "${GREEN}Already in $LINEAGE_DIR directory: $PWD${RESET}"
    fi
}

# ================================
# Main Script
# ================================

sleep 4s && clear
setup_lineage_dir
cd "$HOME/LineageOS-MicroG" || error_exit "Failed to cd to LineageOS-MicroG"

sleep 4s && clear
echo -e "${CYAN}Starting LOS 23.2 build script...${RESET}"

sleep 4s && clear
cleanup_repos

sleep 4s && clear
echo -e "${CYAN}Initializing repo...${RESET}"
repo init -u https://github.com/LineageOS/android.git -b lineage-23.2 --git-lfs || error_exit "Repo init failed"
print_header "Repo init success"

sleep 4s && clear
clone_repo "https://github.com/saroj-nokia/local_manifests_sapphire" "sapphire16" ".repo/local_manifests"

sleep 4s && clear
echo -e "${CYAN}Creating MicroG manifest...${RESET}"
cat > .repo/local_manifests/microg.xml << EOF
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
    <remote name="lineageos4microg" fetch="https://github.com/lineageos4microg/" />
    <project path="vendor/partner_gms" name="android_vendor_partner_gms" remote="lineageos4microg" revision="master" />
</manifest>
EOF
print_header "MicroG manifest created"

sleep 4s && clear
echo -e "${CYAN}Syncing full repo...${RESET}"
repo sync -c --force-sync --optimized-fetch --no-tags --no-clone-bundle --prune -j14 || error_exit "Repo sync failed"
print_header "Repo sync success"

sleep 4s && clear
echo -e "${CYAN}Cloning HALs for SM6225...${RESET}"
clone_hal "https://github.com/sapphire-sm6225/android_hardware_qcom-caf_common.git" "hardware/qcom-caf/common" "lineage-23.2"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_agm.git" "hardware/qcom-caf/sm6225/audio/agm" "lineage-22.2-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_arpal-lx.git" "hardware/qcom-caf/sm6225/audio/pal" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_data-ipa-cfg-mgr.git" "hardware/qcom-caf/sm6225/data-ipa-cfg-mgr" "lineage-23.2-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/vendor_qcom_opensource_dataipa.git" "hardware/qcom-caf/sm6225/dataipa" "lineage-23.2-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_display.git" "hardware/qcom-caf/sm6225/display" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_media.git" "hardware/qcom-caf/sm6225/media" "lineage-23.2-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/hardware_qcom_audio.git" "hardware/qcom-caf/sm6225/audio/primary-hal" "lineage-22.0-caf-sm6225"
clone_hal "https://github.com/sapphire-sm6225/device_qcom_sepolicy_vndr.git" "device/qcom/sepolicy_vndr/sm6225" "lineage-23.2-caf-sm6225"
print_header "HALs cloned"

sleep 4s && clear
rm -rf vendor/lineage
clone_repo "https://github.com/sapphire-sm6225/android_vendor_lineage.git" "lineage-23.2" "vendor/lineage"
print_header "Vendor cleanup completed"

add_my_apps(){
    sleep 4s && clear
    echo -e "${CYAN}Cloning Via browser...${RESET}"
    mkdir -p packages/apps/Via
    git clone --depth 1 -b avium-16.2 https://github.com/AviumUI/android_packages_apps_Via.git packages/apps/Via
    rm -rf packages/apps/Via/.git
    print_header "Via browser cloned to packages/apps/Via"

    sleep 4s && clear
    add_to_device_mk "Via"

    sleep 4s && clear
    echo -e "${CYAN}Cloning AuroraStore prebuilt...${RESET}"
    rm -rf vendor/aurora
    git clone --depth 1 -b 12L https://github.com/MSe1969/AuroraStore-prebuilt.git vendor/aurora
    rm -rf vendor/aurora/.git
    print_header "AuroraStore prebuilt cloned to vendor/aurora"

    sleep 4s && clear
    add_to_device_mk "AuroraStore"
    add_to_device_mk "AuroraServices"
}

sleep 4s && clear
echo -e "${CYAN}Installing gofile upload tool...${RESET}"
wget -q https://raw.githubusercontent.com/kenway214/GoFile-Upload-Script/master/upload.sh \
    -O ~/LineageOS-MicroG/gofile && chmod +x ~/LineageOS-MicroG/gofile
if ! grep -q 'alias gofile' ~/.bashrc; then
    echo 'alias gofile="~/LineageOS-MicroG/gofile"' >> ~/.bashrc
fi
source ~/.bashrc 2>/dev/null || true
print_header "gofile installed"

LINEAGE_SAPPHIRE_MK="device/xiaomi/sapphire/lineage_sapphire.mk"
if [ -f "$LINEAGE_SAPPHIRE_MK" ]; then
    sed -i 's/^-include vendor\/gapps\/arm64\/arm64-vendor.mk/#-include vendor\/gapps\/arm64\/arm64-vendor.mk/' "$LINEAGE_SAPPHIRE_MK"
    print_header "Gapps line commented in lineage_sapphire.mk"
else
    echo -e "${YELLOW}lineage_sapphire.mk not found, skipping Gapps comment${RESET}"
fi

sleep 4s && clear
patch_signature_spoofing

sleep 4s && clear
patch_version_mk

sleep 4s && clear
echo -e "${CYAN}Setting up build environment...${RESET}"
source build/envsetup.sh
export BUILD_USERNAME=WhoFoss
export BUILD_HOSTNAME=los23
export SKIP_ABI_CHECKS=true
export WITH_GMS=true
mkdir -p out/target/product/sapphire/obj/KERNEL_OBJ/usr
print_header "Build environment ready"

sleep 4s && clear
echo -e "${CYAN}Starting build...${RESET}"

brunch sapphire user || error_exit "Brunch failed"

sleep 4s && clear
print_header "Build process completed successfully!"

sleep 4s
# Upload ROM zip file to GoFile
ROM_DIR="out/target/product/sapphire/"
ROM_NAME=$(ls "$ROM_DIR" | grep "lineage-23.2-.*-UNOFFICIAL-sapphire.*\.zip$" | tail -n 1)

if [ -n "$ROM_NAME" ]; then
    ROM_PATH="$ROM_DIR$ROM_NAME"
    echo -e "${CYAN}Uploading ROM to GoFile...${RESET}"
    ~/LineageOS-MicroG/gofile "$ROM_PATH"
    if [ $? -eq 0 ]; then
        print_header "ROM uploaded successfully to GoFile!"
    else
        echo -e "${RED}Failed to upload ROM to GoFile.${RESET}"
    fi
else
    echo -e "${YELLOW}ROM file not found. Upload skipped.${RESET}"
fi
