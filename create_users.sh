#!/bin/bash

# Configuration for log rotation
LOG_DIR="/var/log"
LOG_FILE="$LOG_DIR/user_management.log"
LOG_ROTATE_DAYS=7
LOG_MAX_FILES=5

# Function to handle log rotation
log_rotate() {
    # Rotate log files every $LOG_ROTATE_DAYS days
    if find "$LOG_FILE" -mtime +$LOG_ROTATE_DAYS > /dev/null 2>&1; then
        # Rename the current log file with a timestamp
        timestamp=$(date '+%Y-%m-%d-%H-%M-%S')
        if mv "$LOG_FILE" "$LOG_DIR/user_management-$timestamp.log"; then
            # Remove old log files (keep only the latest $LOG_MAX_FILES)
            if ! ls -1tr $LOG_DIR/user_management-*.log | head -n -$LOG_MAX_FILES | xargs -d '\n' rm -f --; then
                log "ERROR: Failed to remove old log files"
            fi
        else
            log "ERROR: Failed to rename log file"
        fi
    fi
}

# Set Up logging and secure storage
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

# Function to create a user
create_user() {
    local username="$1"
    local groups="$2"

    # Create the user's personal group
    if ! getent group "$username" > /dev/null; then
        if groupadd "$username"; then
            log "Created group: $username"
        else
            log "ERROR: Failed to create group: $username"
        fi
    fi

    # Create additional groups if they do not exist
    IFS=',' read -ra group_array <<< "$groups"
    for group in "${group_array[@]}"; do
        if ! getent group "$group" > /dev/null; then
            if groupadd "$group"; then
                log "Created group: $group"
            else
                log "ERROR: Failed to create group: $group"
            fi
        fi
    done

    # Create the user with their personal group and additional groups
    if ! id -u "$username" > /dev/null 2>&1; then
        if useradd -m -g "$username" -G "$groups" "$username"; then
            log "Created user: $username with groups: $groups"
        else
            log "ERROR: Failed to create user: $username"
            return 1
        fi

        # Generate a random password using pwgen
        password=$(pwgen -s -c -n 12 -1) || { log "ERROR: Failed to generate password"; return 1; }

        # Set the plain password for the user
        if echo "$username:$password" | chpasswd; then
            echo "$username,$password" >> $PASSWORD_FILE || log "ERROR: Failed to store plain password for user: $username"
            log "Generated password for user: $username"
        else
            log "ERROR: Failed to set password for user: $username"
            return 1
        fi

        # Hash the password using bcrypt
        hashed_password=$(echo "$password" | openssl passwd -6 -stdin) || { log "ERROR: Failed to hash password"; return 1; }

        # Update the user's password with the hashed password
        if usermod --password "$hashed_password" "$username"; then
            log "Stored hashed password for user: $username"
        else
            log "ERROR: Failed to store hashed password for user: $username"
            return 1
        fi

        # Assign the user to the specified groups
        for group in "${group_array[@]}"; do
            if usermod -aG "$group" "$username"; then
                log "Added user $username to group $group"
            else
                log "ERROR: Failed to add user $username to group $group"
            fi
        done
    else
        log "User $username already exists."
    fi
}

# Read and parse the input file
while IFS=';' read -r username groups; do
    # Trim whitespace from username and groups
    username=$(echo "$username" | xargs)
    groups=$(echo "$groups" | xargs)
    
    log "Parsed username: $username, groups: $groups"
    
    # Create user and groups
    create_user "$username" "$groups"

done < "$1" || error_exit "Failed to read input file"

log "Script execution completed"
