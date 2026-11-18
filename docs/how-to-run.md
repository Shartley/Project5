# How to run Project5 (Mac and Quest quick guide)

The [README](../README.md) is the full guide: browser build, controls, test walkthrough and the PowerShell launcher (Windows). This page is the short version for a **Mac**, plus how to see the **art walkthrough**.

## The game, on a computer

1. Install **Godot 4.7.2** (standard build, not .NET) from [godotengine.org](https://godotengine.org/download).
2. Get the repo: `git clone https://github.com/Shartley/Project5.git` (or `git pull`).
3. Open Godot, click **Import**, choose `project.godot`, then **Import & Edit**. The first import takes a minute or two.
4. Press **Run Project** (▶ at the top right), or **Cmd+B** on a Mac (**F5** on Windows).
5. Pick **Enter chamber**, **Begin daily workout** or **Training** in the welcome window. Controls are in the README; **F1** opens the test panel.

## The art walkthrough

A free-roam look at the Goblin Warren's Black Hall: goblins, the gate portal and the two daggers in your hands. Nothing attacks; it only shows the art.

1. In Godot's FileSystem panel, open `assets/preview/walkthrough.tscn`.
2. Press **Run Current Scene** (the clapperboard ▶ at the top right), or **Cmd+R** on a Mac (**F6** on Windows).
3. **WASD** to move, **mouse** to look, **Shift** to walk faster, **Esc** to free the mouse.

## In a Meta Quest, from a Mac

Quest Link does not exist on a Mac, so the game is installed onto the headset as an app.

**One-time setup on the Mac**

1. Java 17: `brew install --cask temurin@17`
2. [Android Studio](https://developer.android.com/studio). Open it once, then **Settings → Languages & Frameworks → Android SDK** and install the packages listed in [Godot's Android guide](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_android.html) (SDK Platform 35, Build-Tools 35.0.1, Platform-Tools, Command-line Tools, NDK, CMake).
3. In Godot: **Godot → Editor Settings → Export → Android**
   - **Java SDK Path:** `/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home`
   - **Android SDK Path:** `/Users/<you>/Library/Android/sdk`
4. In Godot: **Editor → Manage Export Templates → Download and Install** (about 1 GB).

**One-time setup on the headset**

5. In the **Meta Horizon** phone app: **Menu → Devices →** your Quest **→ Headset settings → Developer Mode → On** (Meta asks for a free developer account the first time).
6. Plug the Quest into the Mac with a USB-C **data** cable, put it on, and accept **Allow USB debugging** (tick **Always allow**).

**Run it**

7. **Project → Export…** and check the **Quest Debug** preset shows no red errors. Close the window.
8. Click **Remote Deploy** at the top right (the Android icon) and choose the Quest. Godot builds the app, installs it and starts it. Quest controls are in the README.

Later, open it from the headset with **Library → Unknown Sources → Project5**.

## If something goes wrong

- **"Could not install to device":** uninstall the old copy on the headset (**Library → Unknown Sources**) and deploy again.
- **The Quest is not in the Remote Deploy list:** replug the cable, accept USB debugging again, and make sure the cable carries data.
- **Export errors about the SDK or Java:** recheck the two paths in step 3; the Export window names what is missing.
