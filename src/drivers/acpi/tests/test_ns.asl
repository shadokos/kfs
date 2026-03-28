/*
 * AML Namespace Features Test Suite
 * Tests: _OSI, RefOf/DerefOf references, Alias
 *
 * Evaluate: acpi_eval \_SB._KFS.TNS0.MAIN
 */
DefinitionBlock ("test_ns.aml", "SSDT", 1, "KFS", "TESTNS__", 1)
{
    External (\_SB._KFS, DeviceObj)

    Scope (\_SB._KFS)
    {
        Device (TNS0)
        {
            Name (_HID, "KFST0010")
            Name (PCNT, 0)
            Name (TCNT, 0)

            /* Parse-time alias target for TALS */
            Name (DOBJ, 77)
            Alias (DOBJ, DALJ)

            Method (TOSI, 0, Serialized)
            {
                /* _OSI with "Linux" — should be supported */
                If (_OSI("Linux"))
                {
                    PCNT = PCNT + 1
                }
                Else
                {
                    Return (0x0101)
                }

                /* _OSI with "Windows 2009" — should be supported */
                If (_OSI("Windows 2009"))
                {
                    PCNT = PCNT + 1
                }
                Else
                {
                    Return (0x0102)
                }

                /* _OSI with unknown string — should return False */
                If (_OSI("UnknownOS 9999"))
                {
                    Return (0x0103)
                }
                PCNT = PCNT + 1

                /* _OSI with "Windows 2015" (Win 10) */
                If (_OSI("Windows 2015"))
                {
                    PCNT = PCNT + 1
                }
                Else
                {
                    Return (0x0104)
                }

                Return (0)
            }

            Method (TREF, 0, Serialized)
            {
                /* RefOf a named object, DerefOf to read back */
                Name (XOBJ, 100)
                Local0 = RefOf (XOBJ)
                Local1 = DerefOf (Local0)
                If (Local1 != 100) { Return (0x0201) }
                PCNT = PCNT + 1

                /* Write through DerefOf(reference) */
                Store (200, DerefOf (Local0))
                If (XOBJ != 200) { Return (0x0202) }
                PCNT = PCNT + 1

                /* Verify original ref still valid after write */
                Local2 = DerefOf (Local0)
                If (Local2 != 200) { Return (0x0203) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (TALS, 0, Serialized)
            {
                /* Parse-time alias (created at device scope) */
                If (DALJ != 77) { Return (0x0301) }
                PCNT = PCNT + 1

                /* Runtime alias inside method */
                Name (ROBJ, 88)
                Alias (ROBJ, RALJ)
                If (RALJ != 88) { Return (0x0302) }
                PCNT = PCNT + 1

                Return (0)
            }

            Method (MAIN, 0, Serialized)
            {
                PCNT = 0
                TCNT = 9

                Local0 = TOSI ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TREF ()
                If (Local0 != 0) { Return (Local0) }

                Local0 = TALS ()
                If (Local0 != 0) { Return (Local0) }

                Return (0)
            }
        }
    }
}
