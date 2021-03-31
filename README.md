# Relaunch

Relaunch is an open source Proof-Of-Concept for the exploit used by unlaunch to start arbitrary code on a DSi.

Unlaunch was created by Martin Korth and is the current go-to method for a tethered homebrew mod on the DSi. It allows execution of arbitrary code vie .NDS files or allows to continue normal DSi execution.



### WARNING:

The PoC will set the DSi into a mode that shws code execution but prevents it to boot properly.

**DO NOT RUN ON HARWDARE** you would need to hardmod to remove the PoC Code again. Please use the no$cash  emulator for experimenting with it.





### The Exploit

The DSi boots its system via a 2-staged boot loader. The first stage is kept in the mask rom on the CPU, while the second stage is loaded from a fixed location on the internal NAND (eMMC). The second stage then checks and loads the app launcher.

As every program or system resource on the DSi, the app launcher is protected by a title.tmd file containing metadata and the signature of the application.

The stage2 boot loader loads this title.tmd as a whole without checking the length to a buffer at a fixed address. By simply resizing the title.tmd file we can exceed he fixed buffer size.

There are several other structures and buffers at a memory location after this title.tmd buffer, which then can be overwritten. 

#### The gadget

By controlling two locations we can write the constant value 0x037F3CC0 to any location reachable by the arm9. The pseudocode for this gadget is

​	 `[[037F3878h]+78h] = 037F3CC0h`

The constant is conveniently a pointer to memory address that we can overwrite with our title.tmd. So if we can  write it to the stack as a return address, the execution would continue at 037F3CC0h.



### How-To

The Exploit PoC is provided with a Makefile and a assembler file.

To compose the exploit title.tmd, you need an original title.tmd file that can be appended with the PoC code. You need to extract the file nand:/title\00030017\484e414a\content\title.tmd and save it as title.org in the relaunch directory.

Execute make in the relaunch folder to build a title.tmd of 192kB size containing the PoC.