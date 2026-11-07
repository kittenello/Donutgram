## automated checks

`python3 Tests/power_saving/run.py` compiles extracted production settings, battery-threshold selection, composer measurement, sticker playback, Lottie playback and Core Animation normalization on macOS. It covers the battery boundary, always/never values, migration of older settings, preserving user preferences, clearing a tall rich composer, deferred completions, restoring sticker playback without replacing its timer with a static frame, cancelling delayed Lottie starts, and retaining final animation values and delegates.

the native checks attach animations to a paused backing layer of a hidden AppKit window under a nonzero transaction duration. they cover restoring infinite loops with their playback phase, loops created during power saving, removal, replacement, weak layer ownership and repeated mode changes. the dedicated power-saving workflow checks this fixture without downloading the full app history and submodules.

`--source-only` checks extraction on hosts without Swift or the macOS SDK; it does not execute those behaviors.

## device recording expectations

- the new row uses the energy-saving list's icon, title, description and switch layout in light and dark themes.
- moving the common slider to always activates the stronger policy; never restores configured processes. a battery threshold applies the same rule when crossed.
- stickers, emoji, wallpaper loops, snow, widgets and lottie effects hold still while the policy is active. newly opened stickers retain a visible static frame. tapping a sticker does not start playback.
- chat navigation, message insertion and panel changes settle without animated travel. controls remain usable, send and dismiss completions still finish, and manually opened media remain playable.
- leaving power saving restores the saved autoplay and effects preferences without restarting.
- a sticker returning from offscreen resumes its loop even when first-frame preloading is enabled. a delayed Lottie effect stopped during power saving stays stopped after the mode is disabled; replacing a delayed start with an immediate one reveals the effect at once.
- sending a tall rich message returns the empty composer to one line with the keyboard open and closed. a subsequent multiline message grows normally, and blank lines typed intentionally retain their height.

record the mode change, chat entry/exit, sticker picker and rich-message send at real speed, then inspect labelled frames with `tools/animation_sheet.py`. these visual outcomes require an iOS device or simulator and are not established by the extracted tests.
