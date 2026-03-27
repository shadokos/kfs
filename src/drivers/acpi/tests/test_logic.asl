/*
 * AML Logic Test Suite
 * Tests: And, Or, Xor, Not, Nand, Nor (bitwise),
 * LAnd, LOr, LNot (logical),
 * LEqual, LGreater, LLess, LGreaterEqual, LLessEqual (comparison)
 *
 * Evaluate: acpi_eval \_SB._KFS.TLOG.MAIN
 */
DefinitionBlock ("test_logic.aml", "SSDT", 2, "KFS", "TESTLOGC", 1)
{
    External (\_SB._KFS, DeviceObj)
    External (\_SB._KFS._OPS.AND_, MethodObj)
    External (\_SB._KFS._OPS.OR__, MethodObj)
    External (\_SB._KFS._OPS.XOR_, MethodObj)
    External (\_SB._KFS._OPS.NOT_, MethodObj)
    External (\_SB._KFS._OPS.EQL_, MethodObj)
    External (\_SB._KFS._OPS.NEQ_, MethodObj)
    External (\_SB._KFS._OPS.GRT_, MethodObj)
    External (\_SB._KFS._OPS.LSS_, MethodObj)
    External (\_SB._KFS._OPS.GEQ_, MethodObj)
    External (\_SB._KFS._OPS.LEQ_, MethodObj)
    External (\_SB._KFS._OPS.LAN_, MethodObj)
    External (\_SB._KFS._OPS.LOR_, MethodObj)
    External (\_SB._KFS._OPS.LNT_, MethodObj)

    Scope (\_SB._KFS)
    {
        Device (TLOG)
        {
            Name (_HID, "KFST0002")
            Name (PCNT, 0)
            Name (TCNT, 0)

            Method (TAND, 0)
            {
                Local0 = \_SB._KFS._OPS.AND_ (0xFF, 0x0F)
                If (Local0 != 0x0F) { Return (0x0101) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.AND_ (0xFF00, 0x00FF)
                If (Local0 != 0) { Return (0x0102) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.AND_ (0xAAAA, 0xFFFF)
                If (Local0 != 0xAAAA) { Return (0x0103) }
                PCNT = PCNT + 1

                /* x & 0 = 0 */
                Local0 = \_SB._KFS._OPS.AND_ (0xDEADBEEF, 0)
                If (Local0 != 0) { Return (0x0104) }
                PCNT = PCNT + 1

                /* x & Ones = x */
                Local0 = \_SB._KFS._OPS.AND_ (0x12345678, Ones)
                If (Local0 != 0x12345678) { Return (0x0105) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TOR_, 0)
            {
                Local0 = \_SB._KFS._OPS.OR__ (0xFF00, 0x00FF)
                If (Local0 != 0xFFFF) { Return (0x0201) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.OR__ (0, 0)
                If (Local0 != 0) { Return (0x0202) }
                PCNT = PCNT + 1

                /* x | 0 = x */
                Local0 = \_SB._KFS._OPS.OR__ (0xABCD, 0)
                If (Local0 != 0xABCD) { Return (0x0203) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TXOR, 0)
            {
                Local0 = \_SB._KFS._OPS.XOR_ (0xFF, 0x0F)
                If (Local0 != 0xF0) { Return (0x0301) }
                PCNT = PCNT + 1

                /* x ^ x = 0 */
                Local0 = \_SB._KFS._OPS.XOR_ (0xAA, 0xAA)
                If (Local0 != 0) { Return (0x0302) }
                PCNT = PCNT + 1

                /* x ^ 0 = x */
                Local0 = \_SB._KFS._OPS.XOR_ (0x1234, 0)
                If (Local0 != 0x1234) { Return (0x0303) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TNOT, 0)
            {
                Local0 = \_SB._KFS._OPS.NOT_ (0)
                If (Local0 != Ones) { Return (0x0401) }
                PCNT = PCNT + 1

                Local0 = \_SB._KFS._OPS.NOT_ (Ones)
                If (Local0 != 0) { Return (0x0402) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TCMP, 0)
            {
                /* LEqual / LNotEqual */
                If (\_SB._KFS._OPS.EQL_ (5, 5) != 1) { Return (0x0501) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.EQL_ (5, 6) != 0) { Return (0x0502) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.NEQ_ (0, 0) != 0) { Return (0x0503) }
                PCNT = PCNT + 1

                /* LGreater */
                If (\_SB._KFS._OPS.GRT_ (6, 5) != 1) { Return (0x0504) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.GRT_ (5, 5) != 0) { Return (0x0505) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.GRT_ (5, 6) != 0) { Return (0x0506) }
                PCNT = PCNT + 1

                /* LLess */
                If (\_SB._KFS._OPS.LSS_ (5, 6) != 1) { Return (0x0507) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LSS_ (5, 5) != 0) { Return (0x0508) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LSS_ (6, 5) != 0) { Return (0x0509) }
                PCNT = PCNT + 1

                /* LGreaterEqual */
                If (\_SB._KFS._OPS.GEQ_ (5, 5) != 1) { Return (0x050A) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.GEQ_ (6, 5) != 1) { Return (0x050B) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.GEQ_ (4, 5) != 0) { Return (0x050C) }
                PCNT = PCNT + 1

                /* LLessEqual */
                If (\_SB._KFS._OPS.LEQ_ (5, 5) != 1) { Return (0x050D) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LEQ_ (4, 5) != 1) { Return (0x050E) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LEQ_ (6, 5) != 0) { Return (0x050F) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TLOP, 0)
            {
                /* LAnd */
                If (\_SB._KFS._OPS.LAN_ (1, 1) != 1) { Return (0x0601) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LAN_ (1, 0) != 0) { Return (0x0602) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LAN_ (0, 1) != 0) { Return (0x0603) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LAN_ (0, 0) != 0) { Return (0x0604) }
                PCNT = PCNT + 1

                /* LOr */
                If (\_SB._KFS._OPS.LOR_ (1, 0) != 1) { Return (0x0605) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LOR_ (0, 1) != 1) { Return (0x0606) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LOR_ (1, 1) != 1) { Return (0x0607) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LOR_ (0, 0) != 0) { Return (0x0608) }
                PCNT = PCNT + 1

                /* LNot */
                If (\_SB._KFS._OPS.LNT_ (0) != 1) { Return (0x0609) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LNT_ (1) != 0) { Return (0x060A) }
                PCNT = PCNT + 1

                /* Non-boolean truthy: any non-zero is true */
                If (\_SB._KFS._OPS.LAN_ (0xFF, 1) != 1) { Return (0x060B) }
                PCNT = PCNT + 1
                If (\_SB._KFS._OPS.LOR_ (0x100, 0) != 1) { Return (0x060C) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 40

                Local0 = TAND()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TOR_()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TXOR()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TNOT()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCMP()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TLOP()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
