MODULE_NAME='mIiyamaTExxxxSeriesDisplay'    (
                                                dev vdvObject,
                                                dev dvPort
                                            )

(***********************************************************)
#include 'NAVFoundation.ModuleBase.axi'
#include 'NAVFoundation.Math.axi'
#include 'NAVFoundation.ArrayUtils.axi'

/*
 _   _                       _          ___     __
| \ | | ___  _ __ __ _  __ _| |_ ___   / \ \   / /
|  \| |/ _ \| '__/ _` |/ _` | __/ _ \ / _ \ \ / /
| |\  | (_) | | | (_| | (_| | ||  __// ___ \ V /
|_| \_|\___/|_|  \__, |\__,_|\__\___/_/   \_\_/
                 |___/

MIT License

Copyright (c) 2023 Norgate AV Services Limited

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
*/

(***********************************************************)
(*          DEVICE NUMBER DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_DEVICE

(***********************************************************)
(*               CONSTANT DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_CONSTANT

constant long TL_DRIVE    = 1

constant char COMMAND_HEADER[3] = ':01'

constant integer POWER_STATE_ON     = 1
constant integer POWER_STATE_OFF    = 2
constant integer POWER_STATE_FULL_OFF = 3

constant integer INPUT_HDMI_1    = 1
constant integer INPUT_HDMI_2    = 2
constant integer INPUT_HDMI_3    = 3
constant integer INPUT_HDMI_4    = 4
constant integer INPUT_VGA_1     = 5
constant integer INPUT_VGA_2     = 6
constant integer INPUT_VGA_3     = 7
constant integer INPUT_PC_1      = 8
constant integer INPUT_PC_2      = 9
constant integer INPUT_PC_3      = 10
constant integer INPUT_DISPLAYPORT_1      = 11

constant char INPUT_COMMANDS[][NAV_MAX_CHARS]   =   {
                                                        '001',
                                                        '002',
                                                        '021',
                                                        '022',
                                                        '000',
                                                        '031',
                                                        '032',
                                                        '101',
                                                        '102',
                                                        '103',
                                                        '007'
                                                    }

constant integer GET_POWER    = 1
constant integer GET_INPUT    = 2
constant integer GET_AUDIO_MUTE    = 3
constant integer GET_VOLUME    = 4

constant integer AUDIO_MUTE_ON    = 1
constant integer AUDIO_MUTE_OFF    = 2

constant integer MAX_VOLUME = 100
constant integer MIN_VOLUME = 0

(***********************************************************)
(*              DATA TYPE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_TYPE

(***********************************************************)
(*               VARIABLE DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_VARIABLE
volatile integer iLoop

volatile integer iPollSequence = GET_POWER

volatile integer iRequiredPower
volatile integer iRequiredInput
volatile integer iRequiredAudioMute
volatile sinteger siRequiredVolume

volatile integer iActualPower
volatile integer iActualInput
volatile integer iActualAudioMute
volatile sinteger siActualVolume

volatile long ltDrive[] = { 200 }

volatile integer iSemaphore
volatile char cRxBuffer[NAV_MAX_BUFFER]

volatile integer iCommandBusy

(***********************************************************)
(*               LATCHING DEFINITIONS GO BELOW             *)
(***********************************************************)
DEFINE_LATCHING

(***********************************************************)
(*       MUTUALLY EXCLUSIVE DEFINITIONS GO BELOW           *)
(***********************************************************)
DEFINE_MUTUALLY_EXCLUSIVE

(***********************************************************)
(*        SUBROUTINE/FUNCTION DEFINITIONS GO BELOW         *)
(***********************************************************)
(* EXAMPLE: DEFINE_FUNCTION <RETURN_TYPE> <NAME> (<PARAMETERS>) *)
(* EXAMPLE: DEFINE_CALL '<NAME>' (<PARAMETERS>) *)
define_function Send(char cPayload[]) {
    NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_TO, dvPort, cPayload))
    send_string dvPort, "cPayload"
}


define_function char[NAV_MAX_CHARS] Build(char cType[], char cCmd[], char cValue[]) {
    char cPayload[NAV_MAX_CHARS]
    cPayload = "COMMAND_HEADER, cType, cCmd, cValue, NAV_CR"
    return cPayload
}


define_function SendQuery(integer iParam) {
    switch (iParam) {
        case GET_POWER: Send(Build('G', '0', '000'))
        case GET_INPUT: Send(Build('G', ':', '000'))
        case GET_AUDIO_MUTE: Send(Build('G', '9', '000'))
        case GET_VOLUME: Send(Build('G', '8', '000'))
    }
}


define_function TimeOut() {
    cancel_wait 'CommsTimeOut'
    wait 300 'CommsTimeOut' { [vdvObject, DEVICE_COMMUNICATING] = false }
}


define_function SetPower(integer iParam) {
    switch (iParam) {
        case POWER_STATE_ON: {
            switch (iActualPower) {
                case POWER_STATE_FULL_OFF: {
                    Send(Build('S', '0', '003'))
                }
                case POWER_STATE_OFF: {
                    Send(Build('S', '0', '001'))
                }
                default: {
                    Send(Build('S', '0', '003'))
                }
            }
        }
        case POWER_STATE_OFF: { Send(Build('S', '0', '000')) }
    }
}


define_function SetInput(integer iParam) { Send(Build('S', ':', INPUT_COMMANDS[iParam])) }


define_function SetVolume(sinteger siParam) { Send(Build('S', '8', format('%03d', siParam))) }


define_function SetMute(integer iParam) {
    switch (iParam) {
        case AUDIO_MUTE_ON: { Send(Build('S', '9', '')) }
        case AUDIO_MUTE_OFF: { Send(Build('S', '9', '')) }
    }
}


define_function Process() {
    stack_var char cTemp[NAV_MAX_BUFFER]

    if (iSemaphore) {
        return
    }

    iSemaphore = true

    while (length_array(cRxBuffer) && NAVContains(cRxBuffer, "NAV_CR")) {
        cTemp = remove_string(cRxBuffer, "NAV_CR", 1)

        if (!length_array(cTemp)) {
            continue
        }

        select {
            active (NAVStartsWith(cTemp, COMMAND_HEADER)): {
                stack_var char cType

                NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_PARSING_STRING_FROM, dvPort, cTemp))

                cTemp = NAVStripCharsFromRight(cTemp, 1)    //Remove CR
                cTemp = NAVStripCharsFromLeft(cTemp, 3)    //Remove HEADER

                cType = get_buffer_char(cTemp)

                switch (cType) {
                    case 'r': {
                        stack_var char cCmd

                        cCmd = get_buffer_char(cTemp)

                        switch (cCmd) {
                            case '0': {
                                switch (cTemp) {
                                    case '000': {
                                        iActualPower = POWER_STATE_OFF
                                    }
                                    case '001': {
                                        iActualPower = POWER_STATE_ON
                                    }
                                    case '002': {
                                        iActualPower = POWER_STATE_FULL_OFF
                                    }
                                    case '003': {

                                    }
                                }

                                iPollSequence = GET_POWER
                            }
                            case ':': {
                                iActualInput = NAVFindInArraySTRING(INPUT_COMMANDS, cTemp)
                                iPollSequence = GET_POWER
                            }
                            case '8': {
                                if (siActualVolume != atoi(cTemp)) {
                                    siActualVolume = atoi(cTemp)
                                    send_level vdvObject, VOL_LVL, siActualVolume * 255 / (MAX_VOLUME - MIN_VOLUME)
                                }

                                iPollSequence = GET_POWER
                            }
                            case '9': {
                                switch (cTemp) {
                                    case '000': {
                                        iActualAudioMute = AUDIO_MUTE_OFF
                                    }
                                    case '001': {
                                        iActualAudioMute = AUDIO_MUTE_ON
                                    }
                                }

                                iPollSequence = GET_POWER
                            }
                        }
                    }
                }
            }
        }
    }

    iSemaphore = false
}


