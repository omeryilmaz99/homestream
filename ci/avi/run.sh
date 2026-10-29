#!/bin/bash
# Runs the AVI probe APK on the emulator and saves logcat + server log.
set -x
APK=$1
mkdir -p emu-out
adb install -r "$APK"
adb logcat -c
adb shell am start -n com.homestream.home_stream/.MainActivity
for t in 20 60 100; do
  sleep 20
  adb exec-out screencap -p > emu-out/shot_$t.png
done
# 4 cases x ~35 s
for i in $(seq 1 30); do
  sleep 5
  adb logcat -d | grep -q "PROBE DONE" && break
done
adb logcat -d > emu-out/logcat.txt
grep "PROBE" emu-out/logcat.txt | tee emu-out/probe.txt
cp ci/avi/server.log emu-out/ 2>/dev/null
echo done
