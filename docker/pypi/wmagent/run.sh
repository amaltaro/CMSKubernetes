#!/bin/bash

### Basic initialization wrapper for WMAgent to serve as the main entry point for the WMAgent Docker container
wmaUser=$(id -un)
wmaGroup=$(id -gn)
wmaUserID=$(id -u)
wmaGroupID=$(id -g)
export WMA_USER=$wmaUser

echo "Running WMAgent container with user: $wmaUser (ID: $wmaUserID) and group: $wmaGroup (ID: $wmaGroupID)"

echo "Setting up bashrc for user: $wmaUser"
mv ${WMA_ROOT_DIR}/etc/wmagent_bashrc ~/.bashrc
source ~/.bashrc

echo "Start initialization"
./init.sh | tee -a $WMA_LOG_DIR/init.log || true

echo "Start sleeping now ...zzz..."
sleep infinity