define_function Drive() {
    iLoop++

    switch (iLoop) {
        case 5:
        case 10:
        case 15:
        case 20: { SendQuery(iPollSequence); return }
        case 25: { iLoop = 0; return }
        default: {
            if (iCommandBusy) { return }

            if (iRequiredPower && (iRequiredPower == iActualPower)) { iRequiredPower = 0; return }
            if (iRequiredInput && (iRequiredInput == iActualInput)) { iRequiredInput = 0; return }
            if (iRequiredAudioMute && (iRequiredAudioMute == iActualAudioMute)) { iRequiredAudioMute = 0; return }

            if (iRequiredPower && (iRequiredPower != iActualPower)) {
                iCommandBusy = true
                SetPower(iRequiredPower)
                wait 80 iCommandBusy = false
                iPollSequence = GET_POWER
                return
            }

            if (iRequiredInput && (iActualPower == POWER_STATE_ON) && (iRequiredInput != iActualInput)) {
                iCommandBusy = true
                SetInput(iRequiredInput)
                wait 10 iCommandBusy = false
                iPollSequence = GET_INPUT
                return
            }

            if (iRequiredAudioMute && (iActualPower == POWER_STATE_ON) && (iRequiredAudioMute != iActualAudioMute)) {
                iCommandBusy = true
                SetMute(iRequiredAudioMute);
                wait 10 iCommandBusy = false
                iPollSequence = GET_AUDIO_MUTE;
                return
            }
        }
    }
}


