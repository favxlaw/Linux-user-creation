#!/bin/bash

# Set Up logging and secure storage
LOG_FILE="/var/log/user_management.log"
PASSWORD_FILE="/var/secure/user_passwords.txt"
LOG_ROTATE_DAYS=30
LOG_MAX_FILES=5

mkdir -p /var/secure
touch $LOG_FILE
touch $PASSWORD_FILE
chmod 600 $PASSWORD_FILE

log() {
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

log "Script execution started"

# Log file rotation
log_rotate() {
    if [ $(find "$LOG_FILE" -mtime +$LOG_ROTATE_DAYS 2>/dev/null) ]; then
        timestamp=$(date '+%Y-%m-%d-%H-%M-%S')
        mv "$LOG_FILE" "/var/log/user_management-$timestamp.log" || error_exit "Failed to rotate log file"
        find /var/log/ -name "user_management-*.log" -mtime +$LOG_ROTATE_DAYS -exec rm {} \; | tail -n +$LOG_MAX_FILES
    fi
}

# Check if the input file is provided, is a regular file, and is readable
if [ -z "$1" ]; then
    error_exit "No input file provided. Usage: $0 <input-file>"
elif [ ! -f "$1" ]; then
    error_exit "Input file $1 is not a regular file."
elif [ ! -r "$1" ]; then
    error_exit "Input file $1 not found or not readable."
else
    log "Input file $1 is valid, regular, and readable."
fi

# Function to create user
create_user() {
    local username="$1"
    local groups="$2"

    # Create the user's personal group
    if ! getent group "$username" > /dev/null; then
        groupadd "$username" || error_exit "Failed to create group: $username"
        log "Created group: $username"
    fi

    # Create additional groups if they do not exist
    IFS=',' read -ra group_array <<< "$groups"
    for group in "${group_array[@]}"; do
        if ! getent group "$group" > /dev/null; then
            groupadd "$group" || error_exit "Failed to create group: $group"
            log "Created group: $group"
        fi
    done

    # Create the user with their personal group and additional groups
    if ! id -u "$username" > /dev/null 2>&1; then
        useradd -m -g "$username" -G "$groups" "$username" || error_exit "Failed to create user: $username"
        log "Created user: $username with groups: $groups"

        # Generate a random password for the user
        password=$(pwgen -s -c -n 12 -1)
        echo "$username:$password" | chpasswd || error_exit "Failed to set password for user: $username"
        echo "$username,$password" >> $PASSWORD_FILE
        log "Generated password for user: $username"
    else
        log "User $username already exists."
    fi

    # Assign the user to the specified groups
    for group in "${group_array[@]}"; do
        usermod -aG "$group" "$username" || log "Failed to add user $username to group $group"
        log "Added user $username to group $group"
    done
}

# Read and parse the input file
while IFS=';' read -r username groups; do
    # Trim whitespace from username and groups
    username=$(echo "$username" | xargs)
    groups=$(echo "$groups" | xargs)

    # Log the parsed username and groups
    log "Parsed username: $username, groups: $groups"

    # Split groups by comma and iterate over each group
    IFS=',' read -ra group_array <<< "$groups"
    for group in "${group_array[@]}"; do
        # Trim whitespace from each group name
        group=$(echo "$group" | xargs)
        log "Group for $username: $group"
    done

    create_user "$username" "$groups"

done < "$1"

# Rotate logs at the end of the script execution
log_rotate

log "Script execution completed"
