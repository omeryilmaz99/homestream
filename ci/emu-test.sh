#!/bin/bash
# Installs the APK on the running emulator, starts it and saves screenshots + logs.
set -x
APK=$1
mkdir -p emu-out
adb install -r "$APK"
adb logcat -c
adb shell am start -n com.homestream.home_stream/.MainActivity
for t in 5 15 30; do
  sleep $([ $t = 5 ] && echo 5 || echo 10)
  adb exec-out screencap -p > emu-out/shot_$t.png
done
adb logcat -d > emu-out/logcat.txt
grep -iE "flutter|AndroidRuntime|FATAL|homestream|libc|DEBUG|E/" emu-out/logcat.txt | grep -v "^$" | tail -300
adb shell dumpsys activity top | head -40
echo done
