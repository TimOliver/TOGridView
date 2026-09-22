# TOGridView 
A small, customizable grid view for iOS. The example app targets **iOS 15 and later**.

![TOGridView on iPad in Portrait](https://raw.github.com/TimOliver/TOGridView/master/Screenshots/iPad_Portrait_t.jpg)

[Portrait Screenshot](https://raw.github.com/TimOliver/TOGridView/master/Screenshots/iPad_Portrait.jpg) 
| 
[Landscape Screenshot](https://raw.github.com/TimOliver/TOGridView/master/Screenshots/iPad_Landscape.jpg)

## Running the example

Open `TOGridViewExample.xcodeproj` and choose the shared **TOGridViewExample** scheme. Select your development team under Signing & Capabilities when running on a device; no personal signing profile is stored in the project.

The sample uses scene-based windows, a launch-screen configuration, safe-area layout, and columns derived from the available window width. It supports iPhone, iPad, rotation, resizable windows, Dynamic Type, and light/dark appearance. Cell separators are one-pixel views using `UIColor.separatorColor`; the editing controls use SF Symbols. No PNG assets or device-size categories are required.

- Tap **Add** to insert a uniquely numbered cell.
- Tap **Edit**, then select cells and tap **Delete**.
- In edit mode, touch and hold a cell to drag it to another position.

The scheme includes layout tests for phone and iPad widths and large text, plus UI tests for adding, selecting, deleting, reordering, and rotation. Run them with **Product → Test** or:

```sh
xcodebuild -project TOGridViewExample.xcodeproj -scheme TOGridViewExample \
  -destination 'platform=iOS Simulator,name=iPhone Air' test
```

Choose an available simulator name on your Mac. The screenshot above and the background below describe the original release.

## Objective-C and Swift API

The public headers declare nullability, typed collections, and a typed scroll-position enum. Swift receives optional offscreen cells and auxiliary views, `[TOGridViewCell]` for visible cells, and `[NSNumber]` for index arrays. Collection getters return empty arrays when there are no entries. The grid and its data-source/delegate callbacks belong on the main thread; the protocols also declare this requirement to Swift's concurrency checker.

Keep your data source and delegate alive elsewhere: both references are zeroing-weak. `dequeueReusableCell` creates a default `TOGridViewCell` when no subclass has been registered. The original `dequeReusableCell` spelling remains supported, including subclass overrides. Header, footer, and background views can be removed by assigning `nil`. Overrides of annotated editing, selection, and highlighting methods must call `super`.

For Swift, the custom initializer is `TOGridView(frame:cellClass:)` and scroll positions are `.top`, `.middle`, and `.bottom`. Existing Swift callers may need to adopt these imported names. Objective-C selectors remain available. The obsolete `nonRetinaRenderContexts` property is deprecated; UIKit controls snapshot resolution.

The unit-test target includes a Swift 6 client that checks these imports and implements the callbacks with main-actor state.

During scrolling, the grid skips cell reconciliation while the visible range and layout state are unchanged. Reloads, edits, and geometry changes invalidate this shortcut; the scroll container still updates normally. The reuse pool removes cells from its end, and reuse order is unspecified. Public geometry methods remain overridable.

## What exactly is this thing?

TOGridView is a class I'm developing for implementation into my commercial iOS app [iComics](http://icomics.co/). Given the relatively
large size and complexity of this class, coupled with its flexibility for potential reuse in future projects, I'm making it a completely separate project,
and open-sourcing it on GitHub.

## Given UICollectionView, what was the point of building this?

When looking at potential 'grid view' libraries for iComics, I did a thorough review of not just UICollectionView, but also a lot of the third party
grid view libraries that existed before it. As it turned out, I wasn't completely happy with any of the other options for various reasons.

Several of the major reasons for writing my own included:

  * UICollectionView is iOS 6 exclusive. Since I want iComics to support the first generation iPad (Which only goes up to iOS 5.1.1), UICollectionView is, depressingly, not an option. 
  * All of the other collection view classes are designed to be as flexible as possible, which also means they're very complex, with huge learning curves. I'm creating this class only with iComics' design requirements in mind, with the idea that it can be streamlined and optimised much more easily than those larger classes. 
  * Additionally, a lot of the third party library classes have really 'boilerplate' animations when it comes to adding/moving/deleting cells. Writing my own let me add my own flair to the built-in animations of the view.
  * I have not seen a SINGLE class (UICollectionView included) that elegantly animates interface orientation changes at 60FPS on all iOS devices. I want TOGridView to be the first. :D

## Features

  * Items are contained in cells and displayed vertically
  * Cells are arranged in horizontal rows, with the number and size customisable at different orientations.
  * Cells will crossfade upon orientation change. (Using a technique that was covered at WWDC 2012)
  * Cells can be inserted/deleted on the fly without forcing a complete reload.
  * In edit mode, cells can be deleted or re-ordered (ala the iOS Home Screen)
  * (STILL TODO) Each row can have a decoraton view placed in the background (eg a shelf graphic)

## License

TOGridView is licensed under the MIT License. Feel free to use it in any of your projects. Attribution would be appreciated, but is not required.
