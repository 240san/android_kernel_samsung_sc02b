#!/bin/bash

KERNEL_DIR=$PWD
CWM_DIR=$PWD/release
OUTPUT_DIR=$PWD/out

echo "=====> Build Device SC-02B"
INITRAMFS_SRC_DIR=../sc02b_ramdisk
INITRAMFS_TMP_DIR=/tmp/sc02b_ramdisk

copy_initramfs()
{
  echo copy to $INITRAMFS_TMP_DIR ... $(dirname $INITRAMFS_TMP_DIR)
  
  if [ ! -d $(dirname $INITRAMFS_TMP_DIR) ]; then
    mkdir -p $(dirname $INITRAMFS_TMP_DIR)
  fi

  if [ -d $INITRAMFS_TMP_DIR ]; then
    rm -rf $INITRAMFS_TMP_DIR  
  fi
  cp -a $INITRAMFS_SRC_DIR $INITRAMFS_TMP_DIR
  rm -rf $INITRAMFS_TMP_DIR/.git
  find $INITRAMFS_TMP_DIR -name .gitignore | xargs rm
}

BUILD_DEFCONFIG=kbc_sc02b_aosp_defconfig

BIN_DIR=out/bin
OBJ_DIR=out/obj
mkdir -p $BIN_DIR
mkdir -p $OBJ_DIR

# generate LOCALVERSION
. mod_version

# check and get compiler
. cross_compile

# set build env
export ARCH=arm
export CROSS_COMPILE=$BUILD_CROSS_COMPILE
export USE_SEC_FIPS_MODE=true
export LOCALVERSION="-$BUILD_LOCALVERSION"

echo "=====> BUILD START $BUILD_KERNELVERSION-$BUILD_LOCALVERSION"
read -p "select build? [(a)ll/(u)pdate/(z)Image default:update] " BUILD_SELECT

# copy initramfs
echo ""
echo "=====> copy initramfs"
copy_initramfs

# make start
if [ "$BUILD_SELECT" = 'all' -o "$BUILD_SELECT" = 'a' ]; then
  echo ""
  echo "=====> cleaning"
  rm -rf out
  mkdir -p $BIN_DIR
  mkdir -p $OBJ_DIR
  cp -f ./arch/arm/configs/$BUILD_DEFCONFIG $OBJ_DIR/.config
  make -C $PWD O=$OBJ_DIR oldconfig || exit -1
fi

if [ "$BUILD_SELECT" != 'zImage' -a "$BUILD_SELECT" != 'z' ]; then
  echo ""
  echo "=====> build start"
  if [ -e make.log ]; then
    mv make.log make_old.log
  fi
  nice -n 10 make O=$OBJ_DIR -j12 2>&1 | tee make.log
fi

# check compile error
COMPILE_ERROR=`grep 'error:' ./make.log`
if [ "$COMPILE_ERROR" ]; then
  echo ""
  echo "=====> ERROR"
  grep 'error:' ./make.log
  exit -1
fi

# *.ko replace
find -name '*.ko' -exec cp -av {} $INITRAMFS_TMP_DIR/files/modules/ \;

# build zImage
echo ""
echo "=====> make zImage"
nice -n 10 make O=$OBJ_DIR -j2 zImage CONFIG_INITRAMFS_SOURCE="$INITRAMFS_TMP_DIR" CONFIG_INITRAMFS_ROOT_UID=`id -u` CONFIG_INITRAMFS_ROOT_GID=`id -g` || exit 1

if [ ! -e $OUTPUT_DIR ]; then
  mkdir -p $OUTPUT_DIR
fi

echo ""
echo "=====> CREATE RELEASE IMAGE"
# clean release dir
if [ `find $BIN_DIR -type f | wc -l` -gt 0 ]; then
  rm $BIN_DIR/*
fi

# copy zImage
cp $OBJ_DIR/arch/arm/boot/zImage $OUTPUT_DIR/zImage
cp $OBJ_DIR/arch/arm/boot/zImage $CWM_DIR/boot.img
echo "  $OUTPUT_DIR/zImage"
echo "  $CWM_DIR/boot.img"

# create cwm image
cd $KERNEL_DIR/$BIN_DIR
if [ -d tmp ]; then
  rm -rf tmp
fi
cd $CWM_DIR
zip -r `echo $BUILD_LOCALVERSION`.zip *
mv  `echo $BUILD_LOCALVERSION`.zip $OUTPUT_DIR
echo "  $OUTPUT_DIR/$BUILD_LOCALVERSION-signed.zip"

#cleanup
rm $CWM_DIR/boot.img

cd $KERNEL_DIR
echo ""
echo "=====> BUILD COMPLETE $BUILD_KERNELVERSION-$BUILD_LOCALVERSION"
exit 0