(***********************************************************)
(*                STARTUP CODE GOES BELOW                  *)
(***********************************************************)
DEFINE_START {
    create_buffer dvPort, cRxBuffer
}

(***********************************************************)
(*                THE EVENTS GO BELOW                      *)
(***********************************************************)
DEFINE_EVENT

data_event[dvPort] {
    online: {
        NAVCommand(data.device, "'SET BAUD 9600,N,8,1 485 DISABLE'")
        NAVCommand(data.device, "'B9MOFF'")
        NAVCommand(data.device, "'CHARD-0'")
        NAVCommand(data.device, "'CHARDM-0'")
        NAVCommand(data.device, "'HSOFF'")

        NAVTimelineStart(TL_DRIVE, ltDrive, TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
    }
    string: {
        [vdvObject, DEVICE_COMMUNICATING] = true
        [vdvObject, DATA_INITIALIZED] = true

        TimeOut()

        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_STRING_FROM, dvPort, data.text))
        if (!iSemaphore) { Process() }
    }
}


data_event[vdvObject] {
    command: {
        stack_var char cCmdHeader[NAV_MAX_CHARS]
        stack_var char cCmdParam[3][NAV_MAX_CHARS]

        NAVErrorLog(NAV_LOG_LEVEL_DEBUG, NAVFormatStandardLogMessage(NAV_STANDARD_LOG_MESSAGE_TYPE_COMMAND_FROM, data.device, data.text))

        cCmdHeader = DuetParseCmdHeader(data.text)
        cCmdParam[1] = DuetParseCmdParam(data.text)
        cCmdParam[2] = DuetParseCmdParam(data.text)
        cCmdParam[3] = DuetParseCmdParam(data.text)

        switch (cCmdHeader) {
            case 'PASSTHRU': { Send("cCmdParam[1], NAV_CR") }
            case 'POWER': {
                switch (cCmdParam[1]) {
                    case 'ON': { iRequiredPower = POWER_STATE_ON; Drive() }
                    case 'OFF': { iRequiredPower = POWER_STATE_OFF; iRequiredInput = 0; Drive() }
                }
            }
            case 'VOLUME': {
                switch (cCmdParam[1]) {
                    case 'ABS': {
                        if (iActualPower = POWER_STATE_ON) {
                            SetVolume(atoi(cCmdParam[2]))
                        }
                    }
                    default: {
                        if (iActualPower = POWER_STATE_ON) {
                            SetVolume(NAVScaleValue(atoi(cCmdParam[1]), 255, (MAX_VOLUME - MIN_VOLUME), 0))
                        }
                    }
                }
            }
            case 'INPUT': {
                switch (cCmdParam[1]) {
                    case 'HDMI': {
                        switch (cCmdParam[2]) {
                            case '1': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_HDMI_1; Drive() }
                            case '2': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_HDMI_2; Drive() }
                            case '3': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_HDMI_3; Drive() }
                            case '4': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_HDMI_4; Drive() }
                        }
                    }
                    case 'VGA': {
                        switch (cCmdParam[2]) {
                            case '1': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_VGA_1; Drive() }
                            case '2': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_VGA_2; Drive() }
                            case '3': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_VGA_3; Drive() }
                        }
                    }
                    case 'PC': {
                        switch (cCmdParam[2]) {
                            case '1': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_PC_1; Drive() }
                            case '2': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_PC_2; Drive() }
                            case '3': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_PC_3; Drive() }
                        }
                    }
                    case 'DISPLAYPORT': {
                        switch (cCmdParam[2]) {
                            case '1': { iRequiredPower = POWER_STATE_ON; iRequiredInput = INPUT_DISPLAYPORT_1; Drive() }
                        }
                    }
                }
            }
        }
    }
}


