# Hi

This is a small Powershell script that disables IntelliCode in Visual Studio 2022.

# How does it work?

It sets a couple of config options in `CurrentSettings.vssettings` that are otherwise hidden from the user.

See [this StackOverflow answer](https://stackoverflow.com/a/77294217/14050275) for more information.

# How do I use it?

1. Clone the repository or download the script `disable_intellicode.ps1`
2. Run the script in the usual way

I recommend using Powershell Core, but this is tested and working on Windows Powershell.

The default settings will disable everything by default. If you want a bit more control, or you think one or more config options are causing issues, then you can specify switches and arguments at the command line. They are documented in the script.

# Help! It broke Visual Studio!
I disclaim all responsibility and liability for any damages or losses arising directly or
indirectly as a result of the use of this script.

With that out of the way, the script backs up your old settings before writing any changes. Open `$env:LOCALAPPDATA/Microsoft/VisualStudio/Settings` and look for the `.vssettings` file with `.backup` on the end, then rename it to `CurrentSettings.vssettings`.

# Why?

1. It slows Visual Studio down even more
2. Privacy
3. I don't want all of the code I write being used to train AI models that I don't own
4. I find it more annoying than useful