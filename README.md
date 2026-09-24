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

## Cell reuse and data prefetching

Override `prepareForReuse` in your cell subclass to cancel cell-owned work and clear temporary state. Call `super`. The grid calls this hook once immediately before returning a recycled cell from either dequeue spelling; newly allocated cells do not receive it. The base implementation does nothing, preserving existing subclasses. Configure every cell's content in `gridView:cellForIndex:`. For asynchronous images, check the cell's current item identity before applying a result, even after cancelling an older request.

Data prefetching is optional. Adopt `TOGridViewDataSourcePrefetching` and assign a retained provider to the grid's weak `prefetchDataSource` property:

```objc
gridView.prefetchDataSource = self;
gridView.prefetchRowCount = 2; // Default: two offscreen rows on each side.

- (void)gridView:(TOGridView *)gridView prefetchCellsAtIndices:(NSArray<NSNumber *> *)indices
{
    // Start asynchronous data/image preparation. Save the original item IDs and
    // task handles for these indices; do not create cells or block the main thread.
}

- (void)gridView:(TOGridView *)gridView cancelPrefetchingForCellsAtIndices:(NSArray<NSNumber *> *)indices
{
    // Optional: release each saved prefetch request. Cancel shared work only when
    // no visible cell or other consumer still needs it.
}
```

Callbacks run on the main thread after the current layout/update call stack. Requests contain unique indices in ascending order. Overlapping requests stay active as the viewport moves; obsolete offscreen requests are cancelled. When `cellForIndex:` needs a prefetched item, its request is handed over without cancellation. Loading must also work when no prefetch request was made, or when its result is not ready yet. Swift imports the callbacks as `gridView(_:prefetchCellsAt:)` and `gridView(_:cancelPrefetchingForCellsAt:)`.

Reloads and index-changing edits cancel outstanding requests before issuing fresh ones. Cancellation indices identify the original requests: after changing your model, use saved item IDs/task handles rather than looking up those indices again. This also applies to single-cell reloads, which conservatively invalidate all pending prefetch requests. Call `reloadGrid` after replacing the cell data source so the grid has current counts and metrics.

Data prefetching pauses during animated edits and cell dragging, and while the grid is detached from a window. Set `prefetchRowCount` to zero or clear `prefetchDataSource` to disable it. Cancellation is deferred and advisory; no callbacks are sent from deallocation, so the provider remains responsible for its own task/cache lifetime. These callbacks prepare application data; cell preparation is a separate option below.

## Preparing cells across frames

Enable early cell configuration independently of data prefetching:

```objc
gridView.cellPrefetchingEnabled = YES; // Default: NO; enabled in the example app.
```

The grid uses a display link to request and lay out at most one offscreen cell per display refresh, on the main thread. It keeps up to one row on each side of the visible range ready, prioritizing the scroll direction. A prepared cell is displayed without calling `gridView:cellForIndex:` again. State, permissions and geometry are rechecked at display time, but unchanged values avoid redundant cell setters. Cells that just left the viewport can also stay ready for a reversal. The display link stops when the cache is ready or preparation is suspended.

Opting in changes the timing of `gridView:cellForIndex:`: it can be called early for an item that never appears onscreen. Prepared cells are detached and are not included in `cellForIndex:` or `visibleCellViews`. Preparation uses the grid's traits as the current trait collection; use `gridView.traitCollection` for explicit environment queries. Put work requiring a window or visibility in `willDisplayCell:atIndex:`. Display callbacks still describe the visible lifecycle, and `prepareForReuse` still runs when a recycled cell is dequeued for new content. A data-prefetch request is handed over when cell configuration begins, which may now be before display.

Reloads, edits, geometry changes, and changes to the grid's traits invalidate prepared content. Preparation pauses while dragging cells or animating edits, and stops on detachment or disablement. Memory warnings release spare cells and suspend preparation until a later layout/visible-range change.

Already-visible cells are always supplied immediately, including the initial load and fast jumps that outrun preparation. The scheduler compares its measured cell preparation cost with the [next display deadline](https://developer.apple.com/documentation/quartzcore/cadisplaylink/targettimestamp) and leaves time for other frame work. After three consecutive budget misses, it stops the display link and keeps any ready cells. A visible-range change or preparation invalidation permits a fresh attempt with a reset cost estimate; queued updates alone cannot restart it. This is a best-effort check, not a hard time limit: it cannot interrupt an expensive synchronous data-source callback or split one cell's configuration across frames. Image I/O and decoding should still happen asynchronously in the app.

## Implementation layout and integration

The public API remains in `TOGridView.h` and `TOGridViewCell.h`. The grid's implementation is organized into private categories:

| File | Responsibility |
| --- | --- |
| `TOGridView.m` | Lifecycle, public entry points, accessors, and UIKit overrides |
| `TOGridView+Layout.m` | Metrics, visible-cell reconciliation, recycling, and rotation |
| `TOGridView+Updates.m` | Insertion, deletion, reloading, selection, and shared spring animation |
| `TOGridView+Dragging.m` | Touch handling, reordering, and drag autoscrolling |
| `TOGridView+Prefetching.m` | Data requests, cell preparation, caching, and scheduling |
| `TOGridView+Private.h` | Internal instance storage, properties, and category declarations |

When copying the library into an app, compile **all `.m` files in the `TOGridView` directory** and keep the private header alongside them. Client code only needs to import the public headers; do not publish `TOGridView+Private.h` as a framework's public header. If distributing the sources as a static library, add `-ObjC` to the consuming target's **Other Linker Flags** so the linker loads the category implementations. The example compiles the sources directly and does not need this flag.

The categories share the grid's existing state. Public selectors and overridable geometry/reuse methods remain in the primary implementation. UIKit overrides delegate to private helpers where needed; callers and subclasses continue to use the same API.

With a simulator booted, maintainers can verify static-library category loading using `python3 Scripts/check-static-library.py --simulator booted`. This builds the library as an archive and runs a consumer linked with `-ObjC` and dead stripping enabled.

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