channel_event[vdvObject, 0] {
    on: {
        switch (channel.channel) {
            case POWER: {
                if (iRequiredPower) {
                    switch (iRequiredPower) {
                        case POWER_STATE_ON: { iRequiredPower = POWER_STATE_OFF; iRequiredInput = 0; Drive() }
                        case POWER_STATE_OFF: { iRequiredPower = POWER_STATE_ON; Drive() }
                    }
                }
                else {
                    switch (iActualPower) {
                        case POWER_STATE_ON: { iRequiredPower = POWER_STATE_OFF; iRequiredInput = 0; Drive() }
                        case POWER_STATE_OFF: { iRequiredPower = POWER_STATE_ON; Drive() }
                        case POWER_STATE_FULL_OFF: { iRequiredPower = POWER_STATE_ON; Drive() }
                    }
                }
            }
            case PWR_ON: { iRequiredPower = POWER_STATE_ON; Drive() }
            case PWR_OFF: { iRequiredPower = POWER_STATE_OFF; iRequiredInput = 0; Drive() }
            case VOL_MUTE: {
                if (iActualPower == POWER_STATE_ON) {
                    if (iRequiredAudioMute) {
                        switch (iRequiredAudioMute) {
                            case AUDIO_MUTE_ON: { iRequiredAudioMute = AUDIO_MUTE_OFF; Drive() }
                            case AUDIO_MUTE_OFF: { iRequiredAudioMute = AUDIO_MUTE_ON; Drive() }
                        }
                    }
                    else {
                        switch (iActualAudioMute) {
                            case AUDIO_MUTE_ON: { iRequiredAudioMute = AUDIO_MUTE_OFF; Drive() }
                            case AUDIO_MUTE_OFF: { iRequiredAudioMute = AUDIO_MUTE_ON; Drive() }
                        }
                    }
                }
            }
        }
    }
}


timeline_event[TL_DRIVE] { Drive() }


timeline_event[TL_NAV_FEEDBACK] {
    [vdvObject, VOL_MUTE_FB] = (iActualAudioMute == AUDIO_MUTE_ON)
    [vdvObject, POWER_FB] = (iActualPower == POWER_STATE_ON)
}

(***********************************************************)
(*                     END OF PROGRAM                      *)
(*        DO NOT PUT ANY CODE BELOW THIS COMMENT           *)
(***********************************************************)

