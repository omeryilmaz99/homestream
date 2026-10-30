#!/bin/bash
# Plays the test films on the emulator in the TV app (forced with an
# intent extra) and saves screenshots and the log.
set -x
APK=$1
mkdir -p emu-out
shot() { adb exec-out screencap -p > emu-out/$1.png; }
key() { adb shell input keyevent $1; sleep ${2:-1}; }
adb install -r "$APK"
adb logcat -c
# the whole log, kept outside the device's ring buffer
adb logcat > emu-out/logcat.txt 2>&1 &
LOGCAT=$!
adb shell am start -n com.homestream.home_stream/.MainActivity --ez forceTv true
sleep 22
shot 1-playing
sleep 6
shot 2-subtitles
key 23 2   # the emulator spends the first key on leaving touch mode
key 23 2   # OK: pause, controls appear
shot 3-paused-controls
key 23 1   # resume
key 3 4    # home: app in the background
adb shell dumpsys SurfaceFlinger --list > emu-out/sf-background.txt
adb shell am start -n com.homestream.home_stream/.MainActivity
sleep 8
shot 4-back-from-home
adb shell dumpsys SurfaceFlinger --list > emu-out/sf-playing.txt
closes() { grep -c "LAYER close" emu-out/logcat.txt; }
alive() {
  if adb shell pidof com.homestream.home_stream > /dev/null; then echo "ALIVE $1"; else echo "GONE $1"; fi >> emu-out/alive.txt
}
# back held like on a remote: the release comes after the player is gone
# (a second press if the first only hid the controls)
hold_back() { adb shell input keyevent --duration 600 4; sleep 3; }
n=$(closes); hold_back; [ "$(closes)" = "$n" ] && hold_back
alive after-layer-player
shot 5-closed
sleep 30   # the 10-bit film starts and should switch renderers
shot 6-hidepth
sleep 8
shot 7-hidepth-later
# quick back presses: hide the controls if shown, then leave the player
n=$(closes); key 4 3; [ "$(closes)" = "$n" ] && key 4 3; [ "$(closes)" = "$n" ] && key 4 3
alive after-texture-player
shot 8-home
sleep 2
kill $LOGCAT
cat emu-out/alive.txt
grep -E "HSTEST|LAYER|MPV|VideoLayer|flutter.*(Exception|Error)|FATAL|AndroidRuntime" emu-out/logcat.txt > emu-out/test.txt
grep -iE "CCodec|MediaCodec|c2\.|OMX" emu-out/logcat.txt | head -300 > emu-out/codec.txt
echo done
