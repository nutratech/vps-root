#!/bin/bash

# Execute this script to set up the minic10y user and directories on the nightly server.
# It will prompt for your SSH passphrase once.

VPS_HOST="nightly.nutra.tk"
VPS_USER="gg"

echo "Connecting to $VPS_HOST to set up minic10y user and directories..."

ssh -t "$VPS_USER@$VPS_HOST" "
    echo 'Creating user minic10y...'
    sudo useradd -m -s /bin/bash minic10y

    echo 'Adding minic10y to devs group...'
    sudo usermod -aG devs minic10y

    echo 'Setting up /var/lib/minic10y for sockets...'
    sudo mkdir -p /var/lib/minic10y
    sudo chown -R minic10y:minic10y /var/lib/minic10y
    sudo chmod -R 775 /var/lib/minic10y

    echo 'Done with permissions!'
"

echo "Setup script completed. You can now deploy and start the service."
