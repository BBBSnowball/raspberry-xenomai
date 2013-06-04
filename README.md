raspberry-xenomai
=================

The script in this repository compiles a real-time kernel for Raspberry Pi. Fortunately, the hard work
has been done by other guys. I'm only providing the script. Please keep in mind that this is work in
progress, so don't expect it to be stable!

I suggest that you learn how to compile it yourself. I found a guide that makes it really easy. My script
is based on that guide. And here it is: http://diy.powet.eu/2012/07/25/raspberry-pi-xenomai/

This site has some timing measurements and you can use the programs to test the kernel on your Pi. We tried to
reproduce the measurements, but we couldn't get the Cleverscope software to generate histographs. However, we
got similar results: With the xenomai kernel, jitter is quite reasonable until you get below 100us. If you go
down to 30us, jitter is huge. And below that you get the wrong frequency or it doesn't work at all.

***The script has some rough edges! I don't consider it finished, yet!*** (see below)

***I use Raspbian hardfloat and I haven't (and probably won't) test anything else!***

Configuration
-------------

Not everyone wants the same kernel, so we support several configurations. You can add your own configuration to
the config folder. You have to choose one of them. The README files may be helpful. Remember the name of the
folder and skip ahead to Download or Build.

You can also create your own config. Copy an existing one and modify it as you wish. Each configuration has
these parts:

* README: information about this configuration
* config: sets variables for the build script; at the moment this is: path to adeos patch and kernel config
* versions: versions to set the submodules to; you can use a branch or tag name
* patches: patches to apply
* additional files: patches, kernel config, ...

Download
--------

I have a CI server that builds the kernel. You can download the compiled files from there. It might be slow
because the server is behind a DSL connection. Please consider uploading the files to your server instead of
sharing this link. You can simply use the install.sh script which will download the files for you (see Install).

[Download build artifacts](http://jenkins.bbbsnowball.de:3000/jenkins/artifact/RaspberryPi-Xenomai/build/)

![build status](http://jenkins.bbbsnowball.de:3000/jenkins/badge/RaspberryPi-Xenomai)

If the build is broken, you can still download the last good version.

Build
-----

Run build-all.sh to build all configurations or run build.sh with a configuration name. It will download
the kernel, xenomai and the toolchain (compiler) and build the kernel and xenomai. It's that simple.
Well, almost ;-)

The build cannot run a second time (or for the second config) because the patches cannot be applied to an
unclean tree. The build script has an option to complete clean the trees, but it isn't enabled by default.
If you pass the --clean-sources parameter to one of the scripts, it will kill ALL changes and unversioned
files in the submodules (or rather all folders mentioned in the versions file of the config). YOU WILL LOOSE
ALL MANUAL CHANGES TO THOSE FILES! Therefore, you have to explicitely state that you really want that.

You may also have to install some dependencies. I'm only listing the ones that I had to install on my Debian
wheezy system. Please tell me, if some are missing. You can find more details (and probably a more up-to-date
list) at the start of the build.sh script. The script won't tell you about the dependencies - it will fail
in some way. Hopefully, you can guess the missing thing from the message.

The build will generate the kernel, a modules tar file and Xenomai deb packages in build/$configname/. These
are the same files that you could have downloaded from my server. Now, go ahead to the Install section.

Install
-------

You have to choose a configuration. Please make sure that it matches your system (arm (or no tag) for softfloat,
armhf for hardfloat). In any case, the Debian packages are tagged as `arm`, so you need to force installation
on `armhf`. However, the packages ARE different, so choose the right one.

1. get install.sh<br/>
    `wget https://raw.github.com/BBBSnowball/raspberry-xenomai/master/install.sh`
  
2. edit it and change CONFIG, MIRROR and XENOMAI_VERSION

3. run install.sh - it will download and install the files<br/>
  `chmod +x install.sh` <br/>
  `sudo ./install.sh`

4. reboot the Pi and hope that it works<br/>
  `reboot`

5. try Xenomai<br/>
  `/usr/lib/xenomai/latency`

Debian packages for the kernel
------------------------------

In theory, I could simply use kernel-package, but that doesn't work. Chris Boot has used it to build his
modified kernel, but he had to patch kernel-package to make it work on Debian wheezy.

I'm not building debs for the kernel because...
* I couldn't easily find Chris' modified kernel-package (not in his repo anymore).
* I don't want to make modifications to the build system (except installing some software).
* The other method sort of works (although I would prefer deb packages, of course).

Debian packages for Xenomai
---------------------------

The debs for Raspbian hardfloat are tagged `arm` instead of `armhf`. Therefore, you have to install them with
`dpkg --force-architecture -i ...`. If I tell `dpkg-buildpackage` to build it for `armhf`, it will use the
build system compiler (amd64 in my case). However, I can tell it to build `arm` and let it use the hardfloat
compiler. This works, but I hope that I can improve that.

The debs for softfloat (`arm`) should be fine, but I haven't tested.
