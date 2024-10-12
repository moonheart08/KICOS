git clean -fx -e localbuild.cfg
# Generate tar archive for the disk.
tar --format ustar -cf installer_disk_template\disk.tar -C disk_template *