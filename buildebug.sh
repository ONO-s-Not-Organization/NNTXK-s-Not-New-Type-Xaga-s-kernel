#!/bin/bash
DIR=`readlink -f .`
MAIN=`readlink -f ${DIR}/..`
THREAD="-j$(nproc --all)"

export PATH="<the-patch-to-your-clang>/clang/bin:$PATH"
export CLANG_TRIPLE="aarch64-linux-gnu-"
export CROSS_COMPILE="${CLANG_TRIPLE}"

DEFCONFIG="gki_defconfig"

# Paths
KERNEL_DIR=`pwd`
ZIMAGE_DIR="$KERNEL_DIR/out/arch/arm64/boot"

# 配置 KernelSU
echo ">>> 拉取 SukiSU-Ultra 并设置版本..."
# 如果 KernelSU 目录存在则删除
[ -d "KernelSU" ] && rm -rf KernelSU
curl -LSs "https://raw.githubusercontent.com/ShirkNeko/SukiSU-Ultra/main/kernel/setup.sh" | bash -s susfs-main
cd KernelSU
KSU_VERSION="$(expr "$(git rev-list --count main)" "+" 10606)"
export KSU_VERSION
sed -i "s/DKSU_VERSION=12800/DKSU_VERSION=${KSU_VERSION}/" kernel/Makefile
cd ..

# 克隆所需补丁仓库
echo ">>> 克隆补丁仓库..."
# Clone/update susfs4ksu
if [ -d "susfs4ksu" ]; then
  cd susfs4ksu
  git reset --hard HEAD
  git clean -fdx
  git pull
  cd ..
else
  git clone https://github.com/shirkneko/susfs4ksu.git -b gki-android12-5.10 --depth=1
fi

# Clone/update SukiSU_patch
if [ -d "SukiSU_patch" ]; then
  cd SukiSU_patch
  git reset --hard HEAD
  git clean -fdx
  git pull
  cd ..
else
  git clone https://github.com/ShirkNeko/SukiSU_patch.git --depth=1
fi

# 应用 SUSFS 相关补丁
echo ">>> 应用 SUSFS 及 hook 补丁..."
# 复制补丁文件
cp ./susfs4ksu/kernel_patches/50_add_susfs_in_gki-android12-5.10.patch \
   ./SukiSU_patch/hooks/new_hooks.patch \
   .

# 复制文件系统相关文件
cp -r ./susfs4ksu/kernel_patches/fs/* ./fs/
cp -r ./susfs4ksu/kernel_patches/include/linux/* ./include/linux/

# 应用补丁
patch -p1 < 50_add_susfs_in_gki-android12-5.10.patch || true

# 应用隐藏补丁
cp ./SukiSU_patch/69_hide_stuff.patch ./
patch -p1 -F 3 < 69_hide_stuff.patch
patch -p1 < new_hooks.patch

echo ">>> 配置内核选项..."
DEFCONFIG_FILE=arch/arm64/configs/gki_defconfig

# 定义基础 SUSFS/KSU 配置
declare -A ksu_configs=(
    ["CONFIG_KSU"]="y"
    ["CONFIG_KSU_SUSFS_SUS_SU"]="n"
    ["CONFIG_KSU_MANUAL_HOOK"]="y"
    ["CONFIG_KSU_SUSFS"]="y"
    ["CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT"]="y"
    ["CONFIG_KSU_SUSFS_SUS_PATH"]="y"
    ["CONFIG_KSU_SUSFS_SUS_MOUNT"]="y"
    ["CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT"]="y"
    ["CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT"]="y"
    ["CONFIG_KSU_SUSFS_SUS_KSTAT"]="y"
    ["CONFIG_KSU_SUSFS_SUS_OVERLAYFS"]="n"
    ["CONFIG_KSU_SUSFS_TRY_UMOUNT"]="y"
    ["CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT"]="y"
    ["CONFIG_KSU_SUSFS_SPOOF_UNAME"]="y"
    ["CONFIG_KSU_SUSFS_ENABLE_LOG"]="y"
    ["CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS"]="y"
    ["CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG"]="y"
    ["CONFIG_KSU_SUSFS_OPEN_REDIRECT"]="y"
)

# 写入基础配置
for config in "${!ksu_configs[@]}"; do
    echo "${config}=${ksu_configs[$config]}" >> "$DEFCONFIG_FILE"
done

# 预处理配置
echo ">>> 禁用 defconfig 检查..."
sed -i 's/check_defconfig//' ./build.config.gki

# 检测机器内存是否大于 16GB，如果是，则在`/tmp`目录创建一个`out`目录，软链接到`out`目录
[ -d "./out" ] && rm -rf ./out
if [[ "$(grep MemTotal /proc/meminfo | awk '{print $2}')" -gt 16777216 ]]; then
    echo ">>> 检测到大于 16GB 内存，创建 /tmp/out 软链接..."
    [ -d "/tmp/out" ] && rm -rf /tmp/out
    mkdir -p /tmp/out
    ln -s /tmp/out ./out
else
    echo ">>> 内存小于等于 16GB，使用默认的 out 目录..."
    mkdir -p ./out
fi

# Vars
export ARCH=arm64
export SUBARCH=$ARCH
export KBUILD_BUILD_USER=ferstar
export KBUILD_BUILD_HOST=xaga-arm64

DATE_START=$(date +"%s")

echo  "DEFCONFIG SET TO $DEFCONFIG"
echo "-------------------"
echo "Making Kernel:"
echo "-------------------"
echo

make CC="ccache clang" CXX="ccache clang++" LLVM=1 LLVM_IAS=1 O=out $DEFCONFIG
make CC="ccache clang" CXX="ccache clang++" LLVM=1 LLVM_IAS=1 O=out menuconfig
make CC='ccache clang' CXX="ccache clang++" LLVM=1 LLVM_IAS=1 O=out $THREAD \
    LOCALVERSION=-Android12-9-v$(date +%Y%m%d-%H) \
    CONFIG_LOCALVERSION_AUTO=n \
    CONFIG_MEDIATEK_CPUFREQ_DEBUG=m CONFIG_MTK_IPI=m CONFIG_MTK_TINYSYS_MCUPM_SUPPORT=m \
    CONFIG_MTK_MBOX=m CONFIG_RPMSG_MTK=m CONFIG_LTO_CLANG=y CONFIG_LTO_NONE=n \
    CONFIG_LTO_CLANG_THIN=y CONFIG_LTO_CLANG_FULL=n 2>&1 | tee kernel.log

echo
echo "-------------------"
echo "Build Completed in:"
echo "-------------------"
echo

DATE_END=$(date +"%s")
DIFF=$(($DATE_END - $DATE_START))
echo "Time: $(($DIFF / 60)) minute(s) and $(($DIFF % 60)) seconds."
echo
ls -a $ZIMAGE_DIR

cd $KERNEL_DIR

mkdir -p tmp
cp -fp $ZIMAGE_DIR/Image.gz tmp
cp -rp ./anykernel/* tmp
cd tmp
7za a -mx9 tmp.zip *
cd ..
rm *.zip
cp -fp tmp/tmp.zip Android12-$(grep "# Linux/" out/.config | cut -d " " -f 3)-v$(date +%Y%m%d-%H).zip
rm -rf tmp
