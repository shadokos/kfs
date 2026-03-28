/*
 * AML Advanced References & Store Targets Test Suite
 * Tests: Store to DerefOf target, Store to Index target,
 * CopyObject semantics, CondRefOf edge cases.
 *
 * Evaluate: acpi_eval \_SB._KFS.TRF2.MAIN
 */
DefinitionBlock ("test_ref2.aml", "SSDT", 2, "KFS", "TESTREF2", 1)
{
    External (\_SB._KFS, DeviceObj)

    Scope (\_SB._KFS)
    {
        Device (TRF2)
        {
            Name (_HID, "KFST0012")
            Name (PCNT, 0)
            Name (TCNT, 0)

            /* Named objects for reference tests */
            Name (XVAL, 10)
            Name (YVAL, 20)

            /* ---- Store through DerefOf(RefOf(Named)) ---- */
            Method (TDRF, 0, Serialized)
            {
                /* Create reference to named object */
                XVAL = 10
                Local0 = RefOf (XVAL)

                /* Write through the reference */
                DerefOf (Local0) = 99
                If (XVAL != 99) { Return (0x0101) }
                PCNT = PCNT + 1

                /* Write a different value */
                DerefOf (Local0) = 42
                If (XVAL != 42) { Return (0x0102) }
                PCNT = PCNT + 1

                /* Two references to different objects */
                YVAL = 20
                Local1 = RefOf (YVAL)
                DerefOf (Local1) = 77
                If (YVAL != 77) { Return (0x0103) }
                PCNT = PCNT + 1

                /* Verify first ref still points to XVAL */
                If (DerefOf (Local0) != 42) { Return (0x0104) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- Store to Index target (Buffer/Package element) ---- */
            Method (TIDX, 0, Serialized)
            {
                /* Buffer element write via Index */
                Name (BUF1, Buffer() {0x00, 0x00, 0x00, 0x00})
                Index (BUF1, 1) = 0xAB
                Local0 = DerefOf (Index (BUF1, 1))
                If (Local0 != 0xAB) { Return (0x0201) }
                PCNT = PCNT + 1

                /* Verify other bytes untouched */
                Local0 = DerefOf (Index (BUF1, 0))
                If (Local0 != 0x00) { Return (0x0202) }
                PCNT = PCNT + 1

                /* Package element write via Index */
                Name (PKG1, Package() {10, 20, 30})
                Index (PKG1, 2) = 99
                Local0 = DerefOf (Index (PKG1, 2))
                If (Local0 != 99) { Return (0x0203) }
                PCNT = PCNT + 1

                /* Verify other elements untouched */
                Local0 = DerefOf (Index (PKG1, 0))
                If (Local0 != 10) { Return (0x0204) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- CopyObject semantics ---- */
            Method (TCPY, 0, Serialized)
            {
                /* CopyObject integer to integer */
                Name (COBJ, 42)
                CopyObject (99, COBJ)
                If (COBJ != 99) { Return (0x0301) }
                PCNT = PCNT + 1

                /* CopyObject to local */
                CopyObject (123, Local0)
                If (Local0 != 123) { Return (0x0302) }
                PCNT = PCNT + 1

                /* CopyObject preserves value through read-back */
                Name (COB2, 0)
                CopyObject (0xDEAD, COB2)
                Local1 = COB2
                If (Local1 != 0xDEAD) { Return (0x0303) }
                PCNT = PCNT + 1

                Return (0)
            }

            /* ---- CondRefOf edge cases ---- */
            Method (TCRF, 0, Serialized)
            {
                /* Existing named object: returns True */
                If (CondRefOf (XVAL, Local0)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0401) }

                /* Non-existent name: returns False */
                If (CondRefOf (ZZZZ, Local1)) {
                    Return (0x0402)
                }
                PCNT = PCNT + 1

                /* Initialized local: returns True */
                Local2 = 55
                If (CondRefOf (Local2, Local3)) {
                    PCNT = PCNT + 1
                } Else { Return (0x0403) }

                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 14

                Local0 = TDRF()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TIDX()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCPY()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TCRF()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
