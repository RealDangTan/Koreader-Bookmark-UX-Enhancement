# KOReader Bookmark Feature Patch

This repository contains a KOReader user patch:

`2-bookmark-features.lua`

The patch adds extra bookmark and highlight features without replacing full
KOReader source modules. It wraps the stock KOReader bookmark, highlight, and
annotation behavior so it is easier to keep using after KOReader updates.

## Features

- Add custom titles to bookmarks and highlights.
- Ask for an optional title when saving a highlight.
- Save the book title with annotations.
- Sort the bookmark list by book name.
- Show the chapter name in bookmark list rows.
- Filter bookmarks by chapter.
- Show richer bookmark detail information.
- Edit or add a bookmark title from the bookmark details screen.

## Compatibility

This patch is intended for KOReader `v2026.03` or newer.

## Installation

Copy `2-bookmark-features.lua` into the KOReader patches folder:

```text
<koreader>/patches/2-bookmark-features.lua
```

Then restart KOReader.

## Usage

After installation, open KOReader and use the normal bookmark and highlight
tools. Extra options are added to the bookmark settings and bookmark list UI.

> IF the bookmark title is not work, turn it off in option

## Notes

- Keep the filename prefix `2-` so KOReader loads the patch in the expected
  order.
- Back up your KOReader settings and annotations before testing new patches.
- If KOReader changes its internal bookmark modules in a future version, this
  patch may need updates.
