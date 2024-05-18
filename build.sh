#!/bin/bash

is_sudo_available() {
    if [ -z "$(command -v sudo)" ]; then
        echo 0
    else
        echo 1
    fi
}

install_dependencies() {
    if [ $(is_sudo_available) -eq 1 ]; then
        sudo apt update && sudo apt -y install pv cgpt tar unzip aria2
    else
        apt update && apt -y install pv cgpt tar unzip aria2
    fi
}

build_chromeos() {
    # verify chromeos-install.sh and chromeos.bin exist
    if [ ! -f chromeos-install.sh ]; then
        echo "chromeos-install.sh not found"
        exit 1
    fi
    if [ ! -f chromeos.bin ]; then
        echo "chromeos.bin not found"
        exit 1
    fi
    # check bash is available
    if [ -z "$(command -v bash)" ]; then
        echo "bash is not available. Please install bash"
        exit 1
    fi
    if [ $(is_sudo_available) -eq 1 ]; then
        sudo bash chromeos-install.sh -src chromeos.bin -dst chromeos.img
    else
        bash chromeos-install.sh -src chromeos.bin -dst chromeos.img
    fi
}

# ----- Chrome OS Code Names -----

# # Intel Processor
# 3rd gen or older: Samus
# 4th and 5th gen: Rammus
# 6th gen to 9th gen: Shyvana
# 10th gen: Jinlon
# 11th gen and newer: Voxel

# AMD Processor
# Ryzen: Gumboz

# For the given code name, head to https://cros.tech/device/${code_name} and find all a tag with url ending .zip, and choose the a.text with largest number
download_chromeos() {
    local code_name=$1
    local url="https://cros.tech/device/${code_name}"
    local response=$(curl -s --progress-bar $url)
    local link=$(echo $response | sed -n 's/.*<a[^>]*href="\([^"]*dl\.google\.com[^"]*\.zip\)"[^>]*>\([^<]*\)<\/a>.*/\1 \2/p' | awk '
    {
        # Extract the first number found in the text content
        if (match($2, /[0-9]+/)) {
            num = substr($2, RSTART, RLENGTH)
            if (num > max_num) {
                max_num = num
                max_link = $1
            }
        }
    }
    END {
        if (max_num != "") {
            print max_link
        } else {
            print "No valid links found"
        }
    }')
    if [ "$link" == "No valid links found" ]; then
        echo "No valid links found"
        exit 1
    fi
    echo "Downloading Chrome OS for $code_name"
    echo "Link: $link"
    aria2c -x 16 -o chromeos.zip $link
    echo "Download completed"
    echo "Extracting Chrome OS"
    unzip -o chromeos.zip -d chromeos
    echo "Extraction completed"
    echo "Deleting downloaded zip file"
    rm -f chromeos.zip
    echo "Downloaded and extracted Chrome OS for $code_name"
}

D_BRUNCH_COUNT = 0

download_brunch() {
    # Download latest brunch from https://github.com/sebanc/brunch
    # Release page: https://api.github.com/repos/sebanc/brunch/releases/latest
    # Choose first asset
    local url="https://api.github.com/repos/sebanc/brunch/releases/latest"
    local response=$(curl -s $url)
    local link=$(echo $response | sed -n 's/.*"browser_download_url": "\([^"]*\.tar\.gz\)".*/\1/p')
    if [ -z "$link" ]; then
        if [ $D_BRUNCH_COUNT -eq 2 ]; then
            echo "Failed to download brunch"
            exit 1
        else
            RANDOM_SEC=$((1 + RANDOM % 5))
            echo "Failed to download brunch. Retrying in $RANDOM_SEC seconds"
            sleep $RANDOM_SEC
            D_BRUNCH_COUNT=$((D_BRUNCH_COUNT+1))
            download_brunch
            return
        fi
    fi
    echo "Downloading brunch"
    echo "Link: $link"
    aria2c -x 16 -o brunch.tar.gz $link
    echo "Download completed"
    echo "Extracting brunch"
    mkdir -p brunch
    tar -xzvf brunch.tar.gz -C brunch
    echo "Extraction completed"
    echo "Deleting downloaded tar.gz file"
    rm -f brunch.tar.gz
    echo "Downloaded and extracted brunch"
}

post_download_setup() {
    # check if brunch and chromeos directories exist
    if [ ! -d brunch ]; then
        echo "brunch directory not found"
        exit 1
    fi
    if [ ! -d chromeos ]; then
        echo "chromeos directory not found"
        exit 1
    fi
    # copy all files from brunch to chromeos
    echo "Copying brunch files to chromeos..."
    cp -r brunch/* chromeos/
    echo "Copy completed"
    # Rename chromos*.bin to chromeos.bin
    mv chromeos/chromeos*.bin chromeos/chromeos.bin
}

build_chromos_img() {
    # change directory to chromeos
    cd chromeos
    # check if chromeos.bin exists
    if [ ! -f chromeos.bin ]; then
        echo "chromeos.bin not found"
        exit 1
    fi
    # check if chromeos-install.sh exists
    if [ ! -f chromeos-install.sh ]; then
        echo "chromeos-install.sh not found"
        exit 1
    fi
    # check if chromeos.img exists
    if [ -f chromeos.img ]; then
        echo "Deleting existing chromeos.img"
        rm -f chromeos.img
    fi
    echo "Building chromeos.img..."
    # build chromeos.img
    # if variable CHROMEOS_IMG_FILENAME is set, then use that as the filename else use chromeos.img
    # verify CHROMEOS_IMG_FILENAME contains .img
    if [ -z "$CHROMEOS_IMG_FILENAME" ]; then
        CHROMEOS_IMG_FILENAME="chromeos.img"
    else
        if [[ ! "$CHROMEOS_IMG_FILENAME" == *".img" ]]; then
            echo "CHROMEOS_IMG_FILENAME should contain .img"
            exit 1
        fi
    fi
    if [ $(is_sudo_available) -eq 1 ]; then
        sudo bash chromeos-install.sh -src chromeos.bin -dst $CHROMEOS_IMG_FILENAME
    else
        bash chromeos-install.sh -src chromeos.bin -dst $CHROMEOS_IMG_FILENAME
    fi
    if [ -f $CHROMEOS_IMG_FILENAME ]; then
        echo "$CHROMEOS_IMG_FILENAME created successfully"
    else
        echo "Failed to create $CHROMEOS_IMG_FILENAME"
    fi
}

# Execute functions in order
install_dependencies
# if previous command is successful, then only proceed
if [ $? -eq 0 ]; then
    if [ -z "$1" ]; then
        echo "Please provide Chrome OS code name"
        exit 1
    fi
    download_chromeos $1
    if [ $? -eq 0 ]; then
        download_brunch
        if [ $? -eq 0 ]; then
            post_download_setup
            if [ $? -eq 0 ]; then
                build_chromos_img
            else
                echo "Failed to setup post download"
                exit 1
            fi
        else
            echo "Failed to download brunch"
            exit 1
        fi
    else
        echo "Failed to download Chrome OS"
        exit 1
    fi
else
    echo "Failed to install dependencies"
    exit 1
fi
