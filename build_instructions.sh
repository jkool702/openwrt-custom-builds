#!/usr/bin/env bash

buildroot_dir="/mnt/ramdisk"
bin_dir="${buildroot_dir}"/openwrt-custom-builds/WRX36/bin

# NOTE; In my github repo openwrt fork, I have corrected the listing for the dynalink so that the SOC is listed as ipq8074, not ipq8072. This may or may not have had an impact on the resulting image.

# make build directory and clone github repo
mkdir -p "${buildroot_dir}"
cat /proc/mounts | grep -F "${buildroot_dir}" | grep -q 'tmpfs' || sudo mount -t tmpfs tmpfs "${buildroot_dir}" -o defaults -o size=96G

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
./scripts/feeds install -a;

# move in files and configs
cp -r "${bin_dir}"/extra/files ./
cp "${bin_dir}"/extra/configs/{.config,.config.kernel} ./

# speed up downloads. Not needed if using my github repo
# echo "$(cat scripts/download.pl | sed -zE s/'(elsif \(\$mirror \=\~ \/\^\\\@GNU\\\/\(\.\+\)\$\/\) \{[^p]+push \@mirrors\, )[^\}]+\}'/'\1"https:\/\/gnu.mirror.constant.com\/$1"\n\t}'/)" > scripts/download.pl

# configure openwrt settings
make menuconfig

# ALT:
# make defconfig

# download/check sources, then build unmodified kernel 
make -j$(nproc) download 

# fix package hash mis-matches
C="$(make check | grep -B 1 PKG_MIRROR_HASH)"
mapfile -t B < <(grep PKG_MIRROR_HASH <<<"$C" | sed -E s/'^.* '//)
mapfile -t A < <(grep directory <<<"$C" | sed -E 's/^.* '"'"'//;s/'"'"'$//')

for kk in "${!A[@]}"; do
    sed -iE s/'^PKG_MIRROR_HASH.*$'/'PKG_MIRROR_HASH:='"${B[$kk]}"'/' "${A[$kk]}"'/Makefile'
done

make -j$(nproc) V=sc check prepare 

# save important paths in variables
target_board="$(grep -F CONFIG_TARGET_BOARD <.config | sed -E 's/^[^"]*"//;s/".*$//')"
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

# copy full default config of the (just built) default kernel
\mv -f "${builddir_kconfig}" .config.kernel.orig

# generate the partial .config (for the kernel that kernel_menuconfig by default shows) in the kernel build dir
# NOTE: ***DONT CHANGE ANYTHING*** in this kernel_menuconfig - immediately save it (to .config) and exit. 
make kernel_menuconfig

# diff and add to target config to get target diffconfig of full default kernel config
diff .config.kernel.orig "${builddir_kconfig}" | grep '<' | sed -E s/'^< '// | tee -a .config.kernel.diff0 
cat .config.kernel.diff0 >> "${target_kconfig}"

# do this a second time to pull in all the changes in my ciustom kernel
diff ${bin_dir}/extra/configs/.config.kernel .config.kernel.orig | grep '<' | sed -E s/'^< '// | tee -a .config.kernel.diff1 
cat .config.kernel.diff1 >> "${target_kconfig}"

# remove incomplete .config out of kernel build dir
\rm -f  "${builddir_kconfig}" 

# regenerate .config (which gives the full complete kernel .config + my modifictions) and save as ".config" 
# OPTIONAL: actually custom configure the kernel this time 
make kernel_menuconfig

# diff and add to target config to get diffconfig of full custom kernel config,
# then diff that with the target config template (that make kernel_menuconfig 
# *should* have updated) and add anything that is missing to target .config.
# note: diff arguments of inner diff are flipped from previous diff command
echo "$(diff <(diff "${builddir_kconfig}" ${bin_dir}/extra/configs/.config.kernel | grep '<' | sed -E s/'^< '//) "${target_kconfig}" | grep '<' | sed -E s/'^< '//)" | tee -a .config.kernel.diff
cat .config.kernel.diff >> "${target_kconfig}"

# save full .config and fix up target config. 
# dont change anything in kernel_menuconfig - immediately save it (to .config) and exit
\mv -f "${builddir_kconfig}" .config.kernel
make kernel_menuconfig

# check that re-generating the kernel .config doesnt change anything
# the following command should indicate there are no changes
diff .config.kernel "${builddir_kconfig}"

# make kernel
make -j$(nproc) V=sc prepare

# add missing kernel module info to build
mkdir -p files/lib/modules/"${builddir_kernel##*/linux-}"

\cp -f "${builddir_kernel}"/{m,M,.m,.M}od* files/lib/modules/"${builddir_kernel##*/linux-}"
\rm -f $(find files/lib/modules/"${builddir_kernel##*/linux-}" -type f -empty)

# make the rest of the build
make -j$(nproc) -k V=sc

# optional: gather some useful things from the build and add them to bin/extra
mkdir -p bin/extra/keys
mkdir -p bin/extra/configs
cp key-build* bin/extra/keys
cp .config* "$target_kconfig" bin/extra/configs
cp -r files bin/extra

