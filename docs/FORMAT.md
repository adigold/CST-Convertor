# File format notes

These notes come from comparing `.cst` files with `.patch` bundles that Logic Pro saved itself.

## .cst (channel strip setting)

A binary file. It starts with the 4 bytes `OCuA`. The next bytes hold a version number (`06` in older files, `07` in files saved by newer Logic versions). The rest describes the instrument, plugins, plugin states and effects of one channel strip.

CST to Patch never reads or changes this data. It copies the file as it is.

## .patch (Logic patch)

A folder with the `.patch` extension. macOS shows it as a single file.

```
Name.patch/
├── #Root.cst
└── data.plist
```

`#Root.cst` is a normal `.cst` file. It holds the full sound of the patch.

`data.plist` is a binary property list:

| Key | Type | Value CST to Patch writes |
|---|---|---|
| VersionPatches | Integer | 40014 |
| channels | Array | one dictionary, described below |

Keys in the channel dictionary:

| Key | Type | Value CST to Patch writes |
|---|---|---|
| Channel_name | String | preset name |
| Channel_chaStrCategory | String | name of the parent folder |
| Filename | String | `#Root.cst` |
| Root | Boolean | true |
| UUID | String | new random UUID |
| Channel_instID | Integer | 88 |
| Channel_inputIndex_1 | Integer | -1 |
| Channel_inputIsBus | Boolean | false |
| Channel_isMuted | Boolean | false |
| Channel_isSolo | Boolean | false |
| Channel_outputIndex | Integer | 0 |
| Channel_outputIsBus | Boolean | false |
| Channel_outputIsStereo | Boolean | true |
| Channel_receiveChannel | Integer | -1 |
| Channel_seqColorIndex | Integer | 21 |
| Channel_userDidModifySmartControls | Boolean | true |
| Track_icon | Integer | 4505 |
| Channel_sends | Array | 8 sends at 0.0 volume (modes 1, 1, 2, 2, 2, 2, 2, 2) plus one empty dictionary |

Logic rebuilds anything missing from `#Root.cst` when it loads the patch. If you find a key that changes how a patch loads, open an issue.
