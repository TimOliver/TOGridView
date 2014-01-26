# TOGridView 
#### A light and easy collection view for iOS; compatible with iOS 5 and above.

![TOGridView on iPad in Portrait](https://raw.github.com/TimOliver/TOGridView/master/Screenshots/iPad_Portrait_t.jpg)

[Portrait Screenshot](https://raw.github.com/TimOliver/TOGridView/master/Screenshots/iPad_Portrait.jpg) 
| 
[Landscape Screenshot](https://raw.github.com/TimOliver/TOGridView/master/Screenshots/iPad_Landscape.jpg)

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
