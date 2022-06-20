# scrcpy-mobile

Ported scrcpy for mobile platforms, to remotely control Android devices on your iPhone or Android phone.

*Currently only supports controlling Android devices from iOS, Android controlling Android devices will be supported in futrue.*

## Features

* Supports scrcpy with ADB over WiFi ;
* With Hardware decoding, less power and CPU comsumed;
* Optimized gesture experiences for unstable network from mobile devices;

## Installation

Scrcpy Mobile is now available on the App Store. You can download from:

[![Get it from iTunes](https://lisk.com/sites/default/files/pictures/2020-01/download_on_the_app_store_badge.svg)](https://apps.apple.com/us/app/scrcpy-remote/id1629352527)

## Usage 

After the App is installed, the default mode is VNC. If you need to switch to ADB WiFi mode, please visit this URL Scheme: 
[scrcpy2://adb](scrcpy2://adb)

And then please please make sure that the Adnroid devices has enabled the **adb tcpip** mode:

```sh
adb tcpip 5555
```



Visit the URL scheme [scrcpy2://vnc](scrcpy2://vnc) to switch back to VNC mode.

*Note: The VNC mode can only connect the VNC port that be proxied with websockify.*

## Build

Build all dependencies:

```sh
make libs
```

Build `scrcpy-server`:

```sh
make -C porting scrcpy-server
```

Then, Open `scrcpy-ios/scrcpy-ios.xcodeproj` to Build and Run.

## License

```
MIT License

Copyright (c) 2022 Ethan

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

