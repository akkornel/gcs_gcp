#!/bin/bash

# Safe shell settings (from https://sipb.mit.edu/doc/safe-shell/)
set -euf -o pipefail

# Set the umask so that all the files we create are accessible by others.
umask 0022

# Set up the venv and update pip
mkdir /opt/gcs_gcp
python3 -m venv --system-site-packages /opt/gcs_gcp
/opt/gcs_gcp/bin/pip install --upgrade pip wheel

# Install code into the venv
/opt/gcs_gcp/bin/pip install --use-feature=in-tree-build /tmp/workspace/code/

# Purge the pip cache
/opt/gcs_gcp/bin/pip cache purge

# Load the gcsgcp venv on interactive login shells.
cat - > /etc/profile.d/gcs_gcp.sh <<EOF
#!/bin/sh

# When run as an interactive login shell, activate the gcs_gcp venv.
# This gives easy access to the gcsgcp commands.
. /opt/gcs_gcp/bin/activate
EOF
chmod a+x /etc/profile.d/gcs_gcp.sh
. /etc/profile.d/gcs_gcp.sh

# All done!
exit 0
