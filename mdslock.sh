#!/bin/bash

clear_mds_lock_with_timeout() {
    echo "Clearing mds.install.lock and restarting installd process..."
    perl -e 'alarm shift; exec @ARGV' 600 bash -c "
        sudo rm -f /private/var/db/mds/system/mds.install.lock
        sudo killall -1 installd
    " || echo "Warning: mds/install lock clearance may have timed out after 10 minutes."
}

#execute the function
clear_mds_lock_with_timeout
