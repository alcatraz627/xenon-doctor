# The pad registry

The app is for one pad model, and it knows each pad of that model by the pencil mark on its back and its Bluetooth address. That list is a JSON file, so a third pad, or a replacement, is one line and no rebuild.

## Where the file lives

Read in this order, first match wins:

1. `~/Library/Application Support/XenonDoctor/pads.json`, the household's copy. `--add-pad` and `--remove-pad` write this file.
2. `pads.json` inside the app bundle, the copy shipped with the release.
3. The list built into the binary, which matches the shipped file.

An app update replaces the bundle and leaves the Application Support copy alone, so added pads survive.

## The shape

```json
{
  "model" : "Cosmic Byte Stratos Xenon (reports as a DualShock 4)",
  "vendorID" : "0x054C",
  "productID" : "0x09CC",
  "pads" : [
    { "mark" : "SQUARE", "mac" : "D0:27:96:F5:49:AD", "note" : "Aakarsh's pad" },
    { "mark" : "CIRCLE", "mac" : "D0:27:96:D0:11:6D", "note" : "the other pad" }
  ]
}
```

`vendorID` and `productID` name the model: they drive the Steam ignore list (`0x054c/0x09cc`) and the battery listener's device match. `mark` is what the rows call the pad. `mac` is compared on bare hex, so either `D0:27:96:F5:49:AD` or `d0-27-96-f5-49-ad` matches. `note` is shown in the guide.

## From a terminal

```
XenonDoctor --pads                                  print the registry and where it was read from
XenonDoctor --add-pad TRIANGLE D0:27:96:AA:BB:CC "the new one"
XenonDoctor --remove-pad TRIANGLE
```

The address of a new pad: pair it once in System Settings, Bluetooth, click its info button, and read the address there. Or run `system_profiler SPBluetoothDataType` and find the gamepad with vendor 0x054C.

## What reads it

`Sources/XenonDoctor/Model/Pads.swift` is the only reader of the file. Everything else asks `Pads.known`, `Pads.pad(forMAC:)`, `Pads.sdlIgnoreValue`, `Pads.vendorID` and `Pads.productID`: the pad probe, the reconnect repair, the pin, the battery listener, the guide's "which pad is which" list, and the self-test.
