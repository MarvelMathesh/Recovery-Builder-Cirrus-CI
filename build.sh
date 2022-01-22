#!/bin/bash

# cd To An Absolute Path
cd /tmp/rom

# export sync start time
export TZ=$TZ
SYNC_START=$(date +"%s")

# sync source
repo init -u $MANIFEST -b $MANIFEST_BRANCH --depth=1 --groups=all,-notdefault,-device,-darwin,-x86,-mips
repo sync -c --no-clone-bundle --no-tags --optimized-fetch --force-sync -j$(nproc --all)
git clone $DT_LINK --depth=1 --single-branch $DT_PATH
$COMMAND #use if needed ;)

# export sync end time and diff with sync start
SYNC_END=$(date +"%s")
SDIFF=$((SYNC_END - SYNC_START))

# setup TG message and build posts
telegram_message() {
	curl -s -X POST "https://api.telegram.org/bot${TG_TOKEN}/sendMessage" -d chat_id="${TG_CHAT_ID}" \
	-d "parse_mode=Markdown" \
	-d text="$1"
}

# Send 'Build Triggered' message in TG along with sync time
telegram_message "
	*🌟 Build Triggered 🌟*
	*Date:* \`$(date +"%d-%m-%Y %T")\`
	*✅ Sync finished after $((SDIFF / 60)) minute(s) and $((SDIFF % 60)) seconds*"  &> /dev/null

# export build start time
BUILD_START=$(date +"%s")

# Compile
export CCACHE_DIR=/tmp/ccache
export CCACHE_EXEC=$(which ccache)
export USE_CCACHE=1
ccache -M 20G
ccache -o compression=true
ccache -z

. build/envsetup.sh && lunch omni_$DEVICE-$BUILD_TYPE
$COMMAND2 #use if needed ;)
make $TARGET -j8 2>&1 | tee build.log

# export sync end time and diff with build start
BUILD_END=$(date +"%s")
DIFF=$((BUILD_END - BUILD_START))

ls -a $(pwd)/out/target/product/$DEVICE/ # show /out contents
ZIP=$(find $(pwd)/out/target/product/$DEVICE/ -maxdepth 1 -name "*$DEVICE*.zip" | perl -e 'print sort { length($b) <=> length($a) } <>' | head -n 1)
ZIPNAME=$(basename $ZIP)
ZIPSIZE=$(du -sh $ZIP |  awk '{print $1}')
echo "$ZIP"

telegram_build() {
	curl --progress-bar -F document=@"$1" "https://api.telegram.org/bot$BOTTOKEN/sendDocument" \
	-F chat_id="$CHATID" \
	-F "disable_web_page_preview=true" \
	-F "parse_mode=Markdown" \
	-F caption="$2"
}

telegram_post(){
 if [ -f $(pwd)/out/target/product/$DEVICE/$ZIPNAME ]; then
	rclone copy $ZIP MarvelMathesh:recovery -P
	MD5CHECK=$(md5sum $ZIP | cut -d' ' -f1)
	DWD=$DRIVE$ZIPNAME
	telegram_message "
	*✅ Build finished after $(($DIFF / 3600)) hour(s) and $(($DIFF % 3600 / 60)) minute(s) and $(($DIFF % 60)) seconds*
	*ROM:* \`$ZIPNAME\`
	*MD5 Checksum:* \`$MD5CHECK\`
	*Download Link:* [Tdrive]($DWD)
	*Size:* \`$ZIPSIZE\`
	*Date:*  \`$(date +"%d-%m-%Y %T")\`" &> /dev/null
 else
	BUILD_LOG=$(pwd)/build.log
	tail -n 10000 ${BUILD_LOG} >> $(pwd)/buildtrim.txt
	LOG1=$(pwd)/buildtrim.txt
	echo "CHECK BUILD LOG" >> $(pwd)/out/build_error
	LOG2=$(pwd)/out/build_error
	TRANSFER=$(curl --upload-file ${LOG1} https://transfer.sh/$(basename $LOG1))
	telegram_build $LOG2 "
	*❌ Build failed to compile after $(($DIFF / 3600)) hour(s) and $(($DIFF % 3600 / 60)) minute(s) and $(($DIFF % 60)) seconds*
	Build Log: $TRANSFER
	_Date:  $(date +"%d-%m-%Y %T")_" &> /dev/null
 fi
}

# space after build
df -hlT /

# post
telegram_post
