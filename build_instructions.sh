buildroot_dir="/mnt/ramdisk"
bin_dir="$buildroot_dir"/openwrt-custom-builds/WRX36/bin

mkdir -p "${buildroot_dir}"
cat /proc/mounts | grep -F "${buildroot_dir}" | grep -q 'tmpfs' || sudo mount -t tmpfs tmpfs "${buildroot_dir}" -o defaults -o size=96G
mkdir -p "${buildroot_dir}/build"
cd "${buildroot_dir}/build"
git clone https://github.com/jkool702/openwrt.git
cd "${buildroot_dir}/build/openwrt"
git fetch

#echo "$(cat feeds.conf.default | sed -E s/'^#src-git targets '/'src-git targets '/)" > feeds.conf
git clone --depth 1 --branch master --single-branch --no-tags --recurse-submodules https://github.com/fantastic-packages/packages package/fantastic_packages

./scripts/feeds update -a
./scripts/feeds install -a
./scripts/feeds install -a;

# move in files and maion config
cp -r "${bin_dir}"/extra/files ./
cp "${bin_dir}"/extra/configs/{.config,.config.kernel} ./


# speed up downloads. Not needed if using my github repo
# echo "$(cat scripts/download.pl | sed -zE s/'(elsif \(\$mirror \=\~ \/\^\\\@GNU\\\/\(\.\+\)\$\/\) \{[^p]+push \@mirrors\, )[^\}]+\}'/'\1"https:\/\/gnu.mirror.constant.com\/$1"\n\t}'/)" > scripts/download.pl

# configure openwrt settings
make menuconfig

# ALT:
# make defconfig

# download/check sources, then build unmodified kernel 
make -j$(nproc) V=sc download check prepare_kernel_conf kernel_menuconfig

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

# remove incomplete .config out of kernel build dir
\rm -f  "${builddir_kconfig}" 

# regenerate .config (which gives the full complete kernel .config) and actually custom configure the kernel this time -- save as .config when done
make kernel_menuconfig

# diff and add to target config to get diffconfig of full custom kernel config,
# then diff that with the target config template (that make kernel_menuconfig 
# *should* have updated) and add anything that is missing to target .config.
# note: diff arguments of inner diff are flipped from previous diff command
echo "$(diff <(diff "${builddir_kconfig}" .config.kernel.orig | grep '<' | sed -E s/'^< '//) "${target_kconfig}" | grep '<' | sed -E s/'^< '//)" | tee -a .config.kernel.diff
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

# add kernel module info to build
mkdir -p files/lib/modules/"${builddir_kernel##*/}"

\cp -f "${builddir_kernel}"/{m,M,.m,.M}od* files/lib/modules/"${builddir_kernel##*/}"
\rm -f "$(find files/lib/modules/"${builddir_kernel##*/}" -type f -maxdepth 0 -empty)"
# make the rest of the build
make -j$(nproc) -k V=sc


mkdir -p bin/keys
mkdir -p bin/configs
cp key-build* bin/keys
cp .config* "$target_kconfig" bin/configs

rsync -a bin /home/anthony/openwrt/WRX36/bin-NEWEST
