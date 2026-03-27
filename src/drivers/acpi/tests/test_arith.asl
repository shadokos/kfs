/*
 * AML Arithmetic Test Suite
 * Tests: Add, Subtract, Multiply, Divide, Mod, ShiftLeft, ShiftRight,
 * Increment, Decrement, overflow behavior
 *
 * Evaluate: acpi_eval \_SB._KFS.TART.MAIN
 */
DefinitionBlock ("test_arith.aml", "SSDT", 2, "KFS", "TESTARTH", 1)
{
    External (\_SB._KFS, DeviceObj)
    External (\_SB._KFS._OPS.ADD_, MethodObj)
    External (\_SB._KFS._OPS.SUB_, MethodObj)
    External (\_SB._KFS._OPS.MUL_, MethodObj)
    External (\_SB._KFS._OPS.DIV_, MethodObj)
    External (\_SB._KFS._OPS.MOD_, MethodObj)
    External (\_SB._KFS._OPS.SHL_, MethodObj)
    External (\_SB._KFS._OPS.SHR_, MethodObj)
    External (\_SB._KFS._OPS.INC_, MethodObj)
    External (\_SB._KFS._OPS.DEC_, MethodObj)

    Scope (\_SB._KFS)
    {
        Device (TART)
        {
            Name (_HID, "KFST0001")
            Name (PCNT, 0)
            Name (TCNT, 0)

            Method (TADD, 0)
            {
                /* basic add */
                Local0 = \_SB._KFS._OPS.ADD_ (2, 3)
                If (Local0 != 5) { Return (0x0101) }
                PCNT = PCNT + 1

                /* identity */
                Local0 = \_SB._KFS._OPS.ADD_ (0, 0)
                If (Local0 != 0) { Return (0x0102) }
                PCNT = PCNT + 1

                /* 32-bit overflow wraps to zero */
                Local0 = \_SB._KFS._OPS.ADD_ (0xFFFFFFFF, 1)
                If (Local0 != 0) { Return (0x0103) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TSUB, 0)
            {
                Local0 = \_SB._KFS._OPS.SUB_ (10, 3)
                If (Local0 != 7) { Return (0x0201) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.SUB_ (5, 5)
                If (Local0 != 0) { Return (0x0202) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.SUB_ (100, 1)
                If (Local0 != 99) { Return (0x0203) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TMUL, 0)
            {
                Local0 = \_SB._KFS._OPS.MUL_ (3, 7)
                If (Local0 != 21) { Return (0x0301) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.MUL_ (0, 1000)
                If (Local0 != 0) { Return (0x0302) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.MUL_ (256, 256)
                If (Local0 != 0x10000) { Return (0x0303) }
                PCNT = PCNT + 1

                /* 1 * x = x */
                Local0 = \_SB._KFS._OPS.MUL_ (1, 0xDEAD)
                If (Local0 != 0xDEAD) { Return (0x0304) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TDIV, 0)
            {
                Local0 = \_SB._KFS._OPS.DIV_ (10, 3)
                If (Local0 != 3) { Return (0x0401) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.DIV_ (100, 10)
                If (Local0 != 10) { Return (0x0402) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.DIV_ (7, 1)
                If (Local0 != 7) { Return (0x0403) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.DIV_ (0, 5)
                If (Local0 != 0) { Return (0x0404) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TMOD, 0)
            {
                Local0 = \_SB._KFS._OPS.MOD_ (10, 3)
                If (Local0 != 1) { Return (0x0501) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.MOD_ (100, 10)
                If (Local0 != 0) { Return (0x0502) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.MOD_ (7, 4)
                If (Local0 != 3) { Return (0x0503) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.MOD_ (5, 5)
                If (Local0 != 0) { Return (0x0504) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TSHL, 0)
            {
                Local0 = \_SB._KFS._OPS.SHL_ (1, 4)
                If (Local0 != 16) { Return (0x0601) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.SHL_ (0xFF, 8)
                If (Local0 != 0xFF00) { Return (0x0602) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.SHL_ (1, 0)
                If (Local0 != 1) { Return (0x0603) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.SHL_ (1, 31)
                If (Local0 != 0x80000000) { Return (0x0604) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TSHR, 0)
            {
                Local0 = \_SB._KFS._OPS.SHR_ (0xFF00, 8)
                If (Local0 != 0xFF) { Return (0x0701) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.SHR_ (16, 4)
                If (Local0 != 1) { Return (0x0702) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.SHR_ (1, 0)
                If (Local0 != 1) { Return (0x0703) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.SHR_ (0x80000000, 31)
                If (Local0 != 1) { Return (0x0704) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TINC, 0)
            {
                /* Increment / Decrement */
                Local0 = 5
                Local0 = \_SB._KFS._OPS.INC_ (Local0)
                If (Local0 != 6) { Return (0x0801) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.DEC_ (Local0)
                If (Local0 != 5) { Return (0x0802) }
                PCNT = PCNT + 1

                Local0 = 0
                Local0 = \_SB._KFS._OPS.DEC_ (Local0)
                /* Decrement wraps: 0-1 = 0xFFFFFFFFFFFFFFFF */
                If (Local0 != Ones) { Return (0x0803) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 29 /* Total assertions in this file */

                Local0 = TADD()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TSUB()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TMUL()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TDIV()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TMOD()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TSHL()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TSHR()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TINC()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
