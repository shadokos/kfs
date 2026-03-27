/*
 * AML Store Test Suite
 * Tests: Store to Local, Store to named object, method arguments,
 * multiple args, argument passing, chained stores
 *
 * Evaluate: acpi_eval \_SB._KFS.TSTO.MAIN
 */
DefinitionBlock ("test_store.aml", "SSDT", 2, "KFS", "TESTSTR_", 1)
{
    External (\_SB._KFS, DeviceObj)
    External (\_SB._KFS._OPS.ADD_, MethodObj)

    Scope (\_SB._KFS)
    {
        Device (TSTO)
        {
            Name (_HID, "KFST0004")
            Name (PCNT, 0)
            Name (TCNT, 0)
            Name (GBL1, 0)
            Name (GBL2, 0)

            Method (TLOC, 0)
            {
                /* Store to local */
                Local0 = 42
                If (Local0 != 42) { Return (0x0101) }
                PCNT = PCNT + 1

                /* Copy between locals */
                Local1 = Local0
                If (Local1 != 42) { Return (0x0102) }
                PCNT = PCNT + 1

                /* Store expression result */
                Local2 = \_SB._KFS._OPS.ADD_ (Local0, Local1)
                If (Local2 != 84) { Return (0x0103) }
                PCNT = PCNT + 1

                /* All 8 locals */
                Local0 = 0
                Local1 = 1
                Local2 = 2
                Local3 = 3
                Local4 = 4
                Local5 = 5
                Local6 = 6
                Local7 = 7
                
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Local1)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Local2)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Local3)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Local4)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Local5)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Local6)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Local7)
                
                If (Local0 != 28) { Return (0x0104) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TNAM, 0)
            {
                /* Store to named object */
                GBL1 = 99
                If (GBL1 != 99) { Return (0x0201) }
                PCNT = PCNT + 1

                /* Modify named object */
                GBL1 = \_SB._KFS._OPS.ADD_ (GBL1, 1)
                If (GBL1 != 100) { Return (0x0202) }
                PCNT = PCNT + 1

                /* Two globals */
                GBL1 = 10
                GBL2 = 20
                Local0 = \_SB._KFS._OPS.ADD_ (GBL1, GBL2)
                If (Local0 != 30) { Return (0x0203) }
                PCNT = PCNT + 1

                /* Reset for next test run */
                GBL1 = 0
                GBL2 = 0

                Return (0)
            }

            Method (TARG, 1)
            {
                If (Arg0 != 42) { Return (0x0301) }
                PCNT = PCNT + 1
                Return (0)
            }

            Method (TAR2, 3)
            {
                Local0 = \_SB._KFS._OPS.ADD_ (Arg0, Arg1)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Arg2)
                If (Local0 != 60) { Return (0x0401) }
                PCNT = PCNT + 1
                Return (0)
            }

            Method (TAR7, 7)
            {
                /* All 7 args */
                Local0 = \_SB._KFS._OPS.ADD_ (Arg0, Arg1)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Arg2)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Arg3)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Arg4)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Arg5)
                Local0 = \_SB._KFS._OPS.ADD_ (Local0, Arg6)
                
                If (Local0 != 28) { Return (0x0501) }
                PCNT = PCNT + 1
                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 10

                Local0 = TLOC()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TNAM()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TARG(42)
                If (Local0 != 0) { Return (Local0) }

                Local0 = TAR2(10, 20, 30)
                If (Local0 != 0) { Return (Local0) }

                Local0 = TAR7(1, 2, 3, 4, 5, 6, 7)
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
