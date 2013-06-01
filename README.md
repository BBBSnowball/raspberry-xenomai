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

***The script does NOT work yet!***
(Xenomai executables won't start because they don't find their libraries; see below)

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
sharing this link. You need linux-modules.tar.bz2, kernel.img and xenomai-for-pi.tar.bz2. Take those files
and skip ahead to Install.

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

The build will generate two tar files and the kernel in build/$configname/. These are the same files that you
could have downloaded from my server. Now, go ahead to the Install section.

Install
-------

This does NOT work, yet. Please see the details in the next section.

1. copy the files to your Raspberry Pi<br/>
    `scp linux-modules.tar.bz2 kernel.img xenomai-for-pi.tar.bz2 raspberry:`
  
2. open a root shell on the Pi - all further steps have to be done on the Pi<br/>
    `ssh raspberry # or mosh raspberry, if you prefer`<br/>
    `sudo -s`

3. move kernel to /boot partition<br/>
  `cp /boot/kernel.img ~/kernel.img.backup`<br/>
  `cp ~/kernel.img /boot/kernel.img`

4. unpack linux modules<br/>
  `tar -C / -xjf ~/linux-modules.tar.bz2 --no-overwrite-dir --no-same-permissions --no-same-owner`

5. unpack Xenomai runtime and development files<br/>
  `tar -C / -xjf ~/xenomai-for-pi.tar.bz2 --no-overwrite-dir --no-same-permissions --no-same-owner`

6. reboot the Pi and hope that it works<br/>
  `reboot`

7. create device files: see next section

8. try Xenomai; this will most likely fail - see next section<br/>
  `/usr/xenomai/bin/latency`

Library path issues
-------------------

Xenomai lives in /usr/xenomai instead of /usr (as most software). Therefore, the dynamic linker won't find
the library and the programs won't start. I tried a few simple hacks, but none of them made it work (don't
try to copy the files to /usr - it won't work). On my test setup, I have solved it by compiling Xenomai on
the Pi. I'm still trying to find a better way.

This also creates the device nodes. We could deliver them in the Xenomai tar ball, but then we would have to
be the root user on the build system. You can run `make devices` in the Xenomai source tree to create the
device files.

I hope that both problems can be solved by using deb packages instead of tar balls, but I'm still working on that.
