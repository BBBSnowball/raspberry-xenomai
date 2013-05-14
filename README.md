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

I will add some more information as soon as I have created the script...
