# openwrt-custom-builds
Custom NSS-enabled firmware images (compiled locally from source) for OpenWrt for the Dynalink DL-WRX36

# What does "NSS-enabled" mean?

In addition to the "general purpose" CPU, the dynalink dl-wrx36 (and all other ipq807x-based routers) have additional processors that are specifically designed to handle certain networking-related tasks. These extra processors and their related functionality are collectively known as the "Networking Sub-System", or NSS. 

In mainline OpenWrt, the NSS system is largely inactive and mostly just sits there idle and unused. In this NSS-enabled build, however, the NSS is active and takes over the vast majority of the networking stack. This both allows the router to process more traffic than what would be possible using the CPU (I only have only tested it on a 1 gbps connection; but, in theory, it should handle up to a 10 gbps connection). Using the NSS to handle networking stuff also frees up the CPU to do other potentially useful things (file sharing, recursive, DNS lookup, running a plex media server instance, etc.)

Enabling NSS is particularly beneficial for high-bandwidth connections - anyone with an internet connection with bandwidth of a few hundred mbps (or more) should notice distinctly better router performance. Those with connection speeds under ~100 mbps will likely see minimal improvements, and *might* see slightly better performance on mainline openwrt.

# Install instructions

This OpenWrt firmware image can be installed using the [standard WRX36 install instructions for OpenWrt](https://openwrt.org/toh/dynalink/dl-wrx36). 

Firmware images are located in the `WRX36/bin/target/qualcommax/ipq807x` directory. you will want either

* openwrt-qualcommax-ipq807x-dynalink_dl-wrx36-squashfs-sysupgrade.bin
* openwrt-qualcommax-ipq807x-dynalink_dl-wrx36-squashfs-factory.ubi

If you are already on OpenWrt, you can either install the sysupgrade image (e.g., though LUCI), or you can boot into the USB recovery and re-flash `/dev/mtd18` and `/dev/mtd20` with the factory squashfs image. 

Notes re: sysupgrade - On a few previous iterations of this build, sysupgrade refused to work over LUCI but worked when run from the commandline. Also, you can avoid having to "force" the update due to a "missing signature" error if, before doing the sysupgrade, you run

    opkg-key add key-build.pub

where `key-build.pub` is found in this repo at WRX36/bin/extra/keys

# Builtin default network setup

When you first flash the device:

* The default WiFi network name is "OpenWrt_WiFi" and the password is "password" for both 2g and 5g
* The wifi and LAN ports 1 - 3 will be on subnet 10.0.0.0/24 on the "lan" router interface. Access the router via ssh using `ssh root@10.0.0.1` or via LUCI by going to `10.0.0.1` in a web browser.
* LAN port 4 will be on subnet 192.168.1.0/24 on the "IoT" router interface. On this port, the router's address is 192.168.1.1, though access via SSH/LUCI is blocked. Devices on the "lan" interface can access those on the "IoT" interface but not vise-versa. 

The intended usage for LAN port 4 is to plug in a 2nd router in "dumb AP" mode and broadcast a secondary network (on different WiFi channels) for things like IoT devices (smart plugs/lights, alexa, google assistant, smart TV's, etc.). This both:

1. isolates them (and their more-often-than-not awful security) from your computers/phones/tablets, AND
2. it offloads them to other wifi channels so that they dont slow down the devices you actually care about having good wifi speeds on. 

If you dont want this then un-configuring LAN4 is fairly straightforward (much more so than setting it up)

NOTE: both DNS and DHCP are handled by `unbound` (with the help of `odhcpd` for DHCP). `adblock` is pre-setup to integrate with `unbound`. `unbound` has been compiled and setup to be as performant as possible, and is by default in "recursion" mode (not "forwarding" mode). `dnsmasq` is NOT installed.

# Reccomended initial setup steps

First, go to 10.0.0.1 in a web browser and in the "system" menu set your timezone and (optionally) desired hostname (default hostname is "OpenWrt"). After setting the timezone update the system clock (sync with NTP server). Note that `chrony` handled NTP and is setup to use a stratum 1 server with NTS enabled (encrypted ntp).

Second, in LUCI go into wifi settings and (in the roaming tab) turn on time advisement and select your time zone (for both 2g and 5g). Note: the correct time zone is only an option in the drop-down menu here if you first set it in the system tab. 

While you are in the wifi configuration tab, you should also probably change your wifi network name and password to whatever you want to use. If you change the wifi network name, next you should go into the `usteer` configuration tab (available in LUCI) and change the name of the network usteer does band steering for as well.

The last "initial setup" item Id reccomend is going to system->startup and disabling the services you know your wont use.

# Plex Media Server

There is an init script setup that will install and then auto start on boot a plex media server instance running on the router and serving media on an external hard drive. 

Plex media server setup and starting/stopping are controlled by the 'plexmediaserver' service. To control plex media server, use `service plexmediaserver <COMMAND>`. There are a handful of commands, but the most useful are `start`, `stop`, `restart`, and `update`.

If your external hard drive has a plexmediaserver instance on it already the plexmediaserver service *should* auto-detect it. If not, you can initialize one by running

    mkdir -p <external_drive_mount_point>/.plex/Library

Then run 

    service plexmediaserver start

and it *should* set everything up for you. If something isnt working right, try deleting the plexmediaserver config file then restart the plexmediaserver service. It will automatically re-generate the config for you, but only if it is missing (meaning that if the config exists but is wrong it wont automatically change it unless you delete it first).

    rm /etc/config/plexmediaserver
    service plexmediaserver restart

To access plex from a web browser, go to 10.0.0.1:32400/web.

NOTE: plexmediaserver requires `unzip` `curl` and `squashfs-tools-mksquashfs`. This build has them compiled in, but standard openwrt builds do not and will need them installed (using `opkg`)

# Installing packages

The standard 

    opkg update
    opkg install $PKG

will work. However, it may pull in and try to install kmod packages that may not be fully compatible with the device. A handful of extra kmod packages are available in this repo. When possible, I reccomend using the kmod packages from this repo if you need to install one.

***

Disclaimer: My wrx36 is running the firmware that the firmware image's in this repo were based on. The only difference in this firmware image and the one my wrx36 uses is that some configs that would share private info (like my wifi network name and password) were changed/removed. That said, I have not physically flashed this image to a router yet.

# KNOWN BUGS

Currently, to the best of my knowledge, everything is working correctly as it is supposed to (on my dynalink dl-wrx36 at least). That said, enabling the NSS subsystem on OpenWrt is about as cutting edge as openwrt gets. As such, the better performance that using NSS gives comes at the cost of bugs being more likely. If/when any bugs are reported I will list them below.

It is worth noting that this build does NOT include mesh support.
