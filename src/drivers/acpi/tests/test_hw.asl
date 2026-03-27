/*
 * AML Field Read/Write Test Suite
 * Tests: OpRegion (SystemMemory), Field byte/word/dword access,
 * write-then-read-back, combined multi-width access.
 *
 * Uses physical address 0x600 (free conventional memory, safe in QEMU
 * and on bare metal after boot).
 *
 * Evaluate: acpi_eval \_SB._KFS.THW0.MAIN
 */
DefinitionBlock ("test_hw.aml", "SSDT", 2, "KFS", "TESTHW__", 1)
{
    External (\_SB._KFS, DeviceObj)

    Scope (\_SB._KFS)
    {
        Device (THW0)
        {
            Name (_HID, "KFST0008")
            Name (PCNT, 0)
            Name (TCNT, 0)

            /* 16-byte scratch region in low conventional memory */
            OperationRegion (TMEM, SystemMemory, 0x600, 16)
            Field (TMEM, ByteAcc, NoLock, Preserve)
            {
                TB01, 8,    /* offset 0: byte   */
                TB02, 8,    /* offset 1: byte   */
                TW01, 16,   /* offset 2: word   */
                TD01, 32,   /* offset 4: dword  */
                TD02, 32,   /* offset 8: dword  */
                TD03, 32,   /* offset 12: dword */
            }

            Method (TBYT, 0, Serialized)
            {
                /* Write and read back a byte */
                TB01 = 0xAB
                Local0 = TB01
                If (Local0 != 0xAB) { Return (0x0101) }
                PCNT = PCNT + 1

                /* Second byte field */
                TB02 = 0xCD
                Local0 = TB02
                If (Local0 != 0xCD) { Return (0x0102) }
                PCNT = PCNT + 1

                /* Overwrite */
                TB01 = 0x42
                Local0 = TB01
                If (Local0 != 0x42) { Return (0x0103) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TWRD, 0, Serialized)
            {
                /* Write and read back a word */
                TW01 = 0xBEEF
                Local0 = TW01
                If (Local0 != 0xBEEF) { Return (0x0201) }
                PCNT = PCNT + 1

                /* Overwrite */
                TW01 = 0x1234
                Local0 = TW01
                If (Local0 != 0x1234) { Return (0x0202) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TDWD, 0, Serialized)
            {
                /* Write and read back a dword */
                TD01 = 0xDEADBEEF
                Local0 = TD01
                If (Local0 != 0xDEADBEEF) { Return (0x0301) }
                PCNT = PCNT + 1

                /* Write all fields then verify none were clobbered */
                TB01 = 0x11
                TB02 = 0x22
                TW01 = 0x4433
                TD01 = 0x88776655
                TD02 = 0xAABBCCDD

                Local0 = TB01
                If (Local0 != 0x11) { Return (0x0302) }
                PCNT = PCNT + 1

                Local0 = TB02
                If (Local0 != 0x22) { Return (0x0303) }
                PCNT = PCNT + 1

                Local0 = TW01
                If (Local0 != 0x4433) { Return (0x0304) }
                PCNT = PCNT + 1

                Local0 = TD01
                If (Local0 != 0x88776655) { Return (0x0305) }
                PCNT = PCNT + 1

                Local0 = TD02
                If (Local0 != 0xAABBCCDD) { Return (0x0306) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0)
            {
                PCNT = 0
                TCNT = 11

                Local0 = TBYT()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TWRD()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TDWD()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
