#!/bin/bash

# Configuration for log rotation
LOG_DIR="/var/log"
LOG_FILE="$LOG_DIR/user_management.log"
LOG_ROTATE_DAYS=7
MAX_LOG_FILES=5

# Function to handle log rotation
log_rotate() {
    # Rotate log files every $LOG_ROTATE_DAYS days
    if find "$LOG_FILE" -mtime +$LOG_ROTATE_DAYS > /dev/null 2>&1; then
        # Rename the current log file with a timestamp
        timestamp=$(date '+%Y-%m-%d-%H-%M-%S')
        if mv "$LOG_FILE" "$LOG_DIR/user_management-$timestamp.log"; then
            # Remove old log files (keep only the latest $MAX_LOG_FILES)
            if ! ls -1tr $LOG_DIR/user_management-*.log | head -n -$MAX_LOG_FILES | xargs -d '\n' rm -f --; then
                log "ERROR: Failed to remove old log files"
            fi
        else
            log "ERROR: Failed to rename log file"
        fi
    fi
}

# Set up logging and secure storage
PASSWORD_FILE="/var/secure/user_passwords.txt"

mkdir -p /var/secure || error_exit "Failed to create /var/secure directory"
touch $LOG_FILE || error_exit "Failed to create log file"
touch $PASSWORD_FILE || error_exit "Failed to create password file"

chmod 600 $PASSWORD_FILE || error_exit "Failed to set permissions on password file"

log() {
    if ! printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"; then
        echo "ERROR: Failed to write to log file" >&2
    fi
}

error_exit() {
    log "ERROR: $1"
    echo "ERROR: $1" >&2
    exit 1
}

# Automatically call log rotation
log_rotate

log "Script execution started"

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

# Function to verify user and groups
verify_user_and_groups() {
    local username="$1"
    local groups="$2"
    local result=0

    # Verify user exists
    if ! id -u "$username" > /dev/null 2>&1; then
        log "Verification failed: User $username does not exist"
        result=1
    fi

    # Verify group memberships
    IFS=',' read -ra group_array <<< "$groups"
    for group in "${group_array[@]}"; do
        if ! id -nG "$username" | grep -qw "$group"; then
            log "Verification failed: User $username is not in group $group"
            result=1
        fi
    done

    return $result
}

# Function to create and configure a user
create_and_configure_user() {
    local username="$1"
    local groups="$2"

    # Check if the user already exists
    if id -u "$username" > /dev/null 2>&1; then
        log "User $username already exists. Updating groups if necessary."
    else
        # Create the user's personal group if it doesn't exist
        if ! getent group "$username" > /dev/null; then
            if groupadd "$username"; then
                log "Created group: $username"
            else
                error_exit "Failed to create group: $username"
            fi
        fi

        # Create the user if they do not exist
        if useradd -m -g "$username" -G "$groups" "$username"; then
            log "Created user: $username with groups: $groups"
        else
            error_exit "Failed to create user: $username"
        fi

        # Generate a random password using pwgen
        password=$(pwgen -s -c -n 12 -1) || { error_exit "Failed to generate password"; }

        # Set the plain password for the user
        if echo "$username:$password" | chpasswd; then
            echo "$username,$password" >> $PASSWORD_FILE || error_exit "Failed to store plain password for user: $username"
            log "Generated password for user: $username"
        else
            error_exit "Failed to set password for user: $username"
        fi

        # Hash the password using bcrypt
        hashed_password=$(echo "$password" | openssl passwd -6 -stdin) || { error_exit "Failed to hash password"; }

        # Update the user's password with the hashed password
        if usermod --password "$hashed_password" "$username"; then
            log "Stored hashed password for user: $username"
        else
            error_exit "Failed to store hashed password for user: $username"
        fi
    fi

    # Create additional groups if they do not exist and assign user to groups
    IFS=',' read -ra group_array <<< "$groups"
    for group in "${group_array[@]}"; do
        if ! getent group "$group" > /dev/null; then
            if groupadd "$group"; then
                log "Created group: $group"
            else
                error_exit "Failed to create group: $group"
            fi
        fi
        if id -nG "$username" | grep -qw "$group"; then
            log "User $username is already in group $group"
        else
            if usermod -aG "$group" "$username"; then
                log "Added user $username to group $group"
            else
                error_exit "Failed to add user $username to group $group"
            fi
        fi
    done

    # Verify user and group assignments
    if verify_user_and_groups "$username" "$groups"; then
        log "Verification passed for user: $username"
    else
        log "Verification failed for user: $username"
    fi
}

# Read and parse the input file
while IFS=';' read -r username groups; do
    # Trim whitespace from username and groups
    username=$(echo "$username" | xargs)
    groups=$(echo "$groups" | xargs)
    
    log "Parsed username: $username, groups: $groups"
    
    # Create user and groups
    create_and_configure_user "$username" "$groups"

done < "$1" || error_exit "Failed to read input file"

log "Script execution completed"
