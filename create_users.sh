#!/bin/bash

# Set Up logging and secure storage
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.txt"

mkdir -p /var/secure
touch $LOG_FILE
touch $PASSWORD_FILE

chmod 600 $PASSWORD_FILE

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

log "Script execution started"

# Check if the input file is provided, is a regular file, and is readable
if [ -z "$1" ]; then
    log "No input file provided."
    echo "Usage: $0 <input-file>"
    exit 1
elif [ ! -f "$1" ]; then
    log "Input file $1 is not a regular file."
    echo "Error: Input file $1 is not a regular file."
    exit 1
elif [ ! -r "$1" ]; then
    log "Input file $1 not found or not readable."
    echo "Error: Input file $1 not found or not readable."
    exit 1
else
    log "Input file $1 is valid, regular, and readable."
fi

# Function to create a user
create_user() {
    local username="$1"
    local groups="$2"

    # Create the user's personal group
    if ! getent group "$username" > /dev/null; then
        groupadd "$username"
        if [ $? -eq 0 ]; then
            log "Created group: $username"
        else
            log "Failed to create group: $username"
            return 1
        fi
    fi

    # Create additional groups if they do not exist
    IFS=',' read -ra group_array <<< "$groups"
    for group in "${group_array[@]}"; do
        if ! getent group "$group" > /dev/null; then
            groupadd "$group"
            if [ $? -eq 0 ]; then
                log "Created group: $group"
            else
                log "Failed to create group: $group"
                return 1
            fi
        fi
    done

    # Create the user with their personal group and additional groups
    if ! id -u "$username" > /dev/null 2>&1; then
        useradd -m -g "$username" -G "$groups" "$username"
        if [ $? -eq 0 ]; then
            log "Created user: $username with groups: $groups"
            
            # Generate a random password for the user
            password=$(openssl rand -base64 12)
            echo "$username:$password" | chpasswd
            echo "$username,$password" >> $PASSWORD_FILE
            log "Generated password for user: $username"
        else
            log "Failed to create user: $username"
            return 1
        fi
    else
        log "User $username already exists."
    fi
}

# Read and parse the input file
while IFS=';' read -r username groups; do
    # Trim whitespace from username and groups
    username=$(echo "$username" | xargs)
    groups=$(echo "$groups" | xargs)
    
    # Log the parsed username and groups
    log "Parsed username: $username, groups: $groups"
    
    # Create user and groups
    create_user "$username" "$groups"

done < "$1"

log "Script execution completed"
