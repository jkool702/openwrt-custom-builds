# openwrt-custom-builds
Custom firmware images (compiled locally from source) for OpenWrt

# Install instructions

This OpenWrt firmware image can be installed using the [standard WRX36 install instructions for OpenWrt](https://openwrt.org/toh/dynalink/dl-wrx36).

Firmware images are located in the `WRX36/bin/target/qualcommax/ipq8074a` directory.

If you are already on OpenWrt, you can either install the sysupgrade squashfs image (e.g., though LUCI), or you can boot into the USB recovery and re-flash mt18 and mt20 with the factory squashfs image. 

# Initial network configuration

When you first flash the device:

* The wifi and LAN ports 1 - 3 will be on subnet 10.0.0.0/24 on the "lan" router interface. Access the router via ssh using `ssh root@10.0.0.1` or via LUCI by going to `10.0.0.1` in a web browser.

* The default WiFi network name is "OpenWrt_WiFi" and the password is "123456789" for both 2g and 5g

* LAN port 4 will be on subnet 192.168.1.0/24 on the "IoT" router interface. On this port, the router's address is 192.168.1.1, though access via SSH/LUCI is blocked. Devices on the lan interface can access those on the IoT interface but not vise-versa. 

NOTE: The intended usage for LAN port 4 is to plug in a 2nd router in "dumb AP" mode and broadcast a secondary network (on different WiFi channels) for things like IoT devices (smart plugs/lights, alexa, google assistant, smart TV's, etc.). This both:

1. isolates them (and their more-often-than-not awful security) from your computers/phones/tablets, AND
2. it offloads then to other wifi channels so that tey dont slow down the devices you actually care about having good wifi speeds.

# Reccomended initial setup steps

First, go to 10.0.0.1 in a web browser and in the "system" menu set your timezone and desired hostname (default hostname is "OpenWrt").

Note: if you change the hostname, you will have to change it a few other places as well. In LUCI:

1. network - interfaces -> dhcp -> advanced, remove the `12,OpenWrt` antry and add a `12,NEW_HOSTNAME` entry. Do this for both lan and IoT.
2. If you want to use ksmbd, there are a few places where you should change the fields with `OpenWrt` or `OPENWRT` to your new hostname (keep all caps on the options that have `OPENWRT` by default)

Second, in LUCI go into wifi settings and (in the roaming tab) turn on time advisement and select your time zone (for both 2g and 5g). Note: the correct time zone is only an option in the drop-down menu here if you first set it in the system tab. 

While you are in the wifi configuration tab, you should also probably change your wifi network name and password to whatever you want to use. If you change the wifi network name, next you should go into the `usteer` configuration tab (available in LUCI) and change the name of the network usteer does band steering for as well.

The last "initial setup" item Id reccomend is going to system->startup and disabling the services you know your wont use.

Note: you should disable the "plexmediaserver" startup service in this menu, regardless if you want to use plex media server. See below for instructions to setup and auto-start plex media server on boot.

# Plex Media Server

There is an init script setup that will install and then auto start on boot a plex media server instance running on the router and serving media on an external hard drive. 

To set this up, in LUCI go system->startup->local startup, and 

1. replace all instances of `${plex_dev}` with the block devine name of the external drive. This will probably be `/dev/sda1` or `/dev/sda2`
2. replace all instances of `${plex_mnt}` with the desired mount point for the drive. Example: `/mnt/plex`. Note: do NOT include the trailing `/`.

Then reboot. On boot up, it should install plex media server and start it for you. (note: it might take a minute to build the squashfs image of it for you).

To control plex media server, use `service plexmediaserver <COMMAND>`. There are a handful of commands, but the most useful are `start`, `stop`, and `update`.

To access plex from a web browser, go to 10.0.0.1:32400/web.

# Installing packages

The standard 

    opkg update
    opkg install $PKG

will work. However, it may pull in and try to install kmod packages that may not be fully compatable with the device. Most kmod packages are available in this repo ([here](https://github.com/jkool702/openwrt-custom-builds/tree/main/WRX36/bin/targets/qualcommax/ipq807x/packages/kmods)) - be sure to use the kmod packages from this repo if you need to install one.
