#!/bin/bash
# Based on a combination of: http://www.isticktoit.net/?p=1383
#   and: https://www.raspberrypi.org/forums/viewtopic.php?t=260107
#   and: https://gist.github.com/schlarpc/a327d4aa735f961555e02cbe45c11667/c80d8894da6c716fb93e5c8fea98899c9aab8d89
#   and: https://github.com/ev3dev/ev3-systemd/blob/02caecff9138d0f4dcfeb5afbee67a0bb689cec0/scripts/ev3-usb.sh

configfs="/sys/kernel/config/usb_gadget"
this="${configfs}/libComposite"

# Configure values
serial="$(grep 'Serial' /proc/cpuinfo | head -n 1 | sed -E -e 's/^Serial\s+:\s+0000(.+)/\1/')"
model="$(grep 'Model' /proc/cpuinfo | head -n 1 | sed -E -e 's/^Model\s+:\s+(.+)/\1/')"
manufacturer="Raspberry Pi Foundation"

# The serial number ends in a mac-like address. Let's use this to build a MAC address.
#   The first binary xxxxxx10 octet "locally assigned, unicast" which means we can avoid
#   conflicts with other vendors.
mac_base="$(echo "${serial}" | sed 's/\(\w\w\)/:\1/g' | cut -b 4-)"
ecm_mac_address_dev="02${mac_base}"  # ECM/CDC address for the Pi end
ecm_mac_address_host="12${mac_base}" # ECM/CDC address for the "host" end that the Pi is plugged into
rndis_mac_address_dev="22${mac_base}"  # RNDIS address for the Pi end
rndis_mac_address_host="32${mac_base}" # RNDIS address for the "host" end that the Pi is plugged into

# Make sure that libComposite is loaded
libcomposite_loaded="$(lsmod | grep -e '^libcomposite' 2>/dev/null)"
[ -z "${libcomposite_loaded}" ] && modprobe libcomposite
while [ ! -d "${configfs}" ]
do
  sleep 0.1
done

# Make the path to the libComposite device
mkdir -p "${this}"

echo "0x0200"                      > "${this}/bcdUSB"       # USB Version (2)
echo "0x1d6b"                      > "${this}/idVendor"     # Device Vendor: Linux Foundation
echo "0x0104"                      > "${this}/idProduct"    # Device Type: MultiFunction Composite Device
echo "0x02"                        > "${this}/bDeviceClass" # This means it is a communications device

# Device Version (this seems a bit high, but OK)
# This should be incremented each time there's a "breaking change" so that it's re-detected
# rather than cached (apparently)
echo "0x4000"                      > "${this}/bcdDevice"

# "The OS_Desc config must specify a valid OS Descriptor for correct driver selection"
#   See: https://www.kernel.org/doc/Documentation/ABI/testing/configfs-usb-gadget
mkdir -p "${this}/os_desc"
echo "1"                           > "${this}/os_desc/use"           # Enable OS Descriptors
echo "0xcd"                        > "${this}/os_desc/b_vendor_code" # Extended feature descriptor: MS
echo "MSFT100"                     > "${this}/os_desc/qw_sign"       # OS String "proper"

# Configure the strings the device presents itself as
mkdir -p "${this}/strings/0x409"
echo "${manufacturer}"             > "${this}/strings/0x409/manufacturer"
echo "${model}"                    > "${this}/strings/0x409/product"
echo "${serial}"                   > "${this}/strings/0x409/serialnumber"

# Set up the ECM/CDC and RNDIS network interfaces as
#   configs/c.1 and configs/c.2 respectively.
for i in 1 2
do
  mkdir -p "${this}/configs/c.${i}/strings/0x409"
  echo "0xC0"                      > "${this}/configs/c.${i}/bmAttributes" # Self Powered
  echo "250"                       > "${this}/configs/c.${i}/MaxPower"     # 250mA
done

# Add the Serial interface
mkdir -p "${this}/functions/acm.usb0"
ln -s "${this}/functions/acm.usb0"   "${this}/configs/c.1/"

# Set up the ECM/CDC function
mkdir -p "${this}/functions/ecm.usb0"
echo "${ecm_mac_address_host}"     > "${this}/functions/ecm.usb0/host_addr"
echo "${ecm_mac_address_dev}"      > "${this}/functions/ecm.usb0/dev_addr"
echo "CDC"                         > "${this}/configs/c.1/strings/0x409/configuration"
ln -s "${this}/functions/ecm.usb0"   "${this}/configs/c.1/"

mkdir -p "${this}/functions/rndis.usb0"
mkdir -p "${this}/functions/rndis.usb0/os_desc/interface.rndis"
echo "RNDIS"                       > "${this}/functions/rndis.usb0/os_desc/interface.rndis/compatible_id"
echo "5162001"                     > "${this}/functions/rndis.usb0/os_desc/interface.rndis/sub_compatible_id"
echo "${rndis_mac_address_host}"   > "${this}/functions/rndis.usb0/host_addr"
echo "${rndis_mac_address_dev}"    > "${this}/functions/rndis.usb0/dev_addr"
echo "RNDIS"                       > "${this}/configs/c.2/strings/0x409/configuration"
ln -s "${this}/configs/c.2"          "${this}/os_desc"
ln -s "${this}/functions/rndis.usb0" "${this}/configs/c.2/"

udevadm settle -t 5 || true
ls /sys/class/udc > "${this}/UDC"

systemctl start getty@ttyGS0.service