#!/bin/bash

SMART_FILE_MANAGER="$HOME/smart_file_manager"
BACKUP_DIR="$SMART_FILE_MANAGER/backups"
mkdir -p "$SMART_FILE_MANAGER/compress/"
mkdir -p "$SMART_FILE_MANAGER/decompress/"
mkdir -p "$BACKUP_DIR"

add_log() {
    echo "$(date '+%F %T') - $1" >> $SMART_FILE_MANAGER/smart_file_manager.log
}

stop() {
    read -p "Press [Enter] to continue..."
}

check_command() {
    while true; do
        read -p "Do you want to check type command here or Press [Enter] to Menu... " command
        if [[ -z "$command" ]]; then
            break
        fi
        $command
    done
}

show_file_and_directory() {
    read -p "Path: " path
    read -p "Filter By (e.g 1K, 1M, 1G): " size

    file_count=0
    dir_count=0

    echo -e "\nFiles:"
    for item in "$path"/*; do
        if [[ -f "$item" ]]; then
            item_size=$(du -h "$item" | awk '{print $1}')
            if [[ "$item_size" > "$size" ]]; then
                echo -e "- \e[36m$(basename "$item")\e[0m - $item_size"
                ((file_count++))
            fi
        fi
    done

    echo -e "\nDirectories:"
    for item in "$path"/*; do
        if [[ -d "$item" ]]; then
            dir_size=$(du -h "$item" | awk '{print $1}')
            if [[ "$dir_size" > "$size" ]]; then
                echo -e "- \e[32m$(basename "$item")\e[0m - $dir_size"
                ((dir_count++))
            fi
        fi
    done

    echo -e "\nTotal file count: $file_count"
    echo "Total directory count: $dir_count"
    path_used=$(du -sb "$path" | awk '{print $1}')
    fs_total=$(df -B1 "$path" | awk 'NR==2 {print $2}')
    fs_total_v=$(df -h "$path" | awk 'NR==2 {print $2}')
    if [[ $fs_total -gt 0 ]]; then
        percent_used=$(( path_used * 100 / fs_total ))
    else
        percent_used=0
    fi
    path_used_v=$(du -sh "$path" | awk '{print $1}')
    echo "Total used: $path_used_v"
    echo -e "\nThis directory uses: \e[33m$percent_used%\e[0m of its total volume (\e[36m$fs_total_v\e[0m)"

    add_log "Show files/dirs in $path filtered by size > $size"
    check_command
}



search_by_name_or_content() {
    read -p "path : " path
    read -p "search by filename or content [f/c]: " type
    read -p "search for: " keyword

    echo -e "\nSearch Results:\n"

    if [[ "$type" == "f" ]]; then
    find "$path" -iname "*$keyword*" 2>/dev/null
    elif [[ "$type" == "c" ]]; then
        grep -rnw "$path" -e "$keyword" 2>/dev/null
    else
        echo "Invalid type. Use 'filename' or 'content'."
    fi
    add_log "Search in $path by $type for '$keyword'"
    check_command
}

compress_or_decompress() {
    read -rp "Enter file or folder path: " target

    if [[ -d "$target" ]]; then
        archive_name="${target##*/}_$(date +%F).tar.gz"
        tar -czf "$SMART_FILE_MANAGER/compress/$archive_name" "$target"
        echo "Compressed folder to: $SMART_FILE_MANAGER/compress/$archive_name"
        add_log "Compressed directory $target to $SMART_FILE_MANAGER/compress/$archive_name"
    
    elif [[ -f "$target" ]]; then
        case "$target" in
            *.tar.gz)
                tar -xzf "$target" -C "$SMART_FILE_MANAGER/decompress/"
                echo "Decompressed: $target into $SMART_FILE_MANAGER/decompress/"
                add_log "Decompressed archive $target into $SMART_FILE_MANAGER/"
                ;;
            *)
                archive_name="$(basename "$target")_$(date +%F).tar.gz"
                tar -czf "$SMART_FILE_MANAGER/compress/$archive_name" "$target"
                echo "Compressed file to: $SMART_FILE_MANAGER/compress/$archive_name"
                add_log "Compressed file $target to $SMART_FILE_MANAGER/compress/$archive_name"
                ;;
        esac
    else
        echo "Invalid path."
    fi
    check_command
}

remove_empty_and_cache() {
    read -rp "path: " path
    echo "Removing empty files..."
    find "$path" -type f -empty -delete

    echo "Removing cache/log/tmp files..."
    find "$path" -type f \( -name "*.log" -o -name "*.tmp" -o -name "*.cache" \) -delete

    add_log "Removed empty files and cache from - $path"
    echo "Cleanup done."
    stop
}

backup_file_or_directory() {
    read -rp "Enter file or directory path to backup: " path

    if [[ -f "$path" ]]; then
        cp "$path" "$BACKUP_DIR/$(basename "$path")_backup_$(date +%F_%H%M%S)"
        echo "File backed up to $BACKUP_DIR"
        add_log "Backed up file $path"
    elif [[ -d "$path" ]]; then
        read -rp "Enter file extension to backup (e.g., .txt): " ext
        find "$path" -type f -name "*$ext" | while read -r file; do
            cp "$file" "$BACKUP_DIR/$(basename "$file")_backup_$(date +%F_%H%M%S)"
        done
        echo "Files with $ext backed up to $BACKUP_DIR"
        add_log "Backed up .$ext files from $path"
    else
        echo "Invalid path."
    fi
    check_command
}

while true; do
    clear
    echo "Smart File Manager"
    echo "=========================="
    echo "1. Show file and directory (filtered by size)"
    echo "2. Search by content or name"
    echo "3. Compress or decompress"
    echo "4. Remove empty file and cache"
    echo "5. Backup file or directory"
    echo "6. Exit"
    read -p "Choose [1-6]: " choice

    case $choice in
        1) show_file_and_directory ;;
        2) search_by_name_or_content ;;
        3) compress_or_decompress ;;
        4) remove_empty_and_cache ;;
        5) backup_file_or_directory ;;
        6) echo "Goodbye!"; exit;;
        *) echo "Invalid option." ; pause ;;
    esac
done
