# MacOS base settings

## Keyboard Settings

### Swiss keyboard layout

- Load swiss keyboard layout from GitHub repository: <https://github.com/JtheGunner/swiss-windows-keyboard-layout-macos>
- Follow the instructions in the README.md to install the custom keyboard layout

### Windows keyboard layout

- Download Karabiner-Elements via <https://karabiner-elements.pqrs.org/> and follow the install instructions
- Follow the instructions in the GitHub repository <https://github.com/JtheGunner/karabiner-windows-keyboard-mapping-macos> for the configuration file to remap the keys to a Windows keyboard layout

### Change Font Settings

1. **Make the bold MacOS font thinner:**  
   `defaults -currentHost write -g AppleFontSmoothing -int 1`

2. **Change Microsoft Visual Studio Code Font:**  
   Press `Ctrl + Shift + P` and search for **Preferences: Open User Settings (JSON)**  
   Add or change the following settings:

    ```json
    {
        "editor.fontFamily": "'JetBrains Mono', 'Menlo', 'Monaco', 'Courier New', monospace",
        "editor.fontSize": 12,
        "editor.fontWeight": "100"
    }
    ```

### Custom Shortcuts

Add usefule custom shortcuts globally and for specific applications. Open "System Preferences > Keyboard > Keyboard shortcuts > App shortcuts"

1. **Change global Shorcuts:**  
   Add to following custom shortcuts:
    - **Application**: Alle Applikationen  
      **Menu title**: "Redo"  
      **Shortcut**: "Command (⌘) + Y"

2. **Change shortcuts for Google Chrome:**  
   Add to following custom shortcuts:
    - **Application**: Google Chrome  
      **Menu title**: "Diese Seite neuladen"  
      **Shortcut**: "F5"

    - **Application**: Google Chrome  
      **Menu title**: "Erneutes Laden dieser Seite erzwingen"  
      **Shortcut**: "Command (⌘) + F5"  
      **Important**: To enable this shortcut, you have to disable VoiceOver.  
       You can to this via "System Preferences > Keyboard > Keyboard shortcuts > Accessibility features > disable VoiceOver"

## Productivity

### Install HomeBrew

Homebrew installs the stuff you need that Apple (or your Linux system) didn't.  
`/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`

### Install AltTab

AltTab is used simulate the Windows keyboard short Alt + Tab. (Change between opened windows)  
Download via `https://alt-tab-macos.netlify.app/`  
OR  
Install by HomeBrew `brew install --cask alt-tab`

### Install uBar

Boost your productivity with the most advanced and versatile app and window manager for the Mac.  
Download via `https://ubarapp.com/`

## Genral Settings

### Allow apps from anywhere

1. Open Terminal and run the following command:  
   `sudo spctl --master-disable`
2. Open System Preferences → Security & Privacy → General.
3. Under "Allow apps downloaded from," select "Anywhere."
4. You may be prompted to enter your administrator password to confirm the change.
