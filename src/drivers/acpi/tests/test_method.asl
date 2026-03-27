/*
 * AML Method Call Test Suite
 * Tests: method calls with arguments, recursion, return values,
 * nested calls, method as expression, void methods
 *
 * Evaluate: acpi_eval \_SB._KFS.TMTH.MAIN
 */
DefinitionBlock ("test_method.aml", "SSDT", 2, "KFS", "TESTMETH", 1)
{
    External (\_SB._KFS, DeviceObj)
    External (\_SB._KFS._OPS.ADD_, MethodObj)
    External (\_SB._KFS._OPS.SUB_, MethodObj)
    External (\_SB._KFS._OPS.MUL_, MethodObj)
    External (\_SB._KFS._OPS.LEQ_, MethodObj)

    Scope (\_SB._KFS)
    {
        Device (TMTH)
        {
            Name (_HID, "KFST0005")
            Name (PCNT, 0)
            Name (TCNT, 0)

            Method (ADDM, 2)
            {
                Return (\_SB._KFS._OPS.ADD_ (Arg0, Arg1))
            }

            Method (FACT, 1)
            {
                If (\_SB._KFS._OPS.LEQ_ (Arg0, 1))
                {
                    Return (1)
                }
                Return (\_SB._KFS._OPS.MUL_ (Arg0, FACT(\_SB._KFS._OPS.SUB_ (Arg0, 1))))
            }

            Method (TCAL, 0)
            {
                /* basic call with args */
                Local0 = ADDM(3, 4)
                If (Local0 != 7) { Return (0x0101) }
                PCNT = PCNT + 1

                Local0 = ADDM(0, 0)
                If (Local0 != 0) { Return (0x0102) }
                PCNT = PCNT + 1

                Local0 = ADDM(100, 200)
                If (Local0 != 300) { Return (0x0103) }
                PCNT = PCNT + 1

                /* method result in expression */
                Local0 = \_SB._KFS._OPS.ADD_ (ADDM(10, 20), ADDM(30, 40))
                If (Local0 != 100) { Return (0x0104) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TREC, 0)
            {
                /* recursion: factorial */
                Local0 = FACT(1)
                If (Local0 != 1) { Return (0x0201) }
                PCNT = PCNT + 1

                Local0 = FACT(5)
                If (Local0 != 120) { Return (0x0202) }
                PCNT = PCNT + 1

                Local0 = FACT(10)
                If (Local0 != 3628800) { Return (0x0203) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* Fibonacci */
            Method (FIB_, 1)
            {
                If (\_SB._KFS._OPS.LEQ_ (Arg0, 1))
                {
                    Return (Arg0)
                }
                Return (\_SB._KFS._OPS.ADD_ (FIB_(\_SB._KFS._OPS.SUB_ (Arg0, 1)), FIB_(\_SB._KFS._OPS.SUB_ (Arg0, 2))))
            }

            Method (TFIB, 0)
            {
                Local0 = FIB_(0)
                If (Local0 != 0) { Return (0x0301) }
                PCNT = PCNT + 1

                Local0 = FIB_(1)
                If (Local0 != 1) { Return (0x0302) }
                PCNT = PCNT + 1

                Local0 = FIB_(6)
                If (Local0 != 8) { Return (0x0303) }
                PCNT = PCNT + 1

                Local0 = FIB_(10)
                If (Local0 != 55) { Return (0x0304) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* helper that returns its argument unchanged */
            Method (ECHO, 1)
            {
                Return (Arg0)
            }

            /* nested method calls: ECHO(ADDM(ECHO(2), ECHO(3))) */
            Method (TNST, 0)
            {
                Local0 = ECHO(ADDM(ECHO(2), ECHO(3)))
                If (Local0 != 5) { Return (0x0401) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 12

                Local0 = TCAL()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TREC()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TFIB()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TNST()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
