# DevOps User Creation Script

## Overview

This project involves creating a bash script to automate user and group management on a Linux system. The script reads a text file containing usernames and groups, creates users, assigns groups, sets up home directories, generates random passwords, and logs all actions.

## Usage

To use the script, provide a text file with usernames and groups, where each line is formatted as `user;groups`.

### Example Input File

alice;admin,dev
bob;dev,test
charlie;test


### Running the Script

Run the script with the input file as an argument:

```bash
sudo bash create_users.sh users.txt
```

Files Created
/var/log/user_management.log: Log of all actions performed by the script.
/var/secure/user_passwords.txt: Securely stored passwords for all users.

Requirements
Bash
OpenSSL
