# Raspinfo

Raspinfo is an interactive application to show some info about your Raspberry Pi.

It is a text-mode application written in [Free Pascal](http://www.freepascal.org) and requires ncurses library.

## Runtime Dependency
Most of the information are retrieved by calling [vcgencmd](https://www.raspberrypi.org/documentation/raspbian/applications/vcgencmd.md) command. It is installed by default on [Raspbian](https://www.raspberrypi.org/documentation/raspbian/).

## How to build
You need a working installation of [Free Pascal](http://www.freepascal.org). 
[Lazarus IDE](http://www.lazarus.freepascal.org) is not required, anyway raspinfo.lpi project file is include for convenience of users which have it installed.

You also need development headers for libncurses, you can install it with:
> sudo apt install libncurses-dev

To start building open a terminal, change to the directory containing the source and run :         
> fpc raspinfo.lpr
