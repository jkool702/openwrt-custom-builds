#!/usr/bin/env bash

# # # # # USER SPECIFIED OPTIONS

# set main buildroot
buildroot_dir="/mnt/ramdisk"

# optional - set paths where you can find the [diff]config, kernel config, and "files" directory needs from a previous build
# if any of the below are set and a file/dir exists at the specified path, it will automatically be incorporated into the build
# comment out (or unset if you already ran) any of the below that you dont want automatically added to the build
prev_files_dir_path="${buildroot_dir}"/openwrt-custom-builds/WRX36/bin/extra/files
prev_diff_config_path="${buildroot_dir}"/openwrt-custom-builds/WRX36/bin/extra/configs/.config.diff
prev_kernel_config_path="${buildroot_dir}"/openwrt-custom-builds/WRX36/bin/extra/configs/.config.kernel

# ALT -if you dont have a previous diffconfig (.config.diff) but have a previous full config (.config), specify its path below. 
# Be sure to comment out (or unset if already run) the above line that sets "prev_diff_config_path"
# prev_full_config_path="${buildroot_dir}"/openwrt-custom-builds/WRX36/bin/extra/configs/.config

# choose whether or not to build on a tmpfs
# 'false', '0' --> disable. Anything else (nonempty) --> enable
# if blank/unset, defaults to true if your system has >63 gigs ram and false otherwise
# tmpfs_build_flag=true

# # # # # BEGIN SCRIPT

# get system memory 
read -r memKB < /proc/meminfo
memKB="${memKB% *}"
memKB="${memKB#* }"

# set tmpfs_build_flag to false if empty+unset --OR-- to true if nonempty+set (to anything other than 'false' or '0')
if [[ "${tmpfs_build_flag}" == '0' ]] || [[ "${tmpfs_build_flag}" == 'false' ]]; then
    tmpfs_build_flag=false
elif [[ ${tmpfs_build_flag} ]]; then
    tmpfs_build_flag=true
elif (( ${memKB} > 66060288 )); then
    tmpfs_build_flag=true
else
    tmpfs_build_flag=false
fi

# make build directory 
mkdir -p "${buildroot_dir}"

# mount tmpfs to it (if it doesnt already have one and tmpfs_build_flag is set)
# unless your system has a substantial amount of ram (64gb or more) you should probably either:
# not set tmpfs_build_flag --OR-- enable the "automatic removal of build directories" (set "CONFIG_AUTOREMOVE=y" in .config)
${tmpfs_build_flag} && {
    grep -F "${buildroot_dir}" </proc/mounts | grep -q 'tmpfs' || {
        sudo mount -t tmpfs tmpfs "${buildroot_dir}" -o defaults -o size=$(( ( memKB * 1024 * 3 ) / 4 ))
    }
}

# download custom firmware repo (to grab config files) to "${buildroot_dir}"/openwrt-custom-builds
cd "${buildroot_dir}"
git clone https://github.com/jkool702/openwrt-custom-builds.git --branch=dynalink_wrx36_NSS_build

mkdir -p "${buildroot_dir}/build"
cd "${buildroot_dir}/build"
git clone https://github.com/jkool702/openwrt.git --branch=main-nss
cd "${buildroot_dir}/build/openwrt"
git fetch

# add some extra useful packages
git clone --depth 1 --branch master --single-branch --no-tags --recurse-submodules https://github.com/fantastic-packages/packages package/fantastic_packages

# install packages from feeds
./scripts/feeds update -a
./scripts/feeds install -a
./scripts/feeds install -a

# move in files and configs from previous build
[[ "${prev_files_dir_path}" ]] && [[ -d "${prev_files_dir_path}" ]] && cp -r "${prev_files_dir_path}" ./
[[ "${prev_kernel_config_path}" ]] && [[ -f "${prev_kernel_config_path}" ]] && cp "${prev_kernel_config_path}" .config.kernel.prev || touch .config.kernel.prev
if [[ "${prev_diff_config_path}" ]] && [[ -f "${prev_diff_config_path}" ]]; then
    cp "${prev_diff_config_path}" .config
elif [[ "${prev_full_config_path}" ]] && [[ -f "${prev_full_config_path}" ]]; then
    cp "${prev_full_config_path}" .config
    ./scripts/diffconfig > .config.diff
    \mv -f .config.diff .config 
fi

# get target board
target_board="$(grep -F CONFIG_TARGET_BOARD <.config | sed -E 's/^[^"]*"//;s/".*$//')"

# make copy of default target config(s)
for nn in find target/linux/${target_board}/config-*; do
    cp $nn .config.target.orig0.${nn##*/}
done

# speed up downloading GNU software. https://ftpmirror.gnu.org will automatically pick a nearby mirror for you. Not needed if using my github repo.
# echo "$(cat scripts/download.pl | sed -zE s/'(elsif \(\$mirror \=\~ \/\^\\\@GNU\\\/\(\.\+\)\$\/\) \{[^p]+push \@mirrors\, )[^\}]+\}'/'\1"https:\/\/ftpmirror.gnu.org\/$1"\n\t}'/)" > scripts/download.pl

# configure openwrt settings.
make menuconfig

# generate diffconfig
./scripts/diffconfig > .config.diff

 grep -qE '^CONFIG_AUTOREMOVE=y$' <.config && config_autoremove_flag=true || config_autoremove_flag=false

# ALT - run this instead of `make menuconfig` if you dont want to change anything.
# make defconfig

# download/check sources, then build unmodified kernel 
make -j$(nproc) download 

# force fix package hash mis-matches
C="$(make check | grep -B 1 PKG_MIRROR_HASH)"
mapfile -t B < <(grep PKG_MIRROR_HASH <<<"$C" | sed -E s/'^.* '//)
mapfile -t A < <(grep directory <<<"$C" | sed -E 's/^.* '"'"'//;s/'"'"'$//')
for kk in "${!A[@]}"; do
    sed -iE s/'^PKG_MIRROR_HASH.*$'/'PKG_MIRROR_HASH:='"${B[$kk]}"'/' "${A[$kk]}"'/Makefile'
done

# confirm check doesnt flag anything (there should be no red output)
make -j$(nproc) V=sc check  

# we need to disable automatic build directory removal for the kernel build (if it is set)
if ${config_autoremove_flag}; then
    # build tools+toolchain
    make -j$(nproc) V=sc prepare_kernel_conf
    cp .config .config.save
    { grep -vE '^CONFIG_AUTOREMOVE=y$' <.config.save; echo '# CONFIG_AUTOREMOVE is not set'; } >.config
fi

# build [tools+toolchain+]kernel (unmodified default kernel)
make -j$(nproc) V=sc prepare 

# save important target/kernel config paths in variables
# if the target supports 2 different kernel versions this *should* correctly choose the one that you are using
target_kconfig="$(find target/linux/${target_board}/config-* -maxdepth 0)"
(( $(wc -l <<<"${target_kconfig}") > 1 )) && {
    if grep -qF 'CONFIG_TESTING_KERNEL=y' <.config; then
        target_kconfig0="${target_kconfig%%$'\n'*}"
        target_kconfig="${target_kconfig#*$'\n'}"
    else
        target_kconfig0="${target_kconfig#*$'\n'}"
        target_kconfig="${target_kconfig%%$'\n'*}"
    fi
}
target_kconfig="$(realpath "${target_kconfig}")"
builddir_kernel=(build_dir/target*/linux-${target_board}*/linux-${target_kconfig##*config-}*)
[[ -z ${builddir_kernel} ]] && {
    target_kconfig="$(realpath "${target_kconfig0}")"
    builddir_kernel=(build_dir/target*/linux-${target_board}*/linux-${target_kconfig##*config-}*)
}
builddir_kernel="$(realpath "${builddir_kernel}")"
builddir_kconfig="${builddir_kernel}"/.config

# copy the target config after menuconfig configuring
cp "$target_kconfig" .config.target.orig0

# copy full default config of the (just built) default kernel
\mv -f "${builddir_kconfig}" .config.kernel.orig

# copy the full path of the orig kernel config (i.e., copy (ctrl+shift+c) the output of the below command)
realpath .config.kernel.orig

# generate the partial changes to the target config-x.y by loading the .config from the default kernel build
# NOTE: ***DONT CHANGE ANYTHING*** in this kernel_menuconfig!!!! load the ".config.kernel.orig" and save as ".config" exit. 
# go to "LOAD", paste the path of the ".config.kernel.orig" that you just copied, press enter, then save as ".config" and exit.
# this will automatically add required items to the target config-x.y
make target/linux/clean kernel_menuconfig

# copy the target (post-menuconfig with all automatic changes) target config
cp ${target_kconfig} .config.target.orig

# generate various diffs to layer on the the original full kernel config

# diff orig full kernel config and kernel config downloaed from repo
diff .config.kernel.prev .config.kernel.orig | grep -E '^<' | sed -E s/'^< '// > .config.kernel.prev.diff

# diff original (pre-menuconfig) target config and full (post-menuconfig with all automatic changes) target config
diff .config.target.orig0.${target_kconfig##*/} .config.target.orig | grep -E '^<' | sed -E s/'^< '// > .config.target.orig.diff

# layer full kernel config --> differernces to kernel config from repo --> differences to target config based on menuconfig choices
# the idea here is that automatic changesd to the kernel probably are being made for a good reason,
# so those will take precedence over changes to make the kernel config match the one downloaded from the github repo
cat .config.kernel.orig .config.kernel.prev.diff .config.target.orig.diff > .config.kernel

# copy the full path of the unprocessed kernel config (i.e., copy (ctrl+shift+c) the output of the below command)
realpath .config.kernel

# generate the changes to the target config-x.y required to incorporate changes from the downloaded kernel config from the repo
# NOTE: ***BEFORE CHANGING ANYTHING***:  load the ".config.kernel" 
# go to "LOAD", paste the path of the ".config.kernel" that you just copied, press enter
# NOW YOU CAN CHANGE STUFF (should you want to...you dont *have* to further tweak the kernel)
# After loading the .config.kernel and (optionally) further tweaking the kernel, save as ".config" and exit. 
# All required changes will be automatically saved to the target .config-x.y
make kernel_menuconfig 

# rebuild kernel with all kernel config tweaks present
make -j$(nproc) V=sc target/linux/clean prepare

# copy final target and kernel config
mv .config.kernel .config.kernel.old
cp "$builddir_kconfig" .config.kernel
cp "$target_kconfig" .config.target

# add missing kernel module info to build by including them in the files/lib/modules/<kernel_ver> (this makes `depmod` work better)
mkdir -p files/lib/modules/"${builddir_kernel##*/linux-}"
\cp -f "${builddir_kernel}"/{,.}{m,M}od* files/lib/modules/"${builddir_kernel##*/linux-}"
find files/lib/modules/"${builddir_kernel##*/linux-}" -type f -empty -exec rm {} +

# we need to re-enable automatic build directory removal for the rest of the build (if CONFIG_AUTOREMOVE set)
${config_autoremove_flag} && \mv -f .config.save .config

# make the rest of the build
make -j$(nproc) -k V=sc

# optional: gather some useful things from the build and add them to bin/extra
mkdir -p bin/extra/keys
mkdir -p bin/extra/configs
cp key-build* bin/extra/keys
cp .config* bin/extra/configs
cp -r files bin/extra

